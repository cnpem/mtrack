defmodule MouseTracker.Auth do
  @moduledoc """
  Entry point for the login flow.

  Selects which `MouseTracker.Auth.OIDCProvider` implementation to use, so
  tests can swap the Keycloak client for a mock:

      config :mouse_tracker, :oidc_provider, MouseTracker.Auth.OIDCProviderMock

  The lookup is done at runtime (not compile time) so a test can override it
  per test case with `Application.put_env/3` if it ever needs to.
  """

  alias MouseTracker.Auth.Config
  alias MouseTracker.Auth.OIDC

  @doc "The configured provider implementation."
  def provider, do: Application.get_env(:mouse_tracker, :oidc_provider, OIDC)

  @doc "Whether the real (non-mock) provider is in use."
  def real_provider?, do: provider() == OIDC

  @doc """
  Whether Keycloak is configured.

  Reads configuration only — never the provider — so UI code can render the
  login screen without stubbing the mock.
  """
  def configured?, do: Config.configured?()

  def authorization_url, do: provider().authorization_url()

  def exchange_code(code, flow), do: provider().exchange_code(code, flow)

  def logout_url, do: provider().logout_url()

  @doc """
  URL of the Keycloak account console, where e-mail and password live now.

  Returns `nil` when SSO is not configured, so the UI can hide the link instead
  of pointing at a broken URL.
  """
  def account_url do
    case Config.issuer() do
      nil -> nil
      issuer -> issuer <> "/account"
    end
  end
end
