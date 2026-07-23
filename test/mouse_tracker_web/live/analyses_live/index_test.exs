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
      assert html =~ "No analyzed sessions in this scope"
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

      assert html =~ "No subject selected"
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
        |> form("form[phx-change='set_scope_experiment']", %{
          "scope_experiment" => to_string(experiment.id)
        })
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
end
