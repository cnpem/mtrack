defmodule MouseTrackerWeb.UserLive.LoginTest do
  use MouseTrackerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import MouseTracker.AccountsFixtures

  describe "login page" do
    test "offers Keycloak as the way in", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/log-in")

      assert html =~ "Log in"
      assert html =~ "Continue with Keycloak"
      assert html =~ ~s(href="/users/auth/keycloak")
    end

    test "no longer offers local registration or any credentials form", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/log-in")

      # These are the surfaces the Keycloak migration removed: the app must not
      # collect (or accept) credentials itself anymore.
      refute html =~ "Sign up"
      refute html =~ "Log in with email"
      refute html =~ "login_form_magic"
      refute html =~ "login_form_password"
      refute html =~ "Remember me"
    end

    test "does not render the dev shortcut when dev_routes is off", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/log-in")

      refute html =~ "demo@locomo.dev"
    end

    test "asks an already authenticated user to reauthenticate", %{conn: conn} do
      conn = log_in_user(conn, user_fixture())

      {:ok, _lv, html} = live(conn, ~p"/users/log-in")

      assert html =~ "You need to reauthenticate"
      assert html =~ "Continue with Keycloak"
    end
  end
end

defmodule MouseTrackerWeb.UserLive.LoginUnconfiguredTest do
  @moduledoc """
  A deployment that forgot to set the Keycloak environment variables must fail
  loudly on the login screen — not boot with a hard-coded realm, and not send
  the user to a half-built authorization URL.

  `async: false` because it mutates global application config.
  """

  use MouseTrackerWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup do
    previous = Application.get_env(:mouse_tracker, :oidc)

    on_exit(fn -> Application.put_env(:mouse_tracker, :oidc, previous) end)

    Application.put_env(:mouse_tracker, :oidc,
      issuer: nil,
      client_id: nil,
      client_secret: nil,
      scopes: "openid profile email"
    )

    :ok
  end

  test "explains which variables are missing instead of offering a broken button", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/users/log-in")

    refute html =~ "Continue with Keycloak"
    assert html =~ "not configured"
    assert html =~ "KEYCLOAK_ISSUER"
    assert html =~ "KEYCLOAK_CLIENT_ID"
    assert html =~ "KEYCLOAK_CLIENT_SECRET"
  end
end
