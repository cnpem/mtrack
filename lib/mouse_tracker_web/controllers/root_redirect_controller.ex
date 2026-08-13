defmodule MouseTrackerWeb.RootRedirectController do
  use MouseTrackerWeb, :controller

  alias MouseTrackerWeb.UserAuth

  def index(conn, _params) do
    redirect(conn, to: UserAuth.root_path(conn))
  end
end
