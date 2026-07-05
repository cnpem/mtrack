defmodule MouseTracker.Tracking.PythonPortTest do
  @moduledoc """
  Real subprocess integration test for PythonPort.run/1 -- shells out to
  `uv run python -m priv.python.run --json ...` against an actual sample
  video. Requires:
    - `uv` on PATH with the project's Python deps installed (`uv sync`)
    - a sample video present at `data/NRS_25.01.19_Animal 11_M.mp4`
      (gitignored, NOT present in CI/fresh checkouts -- this whole module
      is tagged :integration and excluded from the default `mix test` run;
      run explicitly with `mix test --include integration`)

  Known limitation (not fixed here, out of scope): PythonPort.run/1 calls
  System.cmd/3 with no timeout -- if the Python process hangs, this test
  (and production) will hang indefinitely.
  """

  use ExUnit.Case, async: true

  @moduletag :integration
  @moduletag timeout: 180_000

  alias MouseTracker.Tracking.PythonPort

  @video_path Path.expand("data/NRS_25.01.19_Animal 11_M.mp4", File.cwd!())

  setup do
    if File.exists?(@video_path) do
      :ok
    else
      {:skip,
       "sample video not found at #{@video_path} -- data/ is gitignored; skipping integration test"}
    end
  end

  test "runs the tracker against a real sample video and decodes the result" do
    params = %{
      "video" => @video_path,
      "valid_region" => [0, 0, 4000, 4000],
      "start_time" => 0,
      "end_time" => 3,
      "threshold" => 80,
      "min_area" => 250,
      "px_per_10cm" => 1.0
    }

    assert {:ok, result} = PythonPort.run(params)

    assert is_map(result)

    for key <- ~w[distance_px distance_cm speed_mean_px speed_mean_cm
                  speed_median_px speed_median_cm speed_max_px speed_max_cm
                  immobility_seconds path_tortuosity thigmotaxis_pct] do
      assert Map.has_key?(result, key), "missing key #{key} in result"
    end

    assert is_number(result["distance_px"])
    assert is_number(result["distance_cm"])
    assert is_number(result["speed_mean_px"])
    assert is_number(result["speed_mean_cm"])
    assert is_number(result["speed_median_px"])
    assert is_number(result["speed_median_cm"])
    assert is_number(result["speed_max_px"])
    assert is_number(result["speed_max_cm"])
    assert is_number(result["immobility_seconds"])
    assert is_number(result["path_tortuosity"])
    assert is_number(result["thigmotaxis_pct"])
    assert is_list(result["frames_into_roi"])
    assert is_list(result["time_into_roi_s"])
  end
end
