defmodule MouseTracker.Experiments.FileCleanup do
  @moduledoc """
  Best-effort disk cleanup for a deleted video: its file plus its results
  directory (heatmap/speed-profile PNGs). The DB row is always deleted first
  by the caller (source of truth) — failures here are logged, not raised, since
  an orphaned file is a lesser problem than blocking a delete on a filesystem
  hiccup.
  """

  require Logger

  def cleanup_video_files(video) do
    remove_file(video.filepath)
    remove_dir(Path.join([static_dir(), "uploads", "results", to_string(video.id)]))
  end

  defp remove_file(nil), do: :ok

  defp remove_file(path) do
    case File.rm(path) do
      :ok ->
        :ok

      {:error, :enoent} ->
        :ok

      {:error, reason} ->
        Logger.warning("Experiments: failed to remove #{path}: #{inspect(reason)}")
    end
  end

  defp remove_dir(dir) do
    File.rm_rf!(dir)
  rescue
    error -> Logger.warning("Experiments: failed to remove #{dir}: #{inspect(error)}")
  end

  defp static_dir, do: Path.join(:code.priv_dir(:mouse_tracker), "static")
end
