defmodule MouseTrackerWeb.DevLoginController do
  @moduledoc """
  Development-only shortcut for signing in as a local user without going through
  Keycloak.

  Keycloak is the only production login path. But without this, working on the
  app locally would require a reachable realm, a registered client and a test
  user before you can see any screen — which is a painful loop for UI work.

  This route is only mounted inside the `:dev_routes` block of the router, which
  is enabled exclusively by `config :mouse_tracker, dev_routes: true`
  (`config/dev.exs`). In a production release the module is unreachable: the
  route is not compiled into the router when the flag is off.
  """

  use MouseTrackerWeb, :controller

  alias MouseTracker.Accounts
  alias MouseTracker.Accounts.User
  alias MouseTrackerWeb.UserAuth

  def create(conn, %{"email" => email}) when is_binary(email) do
    case Accounts.get_user_by_email(email) do
      %User{} = user ->
        conn
        |> put_flash(:info, "Dev sign-in as #{user.email} (no Keycloak involved).")
        |> UserAuth.log_in_user(user)

      nil ->
        conn
        |> put_flash(
          :error,
          "No local user with #{email}. Run `mix run priv/repo/seeds_locomo.exs` first."
        )
        |> redirect(to: ~p"/users/log-in")
    end
  end

  def create(conn, _params),
    do: conn |> put_flash(:error, "Missing ?email=.") |> redirect(to: ~p"/users/log-in")
end
