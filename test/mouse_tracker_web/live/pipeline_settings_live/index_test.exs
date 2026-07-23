defmodule MouseTrackerWeb.PipelineSettingsLive.IndexTest do
  use MouseTrackerWeb.ConnCase

  import Phoenix.LiveViewTest
  import MouseTracker.ExperimentsFixtures

  alias MouseTracker.Accounts
  alias MouseTracker.Experiments
  alias MouseTracker.Repo

  setup :register_and_log_in_user

  setup %{user: user} do
    exp = experiment_fixture(user)
    cal = calibration_fixture(user, %{name: "Arena A"})
    subject = subject_fixture(user, %{name: "M-01"})
    video = video_fixture(exp)
    roi = roi_fixture(video, %{name: "Center"})

    %{exp: exp, cal: cal, subject: subject, video: video, roi: roi}
  end

  test "shows the three library tabs and the defaults form", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/pipeline-settings")

    assert html =~ "Pipeline defaults"
    assert html =~ "Calibrations"
    assert html =~ "ROIs"
    assert html =~ "Subjects"
  end

  test "calibrations tab lists the user's calibrations", %{conn: conn, cal: cal} do
    {:ok, _lv, html} = live(conn, ~p"/pipeline-settings")

    assert html =~ cal.name
  end

  test "only shows resources owned by the current user", %{conn: conn} do
    other = MouseTracker.AccountsFixtures.user_fixture()
    _other_cal = calibration_fixture(other, %{name: "Someone else's calibration"})

    {:ok, _lv, html} = live(conn, ~p"/pipeline-settings")

    refute html =~ "Someone else's calibration"
  end

  test "switches tabs via push_patch", %{conn: conn, roi: roi, subject: subject} do
    {:ok, lv, _html} = live(conn, ~p"/pipeline-settings")

    html = lv |> element("button[phx-value-tab='rois']") |> render_click()
    assert html =~ roi.name
    refute html =~ subject.name

    html = lv |> element("button[phx-value-tab='subjects']") |> render_click()
    assert html =~ subject.name
  end

  test "searches within the active tab", %{conn: conn, user: user} do
    calibration_fixture(user, %{name: "Arena B"})

    {:ok, lv, _html} = live(conn, ~p"/pipeline-settings")

    html =
      lv
      |> form("#pipeline-settings-search", %{"query" => "Arena A"})
      |> render_change()

    assert html =~ "Arena A"
    refute html =~ "Arena B"
  end

  test "renames a calibration on blur", %{conn: conn, cal: cal} do
    {:ok, lv, _html} = live(conn, ~p"/pipeline-settings")

    html =
      lv
      |> element("input[phx-value-id='#{cal.id}'][phx-blur='rename_calibration']")
      |> render_blur(%{"value" => "Arena renamed"})

    assert html =~ "Arena renamed"
    assert Repo.get!(Experiments.Calibration, cal.id).name == "Arena renamed"
  end

  test "renames a ROI on blur", %{conn: conn, roi: roi} do
    {:ok, lv, _html} = live(conn, ~p"/pipeline-settings?tab=rois")

    html =
      lv
      |> element("input[phx-value-id='#{roi.id}'][phx-blur='rename_roi']")
      |> render_blur(%{"value" => "Periphery"})

    assert html =~ "Periphery"
    assert Repo.get!(Experiments.Roi, roi.id).name == "Periphery"
  end

  test "renames a subject on blur", %{conn: conn, subject: subject} do
    {:ok, lv, _html} = live(conn, ~p"/pipeline-settings?tab=subjects")

    html =
      lv
      |> element("input[phx-value-id='#{subject.id}'][phx-blur='rename_subject']")
      |> render_blur(%{"value" => "M-02"})

    assert html =~ "M-02"
    assert Repo.get!(Experiments.Subject, subject.id).name == "M-02"
  end

  test "renaming a subject to a name already in use flashes an error", %{
    conn: conn,
    user: user,
    subject: subject
  } do
    other = subject_fixture(user, %{name: "M-02"})

    {:ok, lv, _html} = live(conn, ~p"/pipeline-settings?tab=subjects")

    lv
    |> element("input[phx-value-id='#{subject.id}'][phx-blur='rename_subject']")
    |> render_blur(%{"value" => other.name})

    assert render(lv) =~ "has already been taken"
    assert Repo.get!(Experiments.Subject, subject.id).name == subject.name
  end

  test "sets a subject's sex via the select", %{conn: conn, subject: subject} do
    {:ok, lv, _html} = live(conn, ~p"/pipeline-settings?tab=subjects")

    lv
    |> form("#subject-sex-#{subject.id}", %{"value" => "F"})
    |> render_change()

    assert Repo.get!(Experiments.Subject, subject.id).sex == "F"
  end

  test "clearing a subject's sex back to blank sets it to nil", %{
    conn: conn,
    user: user,
    subject: subject
  } do
    {:ok, subject} =
      Experiments.update_subject(Accounts.Scope.for_user(user), subject, %{sex: "M"})

    {:ok, lv, _html} = live(conn, ~p"/pipeline-settings?tab=subjects")

    lv
    |> form("#subject-sex-#{subject.id}", %{"value" => ""})
    |> render_change()

    assert Repo.get!(Experiments.Subject, subject.id).sex == nil
  end

  test "edits a subject's genotype on blur", %{conn: conn, subject: subject} do
    {:ok, lv, _html} = live(conn, ~p"/pipeline-settings?tab=subjects")

    html =
      lv
      |> element("input[phx-value-id='#{subject.id}'][phx-blur='update_subject_genotype']")
      |> render_blur(%{"value" => "C57BL/6J"})

    assert html =~ "C57BL/6J"
    assert Repo.get!(Experiments.Subject, subject.id).genotype == "C57BL/6J"
  end

  test "deletes a calibration that is not attached to any video", %{conn: conn, cal: cal} do
    {:ok, lv, _html} = live(conn, ~p"/pipeline-settings")

    html =
      lv
      |> element("button[phx-value-id='#{cal.id}'][phx-click='delete_calibration']")
      |> render_click()

    refute html =~ cal.name
    refute Repo.get(Experiments.Calibration, cal.id)
  end

  test "delete button is disabled for a calibration attached to a video", %{
    conn: conn,
    cal: cal,
    exp: exp
  } do
    video_fixture(exp, cal)

    {:ok, lv, html} = live(conn, ~p"/pipeline-settings")

    assert html =~ "1 video"

    button = element(lv, "button[phx-value-id='#{cal.id}']", "Delete")
    assert render(button) =~ "disabled"

    assert Repo.get!(Experiments.Calibration, cal.id)
  end

  test "delete is refused server-side when a subject is attached to a video", %{
    conn: conn,
    subject: subject,
    exp: exp
  } do
    video_fixture(exp, nil, %{subject_id: subject.id})

    {:ok, lv, _html} = live(conn, ~p"/pipeline-settings?tab=subjects")

    # The button is rendered disabled, so exercise the handler directly to
    # confirm the server-side guard (defense-in-depth) also refuses it.
    render_click(lv, "delete_subject", %{"id" => to_string(subject.id)})

    assert render(lv) =~ "remove it from those videos first"
    assert Repo.get!(Experiments.Subject, subject.id)
  end

  test "duplicates a ROI", %{conn: conn, roi: roi} do
    {:ok, lv, _html} = live(conn, ~p"/pipeline-settings?tab=rois")

    html =
      lv
      |> element("button[phx-value-id='#{roi.id}'][phx-click='duplicate_roi']")
      |> render_click()

    assert html =~ "#{roi.name} (copy)"
  end

  test "saves pipeline defaults and they persist across reloads", %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/pipeline-settings")

    lv
    |> form("#pipeline-defaults-form", user: %{default_threshold: "60", default_min_area: "400"})
    |> render_submit()

    assert render(lv) =~ "Pipeline defaults saved."

    reloaded = Repo.get!(MouseTracker.Accounts.User, user.id)
    assert reloaded.default_threshold == 60
    assert reloaded.default_min_area == 400
  end
end
