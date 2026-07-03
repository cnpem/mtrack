defmodule MouseTracker.Tracking.PythonPortBehaviour do
  @moduledoc """
  Behaviour for the Elixir<->Python tracking boundary, extracted so
  `MouseTracker.Workers.VideoProcessingWorker` can be tested with a
  Mox-generated mock instead of shelling out to `uv run python` in every test.
  """

  @callback run(params :: map()) :: {:ok, map()} | {:error, term()}
end
