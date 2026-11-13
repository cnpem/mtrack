defmodule MouseTrackerWeb.UserLive.SettingsTest do
  use MouseTrackerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import MouseTracker.AccountsFixtures

  describe "Settings page" do
    test "renders the profile form", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/settings")

      assert html =~ "Account Settings"
      assert html =~ "Save profile"
    end

    test "points e-mail/password management at the Keycloak account console", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/settings")

      assert html =~ "Keycloak"
      # Derived from the configured issuer, so it follows the deployment.
      assert html =~ "https://keycloak.example.org/realms/mtrack/account"
    end

    test "no longer renders the local e-mail and password forms", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/settings")

      refute html =~ "Change Email"
      refute html =~ "Save Password"
      refute html =~ "password_form"
      refute html =~ "email_form"
    end

    test "redirects if user is not logged in", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/users/settings")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end

    test "redirects if user is not in sudo mode", %{conn: conn} do
      {:ok, conn} =
        conn
        |> log_in_user(user_fixture(),
          token_authenticated_at: DateTime.add(DateTime.utc_now(:second), -11, :minute)
        )
        |> live(~p"/users/settings")
        |> follow_redirect(conn, ~p"/users/log-in")

      assert conn.resp_body =~ "You must re-authenticate to access this page."
    end
  end

  describe "update profile form" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "updates name and institution", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> form("#profile_form", %{
          "user" => %{"name" => "New Name", "institution" => "MIT"}
        })
        |> render_submit()

      assert result =~ "Profile updated successfully"
    end

    test "renders errors with invalid data (phx-submit)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> form("#profile_form", %{"user" => %{"name" => ""}})
        |> render_submit()

      assert result =~ "can&#39;t be blank"
    end
  end
end
