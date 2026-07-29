defmodule MouseTracker.Workers.VideoProcessingWorkerTest do
  use MouseTracker.DataCase, async: true

  import Mox
  import MouseTracker.AccountsFixtures
  import MouseTracker.ExperimentsFixtures

  alias MouseTracker.Workers.VideoProcessingWorker
  alias MouseTracker.Experiments.{Video, TrackingResult, Rois}
  alias MouseTracker.Tracking.PythonPortMock
  alias MouseTracker.Repo

  setup :verify_on_exit!

  setup do
    user = user_fixture()
    experiment = experiment_fixture(user)

    calibration =
      calibration_fixture(user, %{
        valid_region_x: 0,
        valid_region_y: 0,
        valid_region_w: 640,
        valid_region_h: 480
      })

    video = video_fixture(experiment, calibration)
    roi = roi_fixture(video)

    %{video: video, roi: roi, calibration: calibration}
  end

  describe "perform/1 -- success path" do
    test "transitions status pending -> processing -> done, persists TrackingResult, broadcasts PubSub",
         %{video: video} do
      Phoenix.PubSub.subscribe(MouseTracker.PubSub, "video:#{video.id}")

      # Non-default reference frame must reach the Python params.
      video |> Video.changeset(%{background_frame: 12}) |> Repo.update!()

      PythonPortMock
      |> expect(:run, fn params, on_progress ->
        assert params["video"] == video.filepath
        assert is_list(params["valid_region"])
        assert params["rois"] == [[10, 10, 100, 100]]
        assert params["background_frame"] == 12
        assert is_function(on_progress, 1)

        {:ok,
         %{
           "distance_px" => 1234.5,
           "distance_cm" => 246.9,
           "speed_mean_px" => 12.3,
           "speed_mean_cm" => 2.46,
           "speed_median_px" => 11.0,
           "speed_median_cm" => 2.2,
           "speed_max_px" => 50.0,
           "speed_max_cm" => 10.0,
           "thigmotaxis_pct" => 33.3,
           "immobility_seconds" => 5.0,
           "path_tortuosity" => 1.42
         }}
      end)

      assert :ok = VideoProcessingWorker.perform(%Oban.Job{args: %{"video_id" => video.id}})

      updated_video = Repo.get!(Video, video.id)
      assert updated_video.status == "done"

      tracking_result = Repo.get_by!(TrackingResult, video_id: video.id)
      assert tracking_result.distance_px == 1234.5
      assert tracking_result.distance_cm == 246.9
      assert tracking_result.speed_mean_px == 12.3
      assert tracking_result.speed_mean_cm == 2.46
      assert tracking_result.speed_median_px == 11.0
      assert tracking_result.speed_median_cm == 2.2

      assert_receive {:processing_done, video_id}
      assert video_id == video.id
    end

    test "sets status to processing before calling PythonPort", %{video: video} do
      PythonPortMock
      |> expect(:run, fn _params, _on_progress ->
        assert Repo.get!(Video, video.id).status == "processing"

        {:ok,
         %{
           "distance_px" => 1.0,
           "distance_cm" => 1.0,
           "speed_mean_px" => 1.0,
           "speed_mean_cm" => 1.0,
           "speed_median_px" => 1.0,
           "speed_median_cm" => 1.0
         }}
      end)

      assert :ok = VideoProcessingWorker.perform(%Oban.Job{args: %{"video_id" => video.id}})
    end
  end

  describe "perform/1 -- ROI shapes" do
    test "encodes a polygon ROI as an 8-element list for Python", %{video: video} do
      user = user_fixture()
      experiment = experiment_fixture(user)

      calibration =
        calibration_fixture(user, %{
          valid_region_x: 0,
          valid_region_y: 0,
          valid_region_w: 640,
          valid_region_h: 480
        })

      poly_video = video_fixture(experiment, calibration)

      poly =
        %MouseTracker.Experiments.Roi{user_id: user.id}
        |> MouseTracker.Experiments.Roi.changeset(%{
          name: "Quad",
          shape: "polygon",
          x: 1,
          y: 2,
          x1: 1,
          y1: 2,
          x2: 10,
          y2: 2,
          x3: 10,
          y3: 20,
          x4: 1,
          y4: 20,
          user_id: user.id
        })
        |> Repo.insert!()

      :ok = Rois.attach_roi_to_video(poly_video, poly)

      PythonPortMock
      |> expect(:run, fn params, _on_progress ->
        assert params["rois"] == [[1, 2, 10, 2, 10, 20, 1, 20]]

        {:ok,
         %{
           "distance_px" => 1.0,
           "distance_cm" => 1.0,
           "speed_mean_px" => 1.0,
           "speed_mean_cm" => 1.0,
           "speed_median_px" => 1.0,
           "speed_median_cm" => 1.0
         }}
      end)

      assert :ok = VideoProcessingWorker.perform(%Oban.Job{args: %{"video_id" => poly_video.id}})

      # keep the outer `video` binding referenced so setup stays meaningful
      assert Repo.get!(Video, video.id).status in ["pending", "processing", "done"]
    end
  end

  describe "perform/1 -- error path" do
    test "sets status to error, returns {:error, reason}, does not persist TrackingResult", %{
      video: video
    } do
      PythonPortMock
      |> expect(:run, fn _params, _on_progress ->
        {:error, "Python exited with code 1:\nsome traceback"}
      end)

      assert {:error, "Python exited with code 1:\nsome traceback"} =
               VideoProcessingWorker.perform(%Oban.Job{args: %{"video_id" => video.id}})

      updated_video = Repo.get!(Video, video.id)
      assert updated_video.status == "error"

      refute Repo.get_by(TrackingResult, video_id: video.id)
    end
  end
end
