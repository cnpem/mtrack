defmodule MouseTracker.Auth.Config do
  @moduledoc """
  Runtime settings for the Keycloak (OpenID Connect) integration.

  Everything here comes from `config :mouse_tracker, :oidc`, which
  `config/runtime.exs` fills from environment variables, so the same release
  can point at the institutional Keycloak of each deployment:

      KEYCLOAK_ISSUER=https://sso.example.org/realms/mtrack
      KEYCLOAK_CLIENT_ID=mtrack-web
      KEYCLOAK_CLIENT_SECRET=...
      KEYCLOAK_REDIRECT_URI=https://mtrack.example.org/users/auth/keycloak/callback
      KEYCLOAK_POST_LOGOUT_REDIRECT_URI=https://mtrack.example.org/users/log-in

  `redirect_uri` and `post_logout_redirect_uri` are optional: when omitted they
  are derived from `MouseTrackerWeb.Endpoint`, which is correct for dev and for
  any deployment whose endpoint URL matches the public URL. Set them explicitly
  when the app is behind a proxy and the internal/external URLs differ.
  """

  alias MouseTrackerWeb.Endpoint

  @default_scopes "openid profile email"
  @callback_path "/users/auth/keycloak/callback"
  @post_logout_path "/users/log-in"

  @required_keys [:issuer, :client_id, :client_secret]

  @doc "Raw `:oidc` settings, as loaded from config/runtime.exs."
  def settings, do: Application.get_env(:mouse_tracker, :oidc, [])

  @doc "The realm issuer, e.g. `https://sso.example.org/realms/mtrack`."
  def issuer, do: present(settings()[:issuer])

  @doc "The confidential client id registered in Keycloak."
  def client_id, do: present(settings()[:client_id])

  @doc "The client secret (never logged, never rendered)."
  def client_secret, do: present(settings()[:client_secret])

  @doc "Space-separated scopes requested from the provider."
  def scopes_string, do: present(settings()[:scopes]) || @default_scopes

  @doc "Scopes as a list, the shape `Oidcc.create_redirect_url/4` expects."
  def scopes, do: String.split(scopes_string(), ~r/\s+/, trim: true)

  @doc """
  How MTrack authenticates itself to Keycloak's back channel, e.g. the PAR and
  token endpoints.

  This must be pinned. Left to itself, `oidcc` picks the first method the *realm*
  advertises in `token_endpoint_auth_methods_supported` — and Keycloak lists
  `private_key_jwt` and `client_secret_jwt` there for every realm, even when this
  particular client only has a plain client secret. The result is a hard-to-read
  `401 {"error":"invalid_request","error_description":"Authentication failed."}`.

  Override with `KEYCLOAK_CLIENT_AUTH_METHOD` if the client is configured for
  `client_secret_post` or `client_secret_jwt` instead of the default.
  """
  def client_auth_method do
    case present(settings()[:client_auth_method]) do
      nil -> :client_secret_basic
      "client_secret_post" -> :client_secret_post
      "client_secret_jwt" -> :client_secret_jwt
      "client_secret_basic" -> :client_secret_basic
      "private_key_jwt" -> :private_key_jwt
      other -> raise ArgumentError, "unsupported KEYCLOAK_CLIENT_AUTH_METHOD: #{other}"
    end
  end

  @doc "Name of the `Oidcc.ProviderConfiguration.Worker` process."
  def provider_name do
    settings()[:provider_name] || MouseTracker.Auth.OIDC.ProviderConfiguration
  end

  @doc "The `redirect_uri` sent to Keycloak (must match the client config exactly)."
  def redirect_uri do
    present(settings()[:redirect_uri]) || Endpoint.url() <> @callback_path
  end

  @doc "Where Keycloak sends the user after a federated logout."
  def post_logout_redirect_uri do
    present(settings()[:post_logout_redirect_uri]) || Endpoint.url() <> @post_logout_path
  end

  @doc """
  Whether enough is configured to attempt a login.

  Used by the login screen to explain what is missing instead of redirecting to
  a half-built authorization URL.
  """
  def configured?, do: missing_settings() == []

  @doc "Which required settings are still blank (safe to render, contains no values)."
  def missing_settings do
    Enum.reject(@required_keys, fn key -> is_binary(present(settings()[key])) end)
  end

  @doc """
  Options for the `Oidcc.ProviderConfiguration.Worker` child spec.

  `backoff_type` must be one of the atoms `oidcc` understands
  (`:stop`, `:exponential`, `:random`, `:random_exponential`). Only `:stop`
  gives up; the others retry forever, which is what we want: a Keycloak outage
  must not crash-loop the worker (and therefore take the whole app down with it,
  since it runs in the application supervisor). `:random_exponential` spreads
  retries over 1s..30s with jitter.
  """
  def provider_worker_opts do
    %{
      name: provider_name(),
      issuer: issuer(),
      provider_configuration_opts: %{
        # `oidcc` refuses to load metadata whose endpoints are not HTTPS
        # (`{:invalid_config_property, {:uri_https, :userinfo_endpoint}}`). The
        # local `start-dev` Keycloak only speaks HTTP, so the quirk is enabled
        # *only* when the configured issuer itself is plain HTTP: an `https://`
        # issuer keeps full validation, and an `http://` issuer is already
        # cleartext end-to-end, so there is no security left to lose.
        quirks: %{allow_unsafe_http: insecure_issuer?()}
      },
      # Keep retrying instead of giving up: a Keycloak outage at boot time must
      # not take the whole app down, and the worker self-heals as soon as the
      # realm is reachable again. `:random_exponential` is one of the four atoms
      # `oidcc` accepts, and the only ones that never return `:stop` are the
      # non-`:stop` ones — an unknown atom raises FunctionClauseError and
      # crash-loops the worker (which kills the whole application).
      backoff_type: :random_exponential,
      backoff_min: 1_000,
      backoff_max: 30_000
    }
  end

  @doc """
  Whether the configured issuer is plain HTTP (local development only).

  Drives `allow_unsafe_http` above; see the comment there.
  """
  def insecure_issuer? do
    match?("http://" <> _, issuer())
  end

  @doc "Environment variable names for each required setting, for error messages."
  def env_var_for(:issuer), do: "KEYCLOAK_ISSUER"
  def env_var_for(:client_id), do: "KEYCLOAK_CLIENT_ID"
  def env_var_for(:client_secret), do: "KEYCLOAK_CLIENT_SECRET"

  defp present(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp present(_), do: nil
end
