defmodule Mix.Tasks.MouseTracker.BackfillVideoMetadata do
  @shortdoc "Backfills duration/fps/resolution/size on videos uploaded before metadata capture"
  @moduledoc """
  Populates `duration_seconds`, `fps`, `frame_count`, `width`, `height` and
  `file_size_bytes` for videos already in the database whose files predate the
  upload wizard capturing this metadata (they show "—" in the Datasets library).

  For each video still missing any of those fields, if its file is on disk, this
  probes it with `MouseTracker.Tracking.FrameExtractor` (reusing the shared
  per-video frame cache, so thumbnails get warmed too) and `File.stat` for the
  size, then updates the row. Videos whose file is gone are skipped.

      mix mouse_tracker.backfill_video_metadata

  Idempotent: re-running only touches rows that are still incomplete.
  """
  use Mix.Task

  import Ecto.Query

  alias MouseTracker.{Repo, Experiments}
  alias MouseTracker.Experiments.Video
  alias MouseTracker.Tracking.FrameExtractor

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    videos =
      Repo.all(
        from v in Video,
          where: is_nil(v.duration_seconds) or is_nil(v.fps) or is_nil(v.file_size_bytes)
      )

    Mix.shell().info("Found #{length(videos)} video(s) to backfill.")

    results =
      videos
      |> Task.async_stream(&backfill/1,
        max_concurrency: System.schedulers_online(),
        timeout: :timer.seconds(60),
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, outcome} -> outcome
        {:exit, _reason} -> :error
      end)

    counts = Enum.frequencies(results)

    Mix.shell().info(
      "Done — updated: #{Map.get(counts, :updated, 0)}, " <>
        "missing file: #{Map.get(counts, :missing_file, 0)}, " <>
        "failed: #{Map.get(counts, :error, 0)}"
    )
  end

  defp backfill(%Video{filepath: filepath} = video) do
    if is_binary(filepath) and File.exists?(filepath) do
      frame_path =
        Path.join([
          :code.priv_dir(:mouse_tracker),
          "static",
          "uploads",
          "roi_edit_frames",
          "#{video.id}.png"
        ])

      meta =
        case FrameExtractor.extract_first_frame(filepath, frame_path) do
          {:ok, m} -> m
          {:error, _} -> %{}
        end

      attrs =
        meta
        |> Map.take([:fps, :duration_seconds, :frame_count, :width, :height])
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)
        |> Map.new()
        |> Map.put(:file_size_bytes, File.stat!(filepath).size)

      case Experiments.update_video(video, attrs) do
        {:ok, _} -> :updated
        {:error, _} -> :error
      end
    else
      Mix.shell().info("  skip ##{video.id} (file missing): #{filepath}")
      :missing_file
    end
  end
end
