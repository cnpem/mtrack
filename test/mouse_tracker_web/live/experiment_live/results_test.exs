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
        speed_max_cm: 9.1,
        thigmotaxis_pct: 63.2,
        path_tortuosity: 3.7,
        immobility_seconds: 41.0,
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
    # secondary metric cards (Sprint 3.4)
    assert html =~ "Thigmotaxis"
    assert html =~ "63.2"
    assert html =~ "Path tortuosity"
    assert html =~ "3.7"
    assert html =~ "Immobility"
    assert html =~ "41.0"
  end

  test "shows an empty state when the experiment has no analyzed videos", %{
    conn: conn,
    user: user
  } do
    experiment = experiment_fixture(user)

    {:ok, _lv, html} = live(conn, ~p"/experiments/#{experiment.id}/results")

    assert html =~ "No analyzed videos yet"
  end

  describe "por subject tab" do
    setup %{user: user} do
      subject = subject_fixture(user, %{name: "M-01"})
      cal = calibration_fixture(user, %{name: "Campo A"})
      experiment = experiment_fixture(user)

      v1 =
        video_fixture(experiment, cal, %{
          status: "done",
          subject_id: subject.id,
          filename: "a.mp4",
          duration_seconds: 100.0
        })

      v2 =
        video_fixture(experiment, cal, %{
          status: "done",
          subject_id: subject.id,
          filename: "b.mp4",
          duration_seconds: 100.0
        })

      tracking_result_fixture(v1, %{
        distance_cm: 100.0,
        immobility_seconds: 10.0,
        heatmap_path: "/uploads/results/#{v1.id}/heatmap.png"
      })

      tracking_result_fixture(v2, %{
        distance_cm: 300.0,
        immobility_seconds: 40.0,
        heatmap_path: "/uploads/results/#{v2.id}/heatmap.png"
      })

      %{subject: subject, cal: cal, experiment: experiment, v1: v1, v2: v2}
    end

    test "groups heatmaps by calibration and shows mean ± sd across the subject's videos", %{
      conn: conn,
      experiment: experiment,
      v1: v1,
      v2: v2
    } do
      {:ok, _lv, html} = live(conn, ~p"/experiments/#{experiment.id}/results?tab=subject")

      assert html =~ "Campo A"
      assert html =~ "2 video(s)"
      assert html =~ "/uploads/results/#{v1.id}/heatmap.png"
      assert html =~ "/uploads/results/#{v2.id}/heatmap.png"
      # mean = (100+300)/2 = 200, sd = sqrt(((100-200)^2+(300-200)^2)/1) = 141.4
      assert html =~ "200.0 ± 141.4"
      # immobility aggregated in raw seconds: mean = (10+40)/2 = 25, sd = 21.2
      assert html =~ "25.0 ± 21.2"
    end

    test "switching to per-video shows each video's own metrics instead of the average", %{
      conn: conn,
      experiment: experiment
    } do
      {:ok, lv, _html} = live(conn, ~p"/experiments/#{experiment.id}/results?tab=subject")

      html =
        lv
        |> element("button[phx-value-view='per_video']")
        |> render_click()

      assert html =~ "100.0 cm"
      assert html =~ "300.0 cm"
      refute html =~ "200.0 ± 141.4"
    end

    test "the experiment scope filter narrows the subject's videos to one experiment", %{
      conn: conn,
      user: user,
      subject: subject,
      cal: cal,
      experiment: experiment
    } do
      other_experiment = experiment_fixture(user)

      v3 =
        video_fixture(other_experiment, cal, %{
          status: "done",
          subject_id: subject.id,
          filename: "c.mp4",
          duration_seconds: 100.0
        })

      tracking_result_fixture(v3, %{
        distance_cm: 500.0,
        heatmap_path: "/uploads/results/#{v3.id}/heatmap.png"
      })

      {:ok, lv, html} = live(conn, ~p"/experiments/#{experiment.id}/results?tab=subject")

      assert html =~ "a.mp4"
      assert html =~ "b.mp4"
      assert html =~ "c.mp4"

      html =
        lv
        |> form("form[phx-change='set_scope_experiment']", %{
          "scope_experiment" => to_string(experiment.id)
        })
        |> render_change()

      assert html =~ "a.mp4"
      assert html =~ "b.mp4"
      refute html =~ "c.mp4"
    end

    test "picking a different subject chip swaps which subject's data is shown", %{
      conn: conn,
      user: user,
      cal: cal,
      experiment: experiment
    } do
      other_subject = subject_fixture(user, %{name: "M-02"})

      v4 =
        video_fixture(experiment, cal, %{
          status: "done",
          subject_id: other_subject.id,
          filename: "d.mp4",
          duration_seconds: 100.0
        })

      tracking_result_fixture(v4, %{
        distance_cm: 999.0,
        heatmap_path: "/uploads/results/#{v4.id}/heatmap.png"
      })

      {:ok, lv, html} = live(conn, ~p"/experiments/#{experiment.id}/results?tab=subject")
      assert html =~ "a.mp4"
      refute html =~ "d.mp4"

      html =
        lv
        |> element("button[phx-value-subject='#{other_subject.id}']")
        |> render_click()

      assert html =~ "d.mp4"
      refute html =~ "a.mp4"
    end
  end
end
