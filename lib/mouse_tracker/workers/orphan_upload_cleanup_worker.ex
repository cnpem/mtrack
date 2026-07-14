defmodule MouseTracker.Workers.OrphanUploadCleanupWorker do
  use Oban.Worker, queue: :maintenance, max_attempts: 3

  require Logger
  import Ecto.Query

  alias MouseTracker.Repo
  alias MouseTracker.Experiments.Video

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    max_age_hours = Map.get(args, "max_age_hours", default_max_age_hours())
    base = Map.get(args, "uploads_base_dir", uploads_base_dir())
    cutoff = DateTime.add(DateTime.utc_now(), -trunc(max_age_hours * 3600), :second)

    claimed_tokens = claimed_video_tokens(base)
    frame_stats = clean_frame_dirs(base, list_token_dirs(Path.join(base, "frames")), cutoff)

    video_stats =
      clean_video_dirs(base, list_token_dirs(Path.join(base, "videos")), claimed_tokens, cutoff)

    Logger.info(
      "OrphanUploadCleanupWorker run: cutoff=#{cutoff} base=#{base} " <>
        "frames_deleted=#{frame_stats.deleted} frames_skipped=#{frame_stats.skipped} " <>
        "videos_deleted=#{video_stats.deleted} " <>
        "videos_skipped_claimed=#{video_stats.skipped_claimed} " <>
        "videos_skipped_young=#{video_stats.skipped_young}"
    )

    :ok
  end

  # A Video.filepath created by the wizard always lives under
  # <base>/videos/<token>/<ref>-<client_name>. Deriving the token relative to
  # the actual base dir (rather than matching a hardcoded "uploads/videos"
  # substring) keeps this correct regardless of the base dir's own name, and
  # normalizes "\" to "/" so it also works with mixed-separator paths on Windows.
  defp claimed_video_tokens(base) do
    prefix = (Path.join(base, "videos") <> "/") |> normalize_slashes()

    Repo.all(from(v in Video, select: v.filepath))
    |> Enum.map(&extract_token(&1, prefix))
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  defp extract_token(filepath, prefix) do
    normalized = normalize_slashes(filepath)

    if String.starts_with?(normalized, prefix) do
      normalized |> String.replace_prefix(prefix, "") |> String.split("/") |> List.first()
    end
  end

  defp normalize_slashes(path), do: String.replace(path, "\\", "/")

  defp clean_frame_dirs(base, tokens, cutoff) do
    Enum.reduce(tokens, %{deleted: 0, skipped: 0}, fn token, acc ->
      dir = Path.join([base, "frames", token])

      if stale?(dir, cutoff) do
        remove_dir(dir)
        %{acc | deleted: acc.deleted + 1}
      else
        %{acc | skipped: acc.skipped + 1}
      end
    end)
  end

  defp clean_video_dirs(base, tokens, claimed_tokens, cutoff) do
    Enum.reduce(tokens, %{deleted: 0, skipped_claimed: 0, skipped_young: 0}, fn token, acc ->
      cond do
        MapSet.member?(claimed_tokens, token) ->
          %{acc | skipped_claimed: acc.skipped_claimed + 1}

        stale?(Path.join([base, "videos", token]), cutoff) ->
          remove_dir(Path.join([base, "videos", token]))
          %{acc | deleted: acc.deleted + 1}

        true ->
          %{acc | skipped_young: acc.skipped_young + 1}
      end
    end)
  end

  defp stale?(dir, cutoff) do
    case File.stat(dir, time: :posix) do
      {:ok, %{mtime: mtime}} -> DateTime.from_unix!(mtime) |> DateTime.before?(cutoff)
      {:error, _reason} -> false
    end
  end

  defp remove_dir(dir) do
    File.rm_rf!(dir)
  rescue
    error ->
      Logger.warning("OrphanUploadCleanupWorker: failed to remove #{dir}: #{inspect(error)}")
  end

  defp list_token_dirs(dir) do
    case File.ls(dir) do
      {:ok, entries} -> Enum.filter(entries, &File.dir?(Path.join(dir, &1)))
      {:error, _reason} -> []
    end
  end

  defp uploads_base_dir do
    Application.get_env(:mouse_tracker, :uploads_base_dir, default_uploads_base_dir())
  end

  defp default_uploads_base_dir do
    Path.join(:code.priv_dir(:mouse_tracker), "static/uploads")
  end

  defp default_max_age_hours do
    Application.get_env(:mouse_tracker, :orphan_upload_max_age_hours, 24)
  end
end
