defmodule MouseTrackerWeb.ExperimentLive.NewTest do
  use MouseTrackerWeb.ConnCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "renders the upload step first", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/experiments/new")

    assert html =~ "New experiment · Step 1 of 3"
    assert html =~ "Upload videos"
    assert html =~ "Batch"
  end

  test "guards later steps back to upload when there are no files", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/experiments/new"}}} =
             live(conn, ~p"/experiments/new/roi")
  end
end
