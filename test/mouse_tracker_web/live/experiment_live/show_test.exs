defmodule MouseTrackerWeb.ExperimentLive.ShowTest do
  use MouseTrackerWeb.ConnCase

  import Phoenix.LiveViewTest
  import MouseTracker.ExperimentsFixtures

  alias MouseTracker.Experiments
  alias MouseTracker.Repo
  alias MouseTracker.Workers.VideoProcessingWorker

  setup :register_and_log_in_user

  setup %{user: user} do
    experiment = experiment_fixture(user)
    subject = subject_fixture(user, %{name: "M-01", notes: "olho direito nublado"})
    video = video_fixture(experiment, nil, %{subject_id: subject.id, status: "processing"})

    %{experiment: experiment, subject: subject, video: video}
  end

  test "renders the subject card with existing notes pre-filled", %{
    conn: conn,
    experiment: experiment,
    subject: subject
  } do
    {:ok, _lv, html} = live(conn, ~p"/experiments/#{experiment.id}")

    assert html =~ subject.name
    assert html =~ "olho direito nublado"
  end

  test "shows the subject's group next to the name, with a separator dot when genotype is also present",
       %{conn: conn, user: user} do
    experiment = experiment_fixture(user)

    both =
      subject_fixture(user, %{name: "M-both", genotype: "WT", group: "Control"})

    only_group = subject_fixture(user, %{name: "M-group", group: "Treated"})

    video_fixture(experiment, nil, %{subject_id: both.id, status: "processing"})
    video_fixture(experiment, nil, %{subject_id: only_group.id, status: "processing"})

    {:ok, _lv, html} = live(conn, ~p"/experiments/#{experiment.id}")

    assert html =~ "Control"
    assert html =~ "Treated"
    # separator between genotype and group only appears when both are present
    assert html =~ ~r/WT.*·.*Control/s
  end

  test "does not show a separator when only the group is present", %{conn: conn, user: user} do
    experiment = experiment_fixture(user)
    subject = subject_fixture(user, %{name: "M-group-only", group: "Treated"})
    video_fixture(experiment, nil, %{subject_id: subject.id, status: "processing"})

    {:ok, _lv, html} = live(conn, ~p"/experiments/#{experiment.id}")

    assert html =~ "Treated"
    # only the page <title>'s own " · Phoenix Framework" suffix contains a
    # dot — the subject card itself must not show a leading separator
    refute html =~ ~r/·\s*Treated/
  end

  test "editing the notes textarea persists the observation", %{
    conn: conn,
    experiment: experiment,
    subject: subject
  } do
    {:ok, lv, _html} = live(conn, ~p"/experiments/#{experiment.id}")

    html =
      lv
      |> element("textarea[phx-value-subject-id='#{subject.id}']")
      |> render_blur(%{"value" => "manqueira na pata esquerda"})

    assert html =~ "manqueira na pata esquerda"

    updated = Repo.get!(Experiments.Subject, subject.id)
    assert updated.notes == "manqueira na pata esquerda"
  end

  test "updates the video status live when it changes via PubSub", %{
    conn: conn,
    experiment: experiment,
    video: video
  } do
    {:ok, lv, html} = live(conn, ~p"/experiments/#{experiment.id}")
    assert html =~ "Processing"

    Phoenix.PubSub.broadcast(
      MouseTracker.PubSub,
      VideoProcessingWorker.topic(video.id),
      {:status, video.id, "done"}
    )

    html = render(lv)
    assert html =~ "Done"
    assert html =~ "View results"
    refute html =~ "View progress"
  end

  test "shows attached ROIs with an edit link", %{
    conn: conn,
    experiment: experiment,
    video: video
  } do
    roi = roi_fixture(video, %{name: "Zona central"})

    {:ok, _lv, html} = live(conn, ~p"/experiments/#{experiment.id}")

    assert html =~ "Zona central"
    assert html =~ ~p"/videos/#{video.id}/rois/#{roi.id}/edit"
  end
end
