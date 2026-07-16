defmodule MouseTracker.Tracking.PythonPort do
  @moduledoc """
  Runs the Python tracking engine in headless mode (`--json`) via `Port.open/2`.

  Unlike `System.cmd/3`, a port lets us read the child's stdout line by line as
  it is produced, so the `{"type":"progress","value":N}` lines the Python script
  emits during processing can be surfaced in real time (e.g. broadcast to a
  LiveView) instead of being discarded until the process exits.

  The Python script prints one JSON object per line:
    - `{"type":"progress","value":N}` during processing — forwarded to `on_progress`
    - `{"type":"result",...}` at the end with all computed metrics — returned

  Returns `{:ok, result_map}` or `{:error, reason}`.
  """

  @behaviour MouseTracker.Tracking.PythonPortBehaviour

  require Logger

  @doc """
  Runs the tracker for the given params map.

  `on_progress` is invoked with the decoded progress map (e.g.
  `%{"type" => "progress", "value" => 42.5}`) for each progress line.

  Required keys: "video", "valid_region" ([x, y, w, h])
  Optional keys: "start_time", "end_time", "threshold", "min_area",
                 "px_per_10cm", "rois", "arena_shape", "thigmotaxis_margin_pct",
                 "immobility_threshold_cm", "progress_every",
                 "speed_profile", "speed_distribution", "heatmap"
  """
  @impl true
  def run(params, on_progress \\ fn _ -> :ok end)
      when is_map(params) and is_function(on_progress, 1) do
    json = Jason.encode!(params)

    case System.find_executable("uv") do
      nil ->
        {:error, :uv_not_found}

      uv ->
        port =
          Port.open({:spawn_executable, uv}, [
            :binary,
            :exit_status,
            :hide,
            {:line, 65_536},
            {:args, ["run", "python", "-m", "priv.python.run", "--json", json]},
            {:cd, String.to_charlist(project_root())}
          ])

        stream_loop(port, on_progress, "", nil)
    end
  end

  # Reads the port line-by-line. `buffer` accumulates partial lines (the
  # `{:line, N}` option chunks output at N bytes, marking whether a newline was
  # reached), `result` holds the last decoded `{"type":"result"}` map seen.
  defp stream_loop(port, on_progress, buffer, result) do
    receive do
      {^port, {:data, {:eol, chunk}}} ->
        line = buffer <> chunk
        result = handle_line(line, on_progress, result)
        stream_loop(port, on_progress, "", result)

      {^port, {:data, {:noeol, chunk}}} ->
        stream_loop(port, on_progress, buffer <> chunk, result)

      {^port, {:exit_status, 0}} ->
        case result do
          nil -> {:error, :no_result_line}
          map -> {:ok, map}
        end

      {^port, {:exit_status, code}} ->
        {:error, "Python exited with code #{code}"}
    end
  end

  defp handle_line(line, on_progress, result) do
    case Jason.decode(line) do
      {:ok, %{"type" => "progress"} = map} ->
        on_progress.(map)
        result

      {:ok, %{"type" => "result"} = map} ->
        map

      {:ok, _other} ->
        result

      {:error, _} ->
        # Non-JSON stdout (e.g. stray prints) — ignore but keep for debugging.
        Logger.debug("PythonPort: ignoring non-JSON line: #{inspect(line)}")
        result
    end
  end

  defp project_root do
    :code.priv_dir(:mouse_tracker)
    |> Path.join("..")
    |> Path.expand()
  end
end
