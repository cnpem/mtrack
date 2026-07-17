defmodule MouseTracker.Workers.VideoProcessingWorker do
  use Oban.Worker, queue: :video_processing, max_attempts: 3

  alias MouseTracker.Repo
  alias MouseTracker.Experiments.{Video, TrackingResult, RoiTime}

  @doc """
  PubSub topic a video's status/progress updates are broadcast on.
  """
  def topic(video_id), do: "video:#{video_id}"

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"video_id" => video_id}}) do
    video = Repo.get!(Video, video_id) |> Repo.preload([:calibration, :rois])

    video
    |> Video.changeset(%{status: "processing"})
    |> Repo.update!()

    broadcast(video.id, {:status, video.id, "processing"})

    on_progress = fn %{"value" => value} ->
      broadcast(video.id, {:progress, video.id, value})
    end

    case python_port().run(build_params(video), on_progress) do
      {:ok, result} ->
        save_result(video, result)
        :ok

      {:error, reason} ->
        video
        |> Video.changeset(%{status: "error"})
        |> Repo.update!()

        broadcast(video.id, {:status, video.id, "error"})
        broadcast(video.id, {:processing_error, video.id, reason})

        {:error, reason}
    end
  end

  defp python_port do
    Application.get_env(:mouse_tracker, :python_port, MouseTracker.Tracking.PythonPort)
  end

  defp build_params(%Video{calibration: cal} = video) do
    %{
      "video" => video.filepath,
      "valid_region" => [
        cal.valid_region_x,
        cal.valid_region_y,
        cal.valid_region_w,
        cal.valid_region_h
      ],
      "threshold" => cal.threshold,
      "min_area" => cal.min_area,
      "px_per_10cm" => cal.px_per_10cm,
      "background_frame" => video.background_frame || 0,
      "rois" => Enum.map(video.rois, &roi_to_list/1),
      "heatmap" => output_path(video, "heatmap.png"),
      "speed_profile" => output_path(video, "speed_profile.png")
    }
  end

  # Python distinguishes ROI shape by list length: 3 = circle, 4 = rectangle,
  # 8 = polygon (4 free vertices x1,y1..x4,y4).
  defp roi_to_list(%{shape: "circle"} = roi), do: [roi.x, roi.y, roi.radius]

  defp roi_to_list(%{shape: "polygon"} = roi),
    do: [roi.x1, roi.y1, roi.x2, roi.y2, roi.x3, roi.y3, roi.x4, roi.y4]

  defp roi_to_list(roi), do: [roi.x, roi.y, roi.w, roi.h]

  # Absolute path under priv/static so Plug.Static (from: :mouse_tracker) serves it.
  # The Python side writes the PNG here but does not create parent dirs, so we do.
  defp output_path(video, filename) do
    dir = Path.join([static_dir(), "uploads", "results", to_string(video.id)])
    File.mkdir_p!(dir)
    Path.join(dir, filename)
  end

  defp static_dir, do: Path.join(:code.priv_dir(:mouse_tracker), "static")

  # Web-servable path stored in the DB for `<img src=...>`.
  defp web_path(video, filename), do: "/uploads/results/#{video.id}/#{filename}"

  defp save_result(video, result) do
    metric_keys = ~w[
      distance_px distance_cm
      speed_mean_px speed_mean_cm
      speed_median_px speed_median_cm
      speed_max_px speed_max_cm
      thigmotaxis_pct immobility_seconds path_tortuosity
    ]

    attrs =
      Map.take(result, metric_keys)
      |> Map.put("video_id", video.id)
      |> Map.put("processed_at", DateTime.utc_now())
      |> Map.put("heatmap_path", web_path(video, "heatmap.png"))
      |> Map.put("speed_profile_path", web_path(video, "speed_profile.png"))

    tracking_result =
      %TrackingResult{}
      |> TrackingResult.changeset(attrs)
      |> Repo.insert!()

    save_roi_times(video, tracking_result, result)

    video
    |> Video.changeset(%{status: "done"})
    |> Repo.update!()

    broadcast(video.id, {:status, video.id, "done"})
    broadcast(video.id, {:processing_done, video.id})
  end

  # `frames_into_roi` / `time_into_roi_s` are aligned to the same order as
  # `video.rois` (that's the order build_params/1 passed them to Python), so we
  # zip them back to persist per-video time-in-zone. Sharing a ROI across videos
  # is safe because each video's data lands on its own tracking_result.
  defp save_roi_times(video, tracking_result, result) do
    frames = Map.get(result, "frames_into_roi", [])
    seconds = Map.get(result, "time_into_roi_s", [])

    video.rois
    |> Enum.zip(Enum.zip(frames, seconds))
    |> Enum.each(fn {roi, {frame_count, secs}} ->
      %RoiTime{roi_id: roi.id, tracking_result_id: tracking_result.id}
      |> RoiTime.changeset(%{frame_count: frame_count, seconds: secs})
      |> Repo.insert!()
    end)
  end

  defp broadcast(video_id, message) do
    Phoenix.PubSub.broadcast(MouseTracker.PubSub, topic(video_id), message)
  end
end
