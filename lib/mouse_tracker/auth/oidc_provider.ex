defmodule MouseTracker.Auth.OIDCProvider do
  @moduledoc """
  The seam between the app's login flow and the OpenID Connect client library.

  All Keycloak-specific behaviour lives behind this behaviour, mirroring what
  `MouseTracker.Tracking.PythonPortBehaviour` does for the Python engine: the
  web layer talks to a behaviour, production uses `MouseTracker.Auth.OIDC`, and
  `mix test` swaps in a Mox mock. That means the callback controller can be
  tested for every branch (valid login, replayed `state`, token exchange
  failure, missing e-mail, e-mail collision) without a Keycloak container,
  network, or real credentials.

  The contract is deliberately *claims-shaped* rather than token-shaped: callers
  never see `Oidcc` types, so the mock is trivial to write.
  """

  @typedoc """
  Claims the app actually consumes.

  Everything here has already been verified by the implementation (signature
  against the realm JWKS, `iss`, `aud`, `exp` and the `nonce` echo) — this is
  the only thing the caller is allowed to trust.
  """
  @type claims :: %{
          required(:sub) => String.t(),
          optional(:issuer) => String.t() | nil,
          optional(:email) => String.t() | nil,
          optional(:email_verified) => boolean(),
          optional(:name) => String.t() | nil,
          optional(:username) => String.t() | nil
        }

  @typedoc """
  One-time data that must survive the redirect to Keycloak and back.

  Stored in the Phoenix session (signed cookie) between `c:authorization_url/0`
  and `c:exchange_code/2`, and deleted as soon as it is used.
  """
  @type flow :: %{required(String.t()) => String.t()}

  @doc "Whether the provider is configured well enough to start a login."
  @callback configured?() :: boolean()

  @doc """
  Builds the authorization URL plus the `flow` data to keep in the session.

  The implementation must generate a fresh `state` (CSRF/replay protection), a
  `nonce` (ID token replay protection) and a PKCE verifier on every call.
  """
  @callback authorization_url() :: {:ok, url :: String.t(), flow()} | {:error, term()}

  @doc """
  Exchanges the authorization `code` for a verified set of claims.
  """
  @callback exchange_code(code :: String.t(), flow()) :: {:ok, claims()} | {:error, term()}

  @doc """
  RP-initiated logout URL, so logging out of MTrack also ends the Keycloak SSO
  session. Returns `:not_supported` when the realm does not advertise an
  `end_session_endpoint`; the caller then just clears the local session.
  """
  @callback logout_url() :: {:ok, String.t()} | :not_supported | {:error, term()}
end
