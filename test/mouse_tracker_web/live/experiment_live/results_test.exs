defmodule MouseTrackerWeb.ExperimentLive.ResultsTest do
  use MouseTrackerWeb.ConnCase

  import Phoenix.LiveViewTest
  import MouseTracker.ExperimentsFixtures

  setup :register_and_log_in_user

  test "renders metrics, ROI zones and heatmap for a done video", %{conn: conn, user: user} do
    experiment = experiment_fixture(user)
    cal = calibration_fixture(user)

    video =
      video_fixture(experiment, cal, %{
        status: "done",
        filename: "m01.mp4",
        duration_seconds: 100.0
      })

    result =
      tracking_result_fixture(video, %{
        distance_cm: 3058.0,
        speed_mean_cm: 2.95,
        speed_median_cm: 2.33,
        heatmap_path: "/uploads/results/#{video.id}/heatmap.png"
      })

    roi = roi_fixture(video, %{name: "Center"})
    roi_time_fixture(roi, result, %{seconds: 70.0})

    {:ok, _lv, html} = live(conn, ~p"/experiments/#{experiment.id}/results")

    assert html =~ "Results"
    assert html =~ "3058.0"
    assert html =~ "Center"
    assert html =~ "70.0"
    assert html =~ "/uploads/results/#{video.id}/heatmap.png"
  end

  test "shows an empty state when the experiment has no analyzed videos", %{
    conn: conn,
    user: user
  } do
    experiment = experiment_fixture(user)

    {:ok, _lv, html} = live(conn, ~p"/experiments/#{experiment.id}/results")

    assert html =~ "No analyzed videos yet"
  end
end
