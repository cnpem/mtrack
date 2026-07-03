defmodule MouseTracker.Tracking.PythonPort do
  @moduledoc """
  Runs the Python tracking engine in headless mode (`--json`) via System.cmd/3.

  The Python script prints one JSON object per line:
    - `{"type":"progress","value":N}` during processing (ignored here)
    - `{"type":"result",...}` at the end with all computed metrics

  Returns {:ok, result_map} or {:error, reason}.
  """

  @doc """
  Runs the tracker for the given params map.

  Required keys: "video", "valid_region" ([x, y, w, h])
  Optional keys: "start_time", "end_time", "threshold", "min_area",
                 "px_per_10cm", "rois", "arena_shape", "thigmotaxis_margin_pct",
                 "immobility_threshold_cm", "progress_every",
                 "speed_profile", "speed_distribution", "heatmap"
  """
  def run(params) when is_map(params) do
    json = Jason.encode!(params)
    root = project_root()

    case System.cmd("uv", ["run", "python", "-m", "priv.python.run", "--json", json],
           cd: root,
           stderr_to_stdout: false
         ) do
      {output, 0} ->
        parse_output(output)

      {output, code} ->
        {:error, "Python exited with code #{code}:\n#{output}"}
    end
  end

  defp parse_output(output) do
    result =
      output
      |> String.split("\n", trim: true)
      |> Enum.find_value(fn line ->
        case Jason.decode(line) do
          {:ok, %{"type" => "result"} = map} -> map
          _ -> nil
        end
      end)

    case result do
      nil -> {:error, :no_result_line}
      map -> {:ok, map}
    end
  end

  defp project_root do
    :code.priv_dir(:mouse_tracker)
    |> Path.join("..")
    |> Path.expand()
  end
end
