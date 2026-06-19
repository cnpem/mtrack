defmodule MouseTrackerWeb.PageController do
  use MouseTrackerWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
