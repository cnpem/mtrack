defmodule MouseTracker.Auth.OIDC do
  @moduledoc """
  Real `MouseTracker.Auth.OIDCProvider` implementation, on top of the `oidcc`
  library (OpenID certified, EEF Security WG).

  Everything security-sensitive is delegated:

    * provider discovery + JWKS caching -> `Oidcc.ProviderConfiguration.Worker`
    * PKCE (S256), `state`, `nonce`      -> we generate, `oidcc` sends/validates
    * token exchange + ID token checks   -> `Oidcc.retrieve_token/5` validates
      signature, `iss`, `aud`, `exp` and the `nonce` echo before returning

  We only generate the three one-time secrets and turn the verified ID token
  claims into the app's own `MouseTracker.Auth.OIDCProvider.claims/0` shape.
  """

  @behaviour MouseTracker.Auth.OIDCProvider

  alias MouseTracker.Auth.Config

  # RFC 7636: the verifier is 43..128 characters of unreserved ASCII.
  # 48 random bytes -> 64 base64url characters.
  @pkce_verifier_bytes 48

  @impl true
  def configured?, do: Config.configured?()

  @impl true
  def authorization_url do
    with {:ok, client} <- client() do
      flow = %{
        "state" => random_token(),
        "nonce" => random_token(),
        "pkce_verifier" => random_token(@pkce_verifier_bytes)
      }

      opts = %{
        redirect_uri: client.redirect_uri,
        scopes: client.scopes,
        state: flow["state"],
        nonce: flow["nonce"],
        pkce_verifier: flow["pkce_verifier"],
        preferred_auth_methods: [client.auth_method]
      }

      case Oidcc.create_redirect_url(
             client.provider,
             client.client_id,
             client.client_secret,
             opts
           ) do
        # `:oidcc.create_redirect_url/4` returns an iolist (it concatenates the
        # endpoint, "?" and the query string), not a binary. Normalising here
        # keeps the behaviour's `String.t()` contract honest: a caller that hands
        # the iolist to `redirect/2` gets a 500 from `Plug.HTML.html_escape/1`.
        {:ok, url} -> {:ok, IO.iodata_to_binary(url), flow}
        {:error, reason} -> {:error, {:authorization_url, reason}}
      end
    end
  end

  @impl true
  def exchange_code(code, flow) do
    with {:ok, client} <- client(),
         {:ok, code} <- require_value(code, :missing_code),
         {:ok, verifier} <- require_flow(flow, "pkce_verifier", :missing_pkce_verifier),
         {:ok, nonce} <- require_flow(flow, "nonce", :missing_nonce) do
      opts = %{
        redirect_uri: client.redirect_uri,
        pkce_verifier: verifier,
        nonce: nonce,
        preferred_auth_methods: [client.auth_method]
      }

      case Oidcc.retrieve_token(
             code,
             client.provider,
             client.client_id,
             client.client_secret,
             opts
           ) do
        {:ok, token} -> claims(token, client.issuer)
        {:error, reason} -> {:error, {:token_exchange, reason}}
      end
    end
  end

  @impl true
  def logout_url do
    with {:ok, client} <- client() do
      configuration =
        Oidcc.ProviderConfiguration.Worker.get_provider_configuration(client.provider)

      case Map.get(configuration, :end_session_endpoint) do
        endpoint when is_binary(endpoint) and endpoint != "" ->
          query =
            URI.encode_query(%{
              "client_id" => client.client_id,
              "post_logout_redirect_uri" => Config.post_logout_redirect_uri()
            })

          {:ok, IO.iodata_to_binary([endpoint, "?", query])}

        _ ->
          :not_supported
      end
    end
  rescue
    error -> {:error, {:provider_unavailable, error}}
  end

  ## Claims

  defp claims(%Oidcc.Token{id: %Oidcc.Token.Id{claims: claims}}, issuer) when is_map(claims) do
    case require_value(claims["sub"], :missing_subject) do
      {:ok, sub} ->
        {:ok,
         %{
           sub: sub,
           # `iss` comes from the *verified* ID token; the configured issuer is
           # only a fallback and both are the same value in a correct setup.
           issuer: claims["iss"] || issuer,
           email: claims["email"],
           email_verified: claims["email_verified"] == true,
           name: claims["name"],
           username: claims["preferred_username"]
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp claims(_token, _issuer), do: {:error, :missing_id_token}

  ## Helpers

  defp client do
    if Config.configured?() do
      {:ok,
       %{
         issuer: Config.issuer(),
         client_id: Config.client_id(),
         client_secret: Config.client_secret(),
         redirect_uri: Config.redirect_uri(),
         scopes: Config.scopes(),
         auth_method: Config.client_auth_method(),
         provider: Config.provider_name()
       }}
    else
      {:error, :not_configured}
    end
  end

  defp require_value(value, _error) when is_binary(value) and value != "", do: {:ok, value}
  defp require_value(_value, error), do: {:error, error}

  defp require_flow(flow, key, error) when is_map(flow),
    do: require_value(Map.get(flow, key), error)

  defp require_flow(_flow, _key, error), do: {:error, error}

  defp random_token(bytes \\ 32),
    do: Base.url_encode64(:crypto.strong_rand_bytes(bytes), padding: false)
end
