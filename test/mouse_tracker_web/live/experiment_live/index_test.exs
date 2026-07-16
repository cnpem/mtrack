defmodule MouseTrackerWeb.ExperimentLive.IndexTest do
  use MouseTrackerWeb.ConnCase

  import Phoenix.LiveViewTest
  import MouseTracker.ExperimentsFixtures

  alias MouseTracker.Workers.VideoProcessingWorker

  setup :register_and_log_in_user

  setup %{user: user} do
    experiment = experiment_fixture(user)
    video = video_fixture(experiment, nil, %{status: "processing"})

    %{experiment: experiment, video: video}
  end

  # Scoped to the experiment's <li> card, since the status tab bar (All/Done/
  # Processing/Pending) always renders all four labels regardless of state.
  defp card_html(lv, experiment), do: lv |> element("li", experiment.name) |> render()

  test "lists experiments with their aggregated status", %{conn: conn, experiment: experiment} do
    {:ok, lv, _html} = live(conn, ~p"/experiments")

    assert card_html(lv, experiment) =~ "Processing"
  end

  test "updates the status pill live when a video's status changes via PubSub", %{
    conn: conn,
    experiment: experiment,
    video: video
  } do
    {:ok, lv, _html} = live(conn, ~p"/experiments")
    assert card_html(lv, experiment) =~ "Processing"

    Phoenix.PubSub.broadcast(
      MouseTracker.PubSub,
      VideoProcessingWorker.topic(video.id),
      {:status, video.id, "done"}
    )

    card = card_html(lv, experiment)
    assert card =~ "Done"
    refute card =~ "Processing"
  end
end
