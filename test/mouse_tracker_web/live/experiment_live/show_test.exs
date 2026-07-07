defmodule MouseTrackerWeb.ExperimentLive.ShowTest do
  use MouseTrackerWeb.ConnCase

  import Phoenix.LiveViewTest
  import MouseTracker.ExperimentsFixtures

  alias MouseTracker.Experiments
  alias MouseTracker.Repo

  setup :register_and_log_in_user

  setup %{user: user} do
    experiment = experiment_fixture(user)
    subject = subject_fixture(user, %{name: "M-01", notes: "olho direito nublado"})
    video = video_fixture(experiment, nil, %{subject_id: subject.id})

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
end
