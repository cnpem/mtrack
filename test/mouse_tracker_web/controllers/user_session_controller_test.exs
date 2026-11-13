defmodule MouseTrackerWeb.UserSessionControllerTest do
  @moduledoc """
  Logout only — the login half of this controller no longer exists.

  Credentials are collected by Keycloak and the session is opened by
  `MouseTrackerWeb.OIDCController.callback/2` (see `oidc_controller_test.exs`).
  """

  use MouseTrackerWeb.ConnCase, async: true

  import Mox
  import MouseTracker.AccountsFixtures

  alias MouseTracker.Auth.OIDCProviderMock

  setup :verify_on_exit!

  describe "DELETE /users/log-out" do
    test "clears the local session", %{conn: conn} do
      user = user_fixture()

      conn = conn |> log_in_user(user) |> delete(~p"/users/log-out")

      assert redirected_to(conn) == ~p"/users/log-in"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end

    test "succeeds even if the user is not logged in", %{conn: conn} do
      conn = delete(conn, ~p"/users/log-out")

      assert redirected_to(conn) == ~p"/users/log-in"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end

    test "also ends the Keycloak SSO session when the realm supports it", %{conn: conn} do
      user = user_fixture()

      expect(OIDCProviderMock, :logout_url, fn ->
        {:ok, "https://keycloak.example.org/realms/mtrack/protocol/openid-connect/logout?x=1"}
      end)

      conn = conn |> log_in_user(user) |> delete(~p"/users/log-out")

      # Without id_token_hint, Keycloak shows a confirmation page and then
      # returns to post_logout_redirect_uri (the MTrack login screen).
      assert redirected_to(conn) ==
               "https://keycloak.example.org/realms/mtrack/protocol/openid-connect/logout?x=1"

      refute get_session(conn, :user_token)
    end

    test "still logs out locally when the provider lookup fails", %{conn: conn} do
      user = user_fixture()

      expect(OIDCProviderMock, :logout_url, fn -> {:error, :provider_unavailable} end)

      conn = conn |> log_in_user(user) |> delete(~p"/users/log-out")

      assert redirected_to(conn) == ~p"/users/log-in"
      refute get_session(conn, :user_token)
    end
  end
end
