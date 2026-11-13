defmodule MouseTrackerWeb.UserSessionController do
  @moduledoc """
  Logout.

  Login no longer happens here: credentials are collected by Keycloak and the
  session is opened by `MouseTrackerWeb.OIDCController.callback/2`.
  """

  use MouseTrackerWeb, :controller

  alias MouseTracker.Auth
  alias MouseTrackerWeb.UserAuth

  def delete(conn, _params) do
    # Order matters: `clear_user_session/1` wipes the session (flash included),
    # so the flash is written afterwards, and the redirect is written exactly
    # once — at the end.
    conn =
      conn
      |> UserAuth.clear_user_session()
      |> put_flash(:info, "Logged out successfully.")

    # Logging out of MTrack alone would leave the Keycloak SSO session alive, so
    # the next click on "Log in" would silently sign the user straight back in.
    # When the realm advertises an `end_session_endpoint`, finish the job there.
    case Auth.logout_url() do
      {:ok, url} -> redirect(conn, external: url)
      _ -> redirect(conn, to: ~p"/users/log-in")
    end
  end
end
