defmodule MouseTracker.Tracking.FrameExtractor do
  @moduledoc """
  Extracts a single frame from a video as a PNG, by invoking the Python tracker
  in its headless `--extract-frame` mode.

  Used by the upload wizard to show the first frame of each uploaded video so the
  user can draw ROIs and the scale reference over it. Unlike
  `MouseTracker.Tracking.PythonPort`, this is a one-shot call (no progress
  streaming), so a blocking `System.cmd/3` is enough.
  """

  require Logger

  @doc """
  Writes frame `frame_num` (default 0) of `video_path` to `output_png`.

  Returns `{:ok, meta}` on success, where `meta` is a map with the video's
  `:fps`, `:frame_count`, `:width`, `:height` and `:duration_seconds` (parsed
  from the `video_info` line the Python side emits; any field may be `nil` if
  the codec doesn't expose it, and `meta` is `%{}` if the line is absent).
  Returns `{:error, reason}` (including `:uv_not_found`) on failure. Creates the
  output's parent directory if needed.
  """
  def extract_first_frame(video_path, output_png, frame_num \\ 0) do
    case System.find_executable("uv") do
      nil ->
        {:error, :uv_not_found}

      uv ->
        File.mkdir_p!(Path.dirname(output_png))

        args = [
          "run",
          "python",
          "-m",
          "priv.python.run",
          "--extract-frame",
          Integer.to_string(frame_num),
          "--video",
          video_path,
          "--extract-output",
          output_png
        ]

        case System.cmd(uv, args, cd: project_root(), stderr_to_stdout: true) do
          {out, 0} ->
            if File.exists?(output_png) do
              {:ok, parse_video_info(out)}
            else
              {:error, :no_frame_written}
            end

          {out, code} ->
            Logger.warning("FrameExtractor failed (#{code}): #{out}")
            {:error, "frame extraction exited with code #{code}"}
        end
    end
  end

  # Each stdout line is a JSON object; pick the `video_info` one and keep the
  # metadata fields as an atom-keyed map. Absent/garbled output → `%{}`.
  defp parse_video_info(out) do
    out
    |> String.split("\n", trim: true)
    |> Enum.find_value(%{}, fn line ->
      case Jason.decode(line) do
        {:ok, %{"type" => "video_info"} = info} ->
          %{
            fps: info["fps"],
            frame_count: info["frame_count"],
            width: info["width"],
            height: info["height"],
            duration_seconds: info["duration_seconds"]
          }

        _ ->
          nil
      end
    end)
  end

  defp project_root do
    :code.priv_dir(:mouse_tracker)
    |> Path.join("..")
    |> Path.expand()
  end

  @doc """
  Web path to a cached first-frame PNG for `video` (`uploads/roi_edit_frames/<id>.png`),
  extracting and caching it on first use. Shared by the Datasets library, the
  ROI editor, and the wizard's "reuse video" picker — all show a thumbnail
  keyed by video id and should reuse whichever of them extracted it first.
  Returns `nil` if the frame can't be produced (e.g. the source file is
  missing from disk).
  """
  def ensure_cached_frame(video) do
    frame_path = cached_frame_path(video)
    web_path = cached_frame_web_path(video)

    cond do
      File.exists?(frame_path) ->
        web_path

      is_binary(video.filepath) and File.exists?(video.filepath) ->
        case extract_first_frame(video.filepath, frame_path) do
          {:ok, _meta} -> web_path
          {:error, _} -> nil
        end

      true ->
        nil
    end
  end

  def cached_frame_path(video),
    do: Path.join([static_dir(), "uploads", "roi_edit_frames", "#{video.id}.png"])

  def cached_frame_web_path(video), do: "/uploads/roi_edit_frames/#{video.id}.png"

  defp static_dir, do: Path.join(:code.priv_dir(:mouse_tracker), "static")
end
