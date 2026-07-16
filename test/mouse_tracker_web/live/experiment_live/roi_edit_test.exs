defmodule MouseTrackerWeb.ExperimentLive.RoiEditTest do
  use MouseTrackerWeb.ConnCase

  import Phoenix.LiveViewTest
  import MouseTracker.AccountsFixtures
  import MouseTracker.ExperimentsFixtures

  alias MouseTracker.Experiments

  setup :register_and_log_in_user

  setup %{user: user} do
    experiment = experiment_fixture(user)
    %{experiment: experiment}
  end

  test "an unlocked ROI can have its geometry replaced by redrawing", %{
    conn: conn,
    experiment: experiment,
    scope: scope
  } do
    video = video_fixture(experiment, nil, %{status: "pending"})

    roi =
      roi_fixture(video, %{
        name: "Zona A",
        shape: "polygon",
        x1: 0,
        y1: 0,
        x2: 10,
        y2: 0,
        x3: 10,
        y3: 10,
        x4: 0,
        y4: 10
      })

    {:ok, lv, _html} = live(conn, ~p"/videos/#{video.id}/rois/#{roi.id}/edit")

    render_hook(lv, "shape_drawn", %{
      "kind" => "roi_polygon",
      "points" => [5, 5, 15, 5, 15, 15, 5, 15]
    })

    lv |> element("form") |> render_submit(%{"value" => "Zona A"})

    updated = Experiments.get_roi!(scope, roi.id)

    assert {updated.x1, updated.y1, updated.x2, updated.y2, updated.x3, updated.y3, updated.x4,
            updated.y4} ==
             {5, 5, 15, 5, 15, 15, 5, 15}
  end

  test "renaming without redrawing keeps the existing geometry", %{
    conn: conn,
    experiment: experiment,
    scope: scope
  } do
    video = video_fixture(experiment, nil, %{status: "pending"})
    roi = roi_fixture(video, %{name: "Zona A", x: 1, y: 2, w: 3, h: 4})

    {:ok, lv, _html} = live(conn, ~p"/videos/#{video.id}/rois/#{roi.id}/edit")

    lv |> element("form") |> render_submit(%{"value" => "Zona renomeada"})

    updated = Experiments.get_roi!(scope, roi.id)
    assert updated.name == "Zona renomeada"
    assert {updated.x, updated.y, updated.w, updated.h} == {1, 2, 3, 4}
  end

  test "a locked ROI (attached to a done video) hides the canvas and offers Duplicate", %{
    conn: conn,
    experiment: experiment,
    scope: scope
  } do
    video = video_fixture(experiment, nil, %{status: "done"})
    roi = roi_fixture(video, %{name: "Zona pronta"})

    {:ok, lv, html} = live(conn, ~p"/videos/#{video.id}/rois/#{roi.id}/edit")

    assert html =~ "Geometry is locked"
    assert html =~ "Duplicate ROI"
    refute html =~ "roi-edit-canvas"

    # geometry edits are ignored while locked
    render_hook(lv, "shape_drawn", %{
      "kind" => "roi_polygon",
      "points" => [1, 1, 2, 1, 2, 2, 1, 2]
    })

    lv |> element("form") |> render_submit(%{"value" => "Zona pronta"})

    updated = Experiments.get_roi!(scope, roi.id)
    assert updated.name == "Zona pronta"
    assert updated.shape == "rectangle"
  end

  test "duplicating a locked ROI creates an independent, unlocked copy and redirects to it", %{
    conn: conn,
    experiment: experiment,
    scope: scope
  } do
    video = video_fixture(experiment, nil, %{status: "done"})
    roi = roi_fixture(video, %{name: "Zona pronta"})

    {:ok, lv, _html} = live(conn, ~p"/videos/#{video.id}/rois/#{roi.id}/edit")

    {:error, {:live_redirect, %{to: to}}} =
      lv |> element("button", "Duplicate ROI") |> render_click()

    assert to =~ "/videos/#{video.id}/rois/"
    refute to =~ "/rois/#{roi.id}/edit"

    [copy] = Experiments.list_rois(scope) |> Enum.reject(&(&1.id == roi.id))
    assert copy.name == "Zona pronta (copy)"
    refute Experiments.roi_locked?(copy)
    assert Experiments.list_rois_for_video(video) |> Enum.map(& &1.id) == [roi.id]
  end

  test "mount raises when the video belongs to another user", %{conn: conn} do
    other_experiment = experiment_fixture(user_fixture())
    video = video_fixture(other_experiment, nil, %{status: "pending"})
    roi = roi_fixture(video)

    assert_raise Ecto.NoResultsError, fn ->
      live(conn, ~p"/videos/#{video.id}/rois/#{roi.id}/edit")
    end
  end

  test "mount raises when the roi does not belong to the video", %{
    conn: conn,
    experiment: experiment
  } do
    video_a = video_fixture(experiment, nil, %{status: "pending"})
    video_b = video_fixture(experiment, nil, %{status: "pending"})
    roi_b = roi_fixture(video_b)

    assert_raise Ecto.NoResultsError, fn ->
      live(conn, ~p"/videos/#{video_a.id}/rois/#{roi_b.id}/edit")
    end
  end
end
