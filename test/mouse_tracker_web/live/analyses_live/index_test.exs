defmodule MouseTrackerWeb.AnalysesLive.IndexTest do
  use MouseTrackerWeb.ConnCase

  import Ecto.Query
  import Phoenix.LiveViewTest
  import MouseTracker.ExperimentsFixtures
  import MouseTracker.AccountsFixtures

  alias MouseTracker.Repo
  alias MouseTracker.Experiments.{Rois, Video}

  setup :register_and_log_in_user

  defp set_inserted_at(video, %DateTime{} = dt) do
    Repo.update_all(from(v in Video, where: v.id == ^video.id), set: [inserted_at: dt])
  end

  test "shows an empty state when the user has no subjects", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/analyses")

    assert html =~ "No subjects yet"
  end

  describe "with a subject" do
    setup %{user: user} do
      subject = subject_fixture(user, %{name: "M-01"})
      cal = calibration_fixture(user)
      experiment = experiment_fixture(user)

      %{subject: subject, cal: cal, experiment: experiment}
    end

    test "shows an empty state when the subject has no analyzed sessions", %{
      conn: conn,
      subject: subject
    } do
      {:ok, _lv, html} = live(conn, ~p"/analyses?subjects=#{subject.id}")

      assert html =~ subject.name
      assert html =~ "No analyzed sessions have a value for this metric yet"
    end

    test "renders the trend chart and a chronologically-ordered sessions table", %{
      conn: conn,
      subject: subject,
      cal: cal,
      experiment: experiment
    } do
      v1 =
        video_fixture(experiment, cal, %{
          status: "done",
          subject_id: subject.id,
          filename: "a.mp4"
        })

      v2 =
        video_fixture(experiment, cal, %{
          status: "done",
          subject_id: subject.id,
          filename: "b.mp4"
        })

      set_inserted_at(v1, ~U[2026-01-01 00:00:00Z])
      set_inserted_at(v2, ~U[2026-02-01 00:00:00Z])

      tracking_result_fixture(v1, %{distance_cm: 100.0})
      tracking_result_fixture(v2, %{distance_cm: 300.0})

      {:ok, _lv, html} = live(conn, ~p"/analyses?subjects=#{subject.id}")

      assert html =~ "<svg"
      assert html =~ "100.0"
      assert html =~ "300.0"
      # chronological (ascending) order in the table: a.mp4 before b.mp4
      assert html =~ ~r/a\.mp4.*b\.mp4/s
    end

    test "a single session shows a note instead of a broken chart", %{
      conn: conn,
      subject: subject,
      cal: cal,
      experiment: experiment
    } do
      v1 =
        video_fixture(experiment, cal, %{
          status: "done",
          subject_id: subject.id,
          filename: "solo.mp4"
        })

      tracking_result_fixture(v1, %{distance_cm: 42.0})

      {:ok, _lv, html} = live(conn, ~p"/analyses?subjects=#{subject.id}")

      assert html =~ "<svg"
      assert html =~ "Only one session so far"
    end

    test "toggling another subject's chip adds it to the comparison instead of replacing",
         %{
           conn: conn,
           user: user,
           subject: subject,
           cal: cal,
           experiment: experiment
         } do
      other_subject = subject_fixture(user, %{name: "M-02"})

      v1 =
        video_fixture(experiment, cal, %{
          status: "done",
          subject_id: subject.id,
          filename: "a.mp4"
        })

      v2 =
        video_fixture(experiment, cal, %{
          status: "done",
          subject_id: other_subject.id,
          filename: "b.mp4"
        })

      tracking_result_fixture(v1, %{})
      tracking_result_fixture(v2, %{})

      {:ok, lv, html} = live(conn, ~p"/analyses?subjects=#{subject.id}")
      assert html =~ "a.mp4"
      refute html =~ "b.mp4"

      html =
        lv
        |> form("#analyses-subject-picker", %{"subject" => other_subject.id})
        |> render_change()

      # toggling ON: both subjects are now selected, so both sessions show
      assert html =~ "a.mp4"
      assert html =~ "b.mp4"

      html =
        lv
        |> element("button[phx-value-subject='#{subject.id}']")
        |> render_click()

      # toggling the first one back OFF leaves only the second selected
      assert html =~ "b.mp4"
      refute html =~ "a.mp4"
    end

    test "deselecting the last subject shows the empty-selection state", %{
      conn: conn,
      subject: subject
    } do
      {:ok, lv, _html} = live(conn, ~p"/analyses?subjects=#{subject.id}")

      html =
        lv
        |> element("button[phx-value-subject='#{subject.id}']")
        |> render_click()

      assert html =~ "No subject or group selected"
    end

    test "comparing two subjects overlays both series and lists both subjects' sessions", %{
      conn: conn,
      user: user,
      subject: subject,
      cal: cal,
      experiment: experiment
    } do
      other_subject = subject_fixture(user, %{name: "M-02"})

      v1 =
        video_fixture(experiment, cal, %{
          status: "done",
          subject_id: subject.id,
          filename: "a.mp4"
        })

      v2 =
        video_fixture(experiment, cal, %{
          status: "done",
          subject_id: other_subject.id,
          filename: "b.mp4"
        })

      tracking_result_fixture(v1, %{distance_cm: 100.0})
      tracking_result_fixture(v2, %{distance_cm: 200.0})

      {:ok, _lv, html} = live(conn, "/analyses?subjects=#{subject.id},#{other_subject.id}")

      assert html =~ "a.mp4"
      assert html =~ "b.mp4"
      # each series' tooltip is prefixed with its subject's name
      assert html =~ "M-01 — "
      assert html =~ "M-02 — "
    end

    test "a comparison keeps working when the subjects have a different number of sessions", %{
      conn: conn,
      user: user,
      subject: subject,
      cal: cal,
      experiment: experiment
    } do
      other_subject = subject_fixture(user, %{name: "M-02"})

      v1 =
        video_fixture(experiment, cal, %{
          status: "done",
          subject_id: subject.id,
          filename: "a1.mp4"
        })

      v2 =
        video_fixture(experiment, cal, %{
          status: "done",
          subject_id: subject.id,
          filename: "a2.mp4"
        })

      v3 =
        video_fixture(experiment, cal, %{
          status: "done",
          subject_id: other_subject.id,
          filename: "b1.mp4"
        })

      tracking_result_fixture(v1, %{distance_cm: 10.0})
      tracking_result_fixture(v2, %{distance_cm: 20.0})
      tracking_result_fixture(v3, %{distance_cm: 30.0})

      {:ok, _lv, html} = live(conn, "/analyses?subjects=#{subject.id},#{other_subject.id}")

      assert html =~ "<svg"
      assert html =~ "a1.mp4"
      assert html =~ "a2.mp4"
      assert html =~ "b1.mp4"
    end

    test "the experiment scope filter narrows sessions to one experiment", %{
      conn: conn,
      user: user,
      subject: subject,
      cal: cal,
      experiment: experiment
    } do
      other_experiment = experiment_fixture(user)

      v1 =
        video_fixture(experiment, cal, %{
          status: "done",
          subject_id: subject.id,
          filename: "a.mp4"
        })

      v2 =
        video_fixture(other_experiment, cal, %{
          status: "done",
          subject_id: subject.id,
          filename: "b.mp4"
        })

      tracking_result_fixture(v1, %{})
      tracking_result_fixture(v2, %{})

      {:ok, lv, html} = live(conn, ~p"/analyses?subjects=#{subject.id}")
      assert html =~ "a.mp4"
      assert html =~ "b.mp4"

      html =
        lv
        |> form("#analyses-experiment", %{"experiment" => to_string(experiment.id)})
        |> render_change()

      assert html =~ "a.mp4"
      refute html =~ "b.mp4"
    end

    test "switching metric changes which field is charted", %{
      conn: conn,
      subject: subject,
      cal: cal,
      experiment: experiment
    } do
      v1 =
        video_fixture(experiment, cal, %{
          status: "done",
          subject_id: subject.id,
          filename: "a.mp4"
        })

      tracking_result_fixture(v1, %{distance_cm: 111.0, speed_mean_cm: 7.5})

      {:ok, lv, html} = live(conn, ~p"/analyses?subjects=#{subject.id}")
      assert html =~ "Distance traveled over time"

      html =
        lv
        |> element("button[phx-value-metric='speed_mean_cm']")
        |> render_click()

      assert html =~ "Mean speed over time"
    end

    test "a metric missing on some sessions only charts the sessions that have it", %{
      conn: conn,
      subject: subject,
      cal: cal,
      experiment: experiment
    } do
      v1 =
        video_fixture(experiment, cal, %{
          status: "done",
          subject_id: subject.id,
          filename: "a.mp4"
        })

      v2 =
        video_fixture(experiment, cal, %{
          status: "done",
          subject_id: subject.id,
          filename: "b.mp4"
        })

      set_inserted_at(v1, ~U[2026-01-01 00:00:00Z])
      set_inserted_at(v2, ~U[2026-02-01 00:00:00Z])

      # only v2 gets a thigmotaxis_pct value; v1's stays nil (not required)
      tracking_result_fixture(v1, %{})
      tracking_result_fixture(v2, %{thigmotaxis_pct: 55.0})

      {:ok, lv, html} = live(conn, ~p"/analyses?subjects=#{subject.id}")
      # both rows always show in the table regardless of the charted metric
      assert html =~ "a.mp4"
      assert html =~ "b.mp4"

      html =
        lv
        |> element("button[phx-value-metric='thigmotaxis_pct']")
        |> render_click()

      assert html =~ "Thigmotaxis over time"
      refute html =~ "No analyzed sessions have a value for this metric yet"
      # still only one chartable point -> the single-point note is shown
      assert html =~ "Only one session so far"
    end
  end

  test "a subject owned by another user never appears and is not leaked via the URL", %{
    conn: conn
  } do
    other_user = user_fixture()
    other_subject = subject_fixture(other_user, %{name: "Not mine"})

    {:ok, _lv, html} = live(conn, ~p"/analyses")
    refute html =~ "Not mine"

    {:ok, _lv, html} = live(conn, ~p"/analyses?subjects=#{other_subject.id}")
    refute html =~ "Not mine"
    assert html =~ "No subjects yet"
  end

  describe "group trend line" do
    setup %{user: user} do
      s1 = subject_fixture(user, %{name: "M-01", group: "Control"})
      s2 = subject_fixture(user, %{name: "M-02", group: "Control"})
      cal = calibration_fixture(user)
      experiment = experiment_fixture(user)

      v1 =
        video_fixture(experiment, cal, %{status: "done", subject_id: s1.id, filename: "a1.mp4"})

      v2 =
        video_fixture(experiment, cal, %{status: "done", subject_id: s2.id, filename: "b1.mp4"})

      tracking_result_fixture(v1, %{distance_cm: 10.0})
      tracking_result_fixture(v2, %{distance_cm: 30.0})

      %{s1: s1, s2: s2, experiment: experiment}
    end

    test "toggling a group chip adds a mean series to the chart", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/analyses?subjects=")
      refute html =~ "Control (mean)"

      html =
        lv
        |> form("#analyses-group-picker", %{"group" => "Control"})
        |> render_change()

      assert html =~ "<svg"
      assert html =~ "Control (mean)"
    end

    test "an unknown group in the URL is ignored", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/analyses?subjects=&groups=Nonexistent")

      refute html =~ "Nonexistent"
      assert html =~ "No subject or group selected"
    end

    test "the chart renders with only a group selected (no subjects)", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/analyses?subjects=&groups=Control")

      assert html =~ "<svg"
      assert html =~ "Control (mean)"
    end

    test "a subject and a group can be compared on the same chart simultaneously", %{
      conn: conn,
      s1: s1
    } do
      {:ok, _lv, html} = live(conn, ~p"/analyses?subjects=#{s1.id}&groups=Control")

      assert html =~ "M-01"
      assert html =~ "Control (mean)"
    end

    test "removing the group chip removes its series", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/analyses?groups=Control")
      assert html =~ "Control (mean)"

      html =
        lv
        |> element("button[phx-value-group='Control']")
        |> render_click()

      refute html =~ "Control (mean)"
    end

    test "adding a group auto-adds its member subjects as chips", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/analyses?subjects=")

      html =
        lv
        |> form("#analyses-group-picker", %{"group" => "Control"})
        |> render_change()

      # both members of "Control" are now selected subjects (chips)
      assert html =~ ~s(phx-value-subject)
      assert html =~ "M-01"
      assert html =~ "M-02"
    end

    test "removing a group subtracts its auto-added subjects", %{conn: conn, s1: s1, s2: s2} do
      {:ok, lv, html} =
        live(conn, "/analyses?subjects=#{s1.id},#{s2.id}&groups=Control")

      assert html =~ "b1.mp4"

      html =
        lv
        |> element("button[phx-value-group='Control']")
        |> render_click()

      # both subjects were members of the removed group -> nothing left selected
      assert html =~ "No subject or group selected"
    end
  end

  describe "box views" do
    setup %{user: user} do
      s1 = subject_fixture(user, %{name: "M-01", group: "Control"})
      s2 = subject_fixture(user, %{name: "M-02", group: "CNO"})
      cal = calibration_fixture(user)
      experiment = experiment_fixture(user)

      for {s, dists} <- [{s1, [10.0, 20.0, 30.0]}, {s2, [40.0, 50.0]}] do
        for {d, i} <- Enum.with_index(dists) do
          v =
            video_fixture(experiment, cal, %{
              status: "done",
              subject_id: s.id,
              filename: "#{s.name}-#{i}.mp4"
            })

          tracking_result_fixture(v, %{distance_cm: d})
        end
      end

      %{s1: s1, s2: s2, experiment: experiment}
    end

    test "the per-subject view renders one box per subject", %{conn: conn, s1: s1, s2: s2} do
      {:ok, lv, _html} = live(conn, "/analyses?subjects=#{s1.id},#{s2.id}")

      html = lv |> element("button[phx-value-view='subject_box']") |> render_click()

      assert html =~ ~s(id="analyses-subject-box")
      # median/mean style legend + a group color legend (subjects colored by group)
      assert html =~ "Median"
      assert html =~ "Mean"
      assert html =~ "Groups"
      assert html =~ "Control"
      assert html =~ "CNO"
    end

    test "a category label too long for its slot wraps onto a second line instead of overlapping",
         %{conn: conn, user: user} do
      # Several categories narrow each one's slot, so even a moderately long
      # name among them needs to wrap instead of overlapping its neighbors.
      long_named = subject_fixture(user, %{name: "Mouse With A Long Descriptive Name"})
      others = for i <- 1..4, do: subject_fixture(user, %{name: "M-#{i}"})
      cal = calibration_fixture(user)
      experiment = experiment_fixture(user)

      for s <- [long_named | others] do
        video = video_fixture(experiment, cal, %{status: "done", subject_id: s.id})
        tracking_result_fixture(video, %{distance_cm: 10.0})
      end

      subject_ids = Enum.map_join([long_named | others], ",", & &1.id)
      {:ok, lv, _html} = live(conn, "/analyses?subjects=#{subject_ids}&view=subject_box")

      html = render(lv)
      tspan_count = length(String.split(html, "<tspan")) - 1
      # 5 categories, so 5 tspans if every label stayed on one line — more
      # than that means at least one label actually wrapped onto a 2nd line.
      assert tspan_count > 5
    end

    test "the per-group view renders, hides point names, and log1p toggles", %{
      conn: conn,
      s1: s1,
      s2: s2
    } do
      {:ok, lv, _html} = live(conn, "/analyses?subjects=#{s1.id},#{s2.id}&view=group_box")

      html = render(lv)
      assert html =~ ~s(id="analyses-group-box")
      assert html =~ "hover a point for its subject"
      # subject names live only in the point tooltip (<title>), not as a visible label
      assert html =~ "<title>M-01"
      assert html =~ "log1p off"

      html = lv |> element("button", "log1p off") |> render_click()
      assert html =~ "log1p on"
      assert html =~ "(log1p)"
    end

    test "reflects a subject's group edited after the page mounted (not frozen to mount)", %{
      conn: conn,
      user: user
    } do
      s = subject_fixture(user, %{name: "M-09"})
      cal = calibration_fixture(user)
      experiment = experiment_fixture(user)
      v = video_fixture(experiment, cal, %{status: "done", subject_id: s.id, filename: "a.mp4"})
      tracking_result_fixture(v, %{distance_cm: 10.0})

      # A group name no other fixture uses, so it can only appear once the
      # subject actually carries it (not from some other subject's dropdown).
      {:ok, lv, html} = live(conn, "/analyses?subjects=#{s.id}&view=subject_box")
      refute html =~ "Cohort-Z"

      # Simulate the group being set elsewhere (e.g. Pipeline Settings) while the
      # Analyses page stays mounted.
      scope = user_scope_fixture(user)
      {:ok, _} = MouseTracker.Experiments.Subjects.update_subject(scope, s, %{group: "Cohort-Z"})

      # Any interaction re-runs handle_params -> the group legend now shows it.
      html = lv |> element("button[phx-value-view='subject_box']") |> render_click()
      assert html =~ "Cohort-Z"
    end

    test "the speed-distribution view boxes each subject's pooled per-frame speeds", %{
      conn: conn,
      user: user
    } do
      s = subject_fixture(user, %{name: "S-1", group: "Control"})
      cal = calibration_fixture(user)
      experiment = experiment_fixture(user)

      v1 = video_fixture(experiment, cal, %{status: "done", subject_id: s.id, filename: "a.mp4"})
      v2 = video_fixture(experiment, cal, %{status: "done", subject_id: s.id, filename: "b.mp4"})
      tracking_result_fixture(v1, %{speed_samples: [1.0, 2.0, 3.0, 4.0]})
      tracking_result_fixture(v2, %{speed_samples: [5.0, 6.0]})

      {:ok, lv, _html} = live(conn, "/analyses?subjects=#{s.id}&view=speed_box")

      html = render(lv)
      assert html =~ ~s(id="analyses-speed-box")
      assert html =~ "Speed distribution by subject"
      # fixed to speed: the metric selector is hidden, unit is cm/s, group legend shown
      refute html =~ ~s(phx-click="select_metric")
      assert html =~ "cm/s"
      assert html =~ "Groups"
    end

    test "the speed view shows a hint when no per-frame samples exist", %{
      conn: conn,
      s1: s1
    } do
      # box-views setup creates tracking results without speed_samples
      {:ok, _lv, html} = live(conn, "/analyses?subjects=#{s1.id}&view=speed_box")

      assert html =~ "No per-frame speed data"
      refute html =~ ~s(id="analyses-speed-box")
    end

    test "an export button targets the chart card when a chart is present", %{
      conn: conn,
      s1: s1,
      s2: s2
    } do
      {:ok, lv, _html} = live(conn, "/analyses?subjects=#{s1.id},#{s2.id}&view=subject_box")

      assert has_element?(lv, "#analyses-export[data-capture='analyses-chart-card']")
      assert has_element?(lv, "#analyses-chart-card")
      # the filename base encodes the current view + metric
      assert lv
             |> element("#analyses-export")
             |> render() =~ ~s(data-name="analyses-subject-box-distance_cm")
    end

    test "the export button is hidden when the view has no chart", %{conn: conn, s1: s1} do
      # thigmotaxis is nil on these fixtures -> nothing to chart -> no export
      {:ok, lv, _html} =
        live(conn, "/analyses?subjects=#{s1.id}&view=subject_box&metric=thigmotaxis_pct")

      refute has_element?(lv, "#analyses-export")
    end
  end

  describe "time x roi view" do
    setup %{user: user} do
      cal = calibration_fixture(user)
      experiment = experiment_fixture(user)

      s1 = subject_fixture(user, %{name: "M-01", group: "Control"})
      s2 = subject_fixture(user, %{name: "M-02", group: "CNO"})

      v1 = video_fixture(experiment, cal, %{status: "done", subject_id: s1.id, filename: "a.mp4"})
      v2 = video_fixture(experiment, cal, %{status: "done", subject_id: s2.id, filename: "b.mp4"})

      roi = roi_fixture(v1, %{name: "Center"})
      :ok = Rois.attach_roi_to_video(v2, roi)

      r1 = tracking_result_fixture(v1)
      r2 = tracking_result_fixture(v2)
      roi_time_fixture(roi, r1, %{seconds: 10.0})
      roi_time_fixture(roi, r2, %{seconds: 20.0})

      %{s1: s1, s2: s2}
    end

    test "renders one box per zone/group pair, with a group legend", %{
      conn: conn,
      s1: s1,
      s2: s2
    } do
      {:ok, lv, _html} = live(conn, "/analyses?subjects=#{s1.id},#{s2.id}&view=roi_box")

      html = render(lv)
      assert html =~ ~s(id="analyses-roi-box")
      assert html =~ "Time in ROI zones by group"
      assert html =~ "Groups"
      assert html =~ "Control"
      assert html =~ "CNO"
    end

    test "hides the metric selector on this view", %{conn: conn, s1: s1} do
      {:ok, lv, _html} = live(conn, "/analyses?subjects=#{s1.id}&view=roi_box")

      refute has_element?(lv, "button[phx-click='select_metric']")
    end

    test "ungrouped subjects are excluded, with a hint shown", %{conn: conn, user: user} do
      cal = calibration_fixture(user)
      experiment = experiment_fixture(user)
      grouped = subject_fixture(user, %{name: "M-03", group: "Control"})
      ungrouped = subject_fixture(user, %{name: "M-04"})

      v1 = video_fixture(experiment, cal, %{status: "done", subject_id: grouped.id})
      v2 = video_fixture(experiment, cal, %{status: "done", subject_id: ungrouped.id})
      roi = roi_fixture(v1, %{name: "Periphery"})
      :ok = Rois.attach_roi_to_video(v2, roi)
      r1 = tracking_result_fixture(v1)
      r2 = tracking_result_fixture(v2)
      roi_time_fixture(roi, r1, %{seconds: 5.0})
      roi_time_fixture(roi, r2, %{seconds: 99.0})

      {:ok, lv, _html} =
        live(conn, "/analyses?subjects=#{grouped.id},#{ungrouped.id}&view=roi_box")

      chart_html = lv |> element("#analyses-roi-box") |> render()
      refute chart_html =~ ungrouped.name
      assert render(lv) =~ "Subjects without a group are not shown here."
    end

    test "shows an empty state when no selected group has roi zone data", %{
      conn: conn,
      user: user
    } do
      subject = subject_fixture(user, %{name: "M-05", group: "Control"})
      experiment = experiment_fixture(user)
      video_fixture(experiment, nil, %{status: "done", subject_id: subject.id})

      {:ok, _lv, html} = live(conn, "/analyses?subjects=#{subject.id}&view=roi_box")

      assert html =~ "No ROI zone time"
      refute html =~ ~s(id="analyses-roi-box")
    end

    test "the exported filename is fixed for this view", %{conn: conn, s1: s1, s2: s2} do
      {:ok, lv, _html} = live(conn, "/analyses?subjects=#{s1.id},#{s2.id}&view=roi_box")

      assert lv
             |> element("#analyses-export")
             |> render() =~ ~s(data-name="analyses-time-by-roi")
    end
  end
end
