defmodule MouseTrackerWeb.LiveHelpers do
  @moduledoc """
  Small helpers shared across LiveViews that are not view-specific enough to
  live in a single module, and not presentational enough to be a component.
  """

  @doc """
  Merges `overrides` into a base keyword list of URL params, dropping any
  key whose value is `nil` or `"all"` (the "unset" sentinel used by scope
  filters), for building `push_patch/2` query strings.
  """
  def patch_params(base, overrides) do
    base
    |> Keyword.merge(overrides)
    |> Enum.reject(fn {_k, v} -> v in [nil, "all"] end)
  end
end
