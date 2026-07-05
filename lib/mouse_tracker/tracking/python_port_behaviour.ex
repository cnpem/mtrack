defmodule MouseTracker.Tracking.PythonPortBehaviour do
  @moduledoc """
  Behaviour for the Elixir<->Python tracking boundary, extracted so
  `MouseTracker.Workers.VideoProcessingWorker` can be tested with a
  Mox-generated mock instead of shelling out to `uv run python` in every test.
  """

  @typedoc "Called for every `{\"type\":\"progress\",...}` line the Python process emits."
  @type on_progress :: (map() -> any())

  @callback run(params :: map(), on_progress :: on_progress()) ::
              {:ok, map()} | {:error, term()}
end
