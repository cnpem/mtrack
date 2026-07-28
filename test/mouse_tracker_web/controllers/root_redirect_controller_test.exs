defmodule MouseTrackerWeb.RootRedirectControllerTest do
  use MouseTrackerWeb.ConnCase, async: true

  import MouseTracker.AccountsFixtures

  test "redirects to /users/log-in when signed out", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/users/log-in"
  end

  test "redirects to /experiments when signed in", %{conn: conn} do
    conn =
      conn
      |> log_in_user(user_fixture())
      |> get(~p"/")

    assert redirected_to(conn) == ~p"/experiments"
  end
end
