defmodule MouseTrackerWeb.OIDCControllerTest do
  @moduledoc """
  The Keycloak glue, tested without Keycloak.

  `MouseTracker.Auth.OIDCProviderMock` stands in for the provider, so every
  branch of the callback is reachable: a fresh identity, a returning one, a
  replayed `state`, a failed token exchange, a missing e-mail and the
  account-takeover attempt that the linking policy must refuse.
  """

  use MouseTrackerWeb.ConnCase, async: true

  import Mox
  import MouseTracker.AccountsFixtures

  alias MouseTracker.Accounts
  alias MouseTracker.Auth.OIDCProviderMock

  setup :verify_on_exit!

  @issuer "https://keycloak.example.org/realms/mtrack"

  @claims %{
    sub: "d1c2b3a4-sub",
    issuer: @issuer,
    email: "novo@example.org",
    email_verified: true,
    name: "Novo Pesquisador",
    username: "novo"
  }

  defp flow(overrides \\ %{}) do
    Map.merge(
      %{"state" => "state-1", "nonce" => "nonce-1", "pkce_verifier" => "verifier-1"},
      overrides
    )
  end

  defp callback(conn, flow, query \\ "code=code-1&state=state-1") do
    conn
    |> init_test_session(%{oidc_flow: flow})
    |> get("/users/auth/keycloak/callback?" <> query)
  end

  describe "GET /users/auth/keycloak" do
    test "stores the one-time flow in the session and redirects to Keycloak", %{conn: conn} do
      flow = flow()

      expect(OIDCProviderMock, :authorization_url, fn ->
        {:ok, "https://keycloak.example.org/realms/mtrack/protocol/openid-connect/auth?x=1", flow}
      end)

      conn = get(conn, ~p"/users/auth/keycloak")

      assert redirected_to(conn) ==
               "https://keycloak.example.org/realms/mtrack/protocol/openid-connect/auth?x=1"

      assert get_session(conn, :oidc_flow) == flow
    end

    test "accepts a provider that returns iodata instead of a binary", %{conn: conn} do
      # `:oidcc.create_redirect_url/4` returns an iolist; handing that straight
      # to `redirect/2` raises in `Plug.HTML.html_escape/1` and produced a 500.
      flow = flow()

      expect(OIDCProviderMock, :authorization_url, fn ->
        {:ok, ["https://keycloak.example.org/auth", "?", "client_id=mtrack-web"], flow}
      end)

      conn = get(conn, ~p"/users/auth/keycloak")

      assert redirected_to(conn) ==
               "https://keycloak.example.org/auth?client_id=mtrack-web"
    end

    test "explains a misconfigured deployment instead of redirecting to a broken URL", %{
      conn: conn
    } do
      expect(OIDCProviderMock, :authorization_url, fn -> {:error, :not_configured} end)

      conn = get(conn, ~p"/users/auth/keycloak")

      assert redirected_to(conn) == ~p"/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "not configured"
      refute get_session(conn, :oidc_flow)
    end
  end

  describe "GET /users/auth/keycloak/callback - success" do
    test "provisions a brand new user and opens a normal MTrack session", %{conn: conn} do
      expect(OIDCProviderMock, :exchange_code, fn "code-1", received_flow ->
        assert received_flow["pkce_verifier"] == "verifier-1"
        {:ok, @claims}
      end)

      conn = callback(conn, flow())

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/experiments"
      # The one-time flow must not survive the login.
      refute get_session(conn, :oidc_flow)

      user = Accounts.get_user_by_email("novo@example.org")
      assert user.idp_sub == "d1c2b3a4-sub"
      assert user.idp_issuer == @issuer
      assert user.idp_username == "novo"
      assert user.name == "Novo Pesquisador"
      assert user.confirmed_at
      # Keycloak owns the credentials: no local password is ever stored.
      refute user.hashed_password
    end

    test "signs the same person in again without duplicating the row", %{conn: conn} do
      expect(OIDCProviderMock, :exchange_code, 2, fn _, _ -> {:ok, @claims} end)

      callback(conn, flow())
      first = Accounts.get_user_by_email("novo@example.org")

      callback(build_conn(), flow())

      assert Accounts.get_user_by_email("novo@example.org").id == first.id
    end

    test "honours the deep link the user was trying to reach", %{conn: conn} do
      expect(OIDCProviderMock, :exchange_code, fn _, _ -> {:ok, @claims} end)

      conn =
        conn
        |> init_test_session(%{oidc_flow: flow(), user_return_to: "/datasets"})
        |> get("/users/auth/keycloak/callback?code=code-1&state=state-1")

      assert redirected_to(conn) == "/datasets"
    end

    test "links an existing local account when the e-mail is verified", %{conn: conn} do
      existing = user_fixture(%{email: "novo@example.org"})

      expect(OIDCProviderMock, :exchange_code, fn _, _ -> {:ok, @claims} end)

      callback(conn, flow())

      linked = Accounts.get_user!(existing.id)
      assert linked.idp_sub == "d1c2b3a4-sub"
    end
  end

  describe "GET /users/auth/keycloak/callback - rejections" do
    test "refuses a state that does not match the session, without exchanging the code", %{
      conn: conn
    } do
      expect(OIDCProviderMock, :exchange_code, 0, fn _, _ -> {:ok, @claims} end)

      conn = callback(conn, flow(), "code=code-1&state=stolen-state")

      assert redirected_to(conn) == ~p"/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "expired"
      refute get_session(conn, :user_token)
    end

    test "refuses a callback with no login flow in the session at all", %{conn: conn} do
      expect(OIDCProviderMock, :exchange_code, 0, fn _, _ -> {:ok, @claims} end)

      conn = get(conn, "/users/auth/keycloak/callback?code=code-1&state=state-1")

      assert redirected_to(conn) == ~p"/users/log-in"
      refute get_session(conn, :user_token)
    end

    test "surfaces a token exchange failure", %{conn: conn} do
      expect(OIDCProviderMock, :exchange_code, fn _, _ ->
        {:error, {:token_exchange, :invalid_grant}}
      end)

      conn = callback(conn, flow())

      assert redirected_to(conn) == ~p"/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error)
      refute get_session(conn, :user_token)
    end

    test "does not create a user when Keycloak returns no e-mail", %{conn: conn} do
      expect(OIDCProviderMock, :exchange_code, fn _, _ ->
        {:ok, Map.merge(@claims, %{email: nil})}
      end)

      conn = callback(conn, flow())

      assert redirected_to(conn) == ~p"/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "e-mail"
      refute get_session(conn, :user_token)
      assert Accounts.get_user_by_idp_identity("d1c2b3a4-sub", @issuer) == nil
    end

    test "refuses to take over an existing account using an unverified e-mail", %{conn: conn} do
      existing = user_fixture(%{email: "vitima@example.org"})

      expect(OIDCProviderMock, :exchange_code, fn _, _ ->
        {:ok, Map.merge(@claims, %{email: "vitima@example.org", email_verified: false})}
      end)

      conn = callback(conn, flow())

      assert redirected_to(conn) == ~p"/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "verified"
      refute get_session(conn, :user_token)
      # The victim's account must be untouched.
      assert Accounts.get_user!(existing.id).idp_sub == nil
    end

    test "handles the error Keycloak sends when the user cancels", %{conn: conn} do
      conn = callback(conn, flow(), "error=access_denied&error_description=User+denied")

      assert redirected_to(conn) == ~p"/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "cancelled"
      refute get_session(conn, :user_token)
    end
  end
end
