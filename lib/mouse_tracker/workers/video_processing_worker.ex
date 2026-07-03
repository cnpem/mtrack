defmodule MouseTracker.Workers.VideoProcessingWorker do
  use Oban.Worker, queue: :video_processing, max_attempts: 3

  alias MouseTracker.Repo
  alias MouseTracker.Experiments.{Video, TrackingResult}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"video_id" => video_id}}) do
    video = Repo.get!(Video, video_id) |> Repo.preload([:calibration, :rois])

    video
    |> Video.changeset(%{status: "processing"})
    |> Repo.update!()

    case python_port().run(build_params(video)) do
      {:ok, result} ->
        save_result(video, result)
        :ok

      {:error, reason} ->
        video
        |> Video.changeset(%{status: "error"})
        |> Repo.update!()

        {:error, reason}
    end
  end

  defp python_port do
    Application.get_env(:mouse_tracker, :python_port, MouseTracker.Tracking.PythonPort)
  end

  defp build_params(%Video{calibration: cal} = video) do
    %{
      "video" => video.filepath,
      "valid_region" => [cal.valid_region_x, cal.valid_region_y, cal.valid_region_w, cal.valid_region_h],
      "threshold" => cal.threshold,
      "min_area" => cal.min_area,
      "px_per_10cm" => cal.px_per_10cm,
      "rois" => Enum.map(video.rois, &roi_to_list/1)
    }
  end

  # Python distinguishes ROI shape by list length: 3 = circle, 4 = rectangle
  defp roi_to_list(%{shape: "circle"} = roi), do: [roi.x, roi.y, roi.radius]
  defp roi_to_list(roi), do: [roi.x, roi.y, roi.w, roi.h]

  defp save_result(video, result) do
    metric_keys = ~w[
      distance_px distance_cm
      speed_mean_px speed_mean_cm
      speed_median_px speed_median_cm
      speed_max_px speed_max_cm
      thigmotaxis_pct immobility_seconds path_tortuosity
      heatmap_path
    ]

    attrs =
      Map.take(result, metric_keys)
      |> Map.put("video_id", video.id)
      |> Map.put("processed_at", DateTime.utc_now())

    %TrackingResult{}
    |> TrackingResult.changeset(attrs)
    |> Repo.insert!()

    video
    |> Video.changeset(%{status: "done"})
    |> Repo.update!()

    Phoenix.PubSub.broadcast(MouseTracker.PubSub, "video:#{video.id}", {:processing_done, video.id})
  end
end
