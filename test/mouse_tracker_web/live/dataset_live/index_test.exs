defmodule MouseTrackerWeb.DatasetLive.IndexTest do
  use MouseTrackerWeb.ConnCase

  import Phoenix.LiveViewTest
  import MouseTracker.ExperimentsFixtures

  alias MouseTracker.Accounts.Scope
  alias MouseTracker.Experiments.Subjects
  alias MouseTracker.Workers.VideoProcessingWorker

  setup :register_and_log_in_user

  setup %{user: user} do
    cal = calibration_fixture(user, %{px_per_10cm: 64.2})
    subject = subject_fixture(user, %{name: "M-017", genotype: "WT"})
    exp = experiment_fixture(user, %{name: "Open Field"})

    done =
      video_fixture(exp, cal, %{
        filename: "trial1.mp4",
        status: "done",
        subject_id: subject.id,
        duration_seconds: 300.0,
        fps: 30,
        file_size_bytes: 184 * 1024 * 1024
      })

    tracking_result_fixture(done, %{distance_cm: 42.3, speed_mean_cm: 3.1})

    pending =
      video_fixture(exp, nil, %{filename: "baseline.mp4", status: "pending"})

    %{exp: exp, subject: subject, done: done, pending: pending}
  end

  test "lists the user's videos with metadata across the library", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/datasets")

    assert html =~ "Datasets"
    assert html =~ "trial1.mp4"
    assert html =~ "baseline.mp4"
    # duration · fps and subject
    assert html =~ "5:00"
    assert html =~ "M-017"
    # calibration px/cm (64.2 px/10cm -> 6.4 px/cm)
    assert html =~ "6.4 px/cm"
    # metrics preview for the done video
    assert html =~ "42.3 cm"
  end

  test "only shows videos owned by the current user", %{conn: conn} do
    other = MouseTracker.AccountsFixtures.user_fixture()
    other_exp = experiment_fixture(other)
    video_fixture(other_exp, nil, %{filename: "someone_elses.mp4"})

    {:ok, _lv, html} = live(conn, ~p"/datasets")

    refute html =~ "someone_elses.mp4"
  end

  test "filters by status", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/datasets")

    html = lv |> element("button[phx-value-status='pending']") |> render_click()

    assert html =~ "baseline.mp4"
    refute html =~ "trial1.mp4"
  end

  test "searches by filename", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/datasets")

    html =
      lv
      |> form("form[phx-change='search']", %{"query" => "baseline"})
      |> render_change()

    assert html =~ "baseline.mp4"
    refute html =~ "trial1.mp4"
  end

  test "toggles to the by-subject view showing an aggregate", %{conn: conn, subject: subject} do
    {:ok, lv, _html} = live(conn, ~p"/datasets")

    html = lv |> element("button[phx-value-view='subject']") |> render_click()

    assert html =~ subject.name
    # aggregate stat card over the subject's done video(s)
    assert html =~ "Distance"
    assert html =~ "1 tracked"
  end

  test "the search bar also matches by subject group", %{conn: conn, user: user, subject: subject} do
    {:ok, _} = Subjects.update_subject(Scope.for_user(user), subject, %{group: "Control"})

    {:ok, lv, _html} = live(conn, ~p"/datasets")

    html =
      lv
      |> form("form[phx-change='search']", %{"query" => "Control"})
      |> render_change()

    assert html =~ "trial1.mp4"
    refute html =~ "baseline.mp4"
  end

  test "toggles to the by-group view showing an aggregate, with ungrouped videos bucketed separately",
       %{conn: conn, user: user, subject: subject} do
    {:ok, _} = Subjects.update_subject(Scope.for_user(user), subject, %{group: "Control"})

    {:ok, lv, _html} = live(conn, ~p"/datasets")

    html = lv |> element("button[phx-value-view='group']") |> render_click()

    assert html =~ "Control"
    assert html =~ "Distance"
    assert html =~ "1 tracked"
    assert html =~ "Ungrouped"
    assert html =~ "baseline.mp4"
  end

  test "updates the status pill live when a video's status changes via PubSub", %{
    conn: conn,
    pending: pending
  } do
    {:ok, lv, _html} = live(conn, ~p"/datasets")

    row = fn -> lv |> element("tr", "baseline.mp4") |> render() end
    assert row.() =~ "Pending"

    Phoenix.PubSub.broadcast(
      MouseTracker.PubSub,
      VideoProcessingWorker.topic(pending.id),
      {:status, pending.id, "done"}
    )

    assert row.() =~ "Done"
    refute row.() =~ "Pending"
  end

  test "shows an empty state when the user has no videos" do
    conn = log_in_user(build_conn(), MouseTracker.AccountsFixtures.user_fixture())

    {:ok, _lv, html} = live(conn, ~p"/datasets")

    assert html =~ "No videos yet"
  end
end
