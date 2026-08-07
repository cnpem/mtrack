defmodule MouseTrackerWeb.AnalysesLive.IndexTest do
  use MouseTrackerWeb.ConnCase

  import Ecto.Query
  import Phoenix.LiveViewTest
  import MouseTracker.ExperimentsFixtures
  import MouseTracker.AccountsFixtures

  alias MouseTracker.Repo
  alias MouseTracker.Experiments.Video

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
end
