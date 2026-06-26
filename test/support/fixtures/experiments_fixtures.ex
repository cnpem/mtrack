defmodule MouseTracker.ExperimentsFixtures do
  alias MouseTracker.Repo
  alias MouseTracker.Experiments.{Calibration, Experiment, Video, Roi, TrackingResult, RoiTime}

  def calibration_fixture(user, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        cage_side_cm: 30.0,
        px_per_10cm: 50.0,
        threshold: 80,
        min_area: 250
      })

    %Calibration{user_id: user.id}
    |> Calibration.changeset(attrs)
    |> Repo.insert!()
  end

  def experiment_fixture(user, attrs \\ %{}) do
    attrs = Enum.into(attrs, %{name: "Experimento #{System.unique_integer()}"})

    %Experiment{user_id: user.id}
    |> Experiment.changeset(attrs)
    |> Repo.insert!()
  end

  def video_fixture(experiment, calibration \\ nil, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        filename: "video_#{System.unique_integer()}.mp4",
        filepath: "/tmp/video_#{System.unique_integer()}.mp4"
      })

    %Video{experiment_id: experiment.id, calibration_id: calibration && calibration.id}
    |> Video.changeset(attrs)
    |> Repo.insert!()
  end

  def roi_fixture(video, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        name: "ROI #{System.unique_integer()}",
        shape: "rectangle",
        x: 10,
        y: 10,
        w: 100,
        h: 100
      })

    %Roi{video_id: video.id}
    |> Roi.changeset(attrs)
    |> Repo.insert!()
  end

  def tracking_result_fixture(video, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        distance_px: 1000.0,
        distance_cm: 33.3,
        speed_mean_px: 5.0,
        speed_mean_cm: 1.5,
        speed_median_px: 4.5,
        speed_median_cm: 1.4,
        processed_at: DateTime.utc_now(:second)
      })

    %TrackingResult{video_id: video.id}
    |> TrackingResult.changeset(attrs)
    |> Repo.insert!()
  end

  def roi_time_fixture(roi, tracking_result, attrs \\ %{}) do
    attrs = Enum.into(attrs, %{frame_count: 120, seconds: 4.0})

    %RoiTime{roi_id: roi.id, tracking_result_id: tracking_result.id}
    |> RoiTime.changeset(attrs)
    |> Repo.insert!()
  end
end
