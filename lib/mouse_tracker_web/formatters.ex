defmodule MouseTrackerWeb.Formatters do
  @moduledoc """
  Small display-formatting helpers shared by the LiveViews that render
  tracking metrics (Results, Datasets, Analyses, Pipeline Settings). Imported
  globally via `MouseTrackerWeb.html_helpers/0`, same as `CoreComponents`/
  `LocomoComponents`.
  """

  @doc "Formats a number for display, or an em dash when nil."
  def fmt(nil), do: "—"
  def fmt(n) when is_integer(n), do: Integer.to_string(n)
  def fmt(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 1)

  @doc "Formats a `%{mean:, sd:}` aggregate (see `Experiments.subject_metric_aggregate/1`)."
  def stat_fmt(%{mean: nil}), do: "—"
  def stat_fmt(%{mean: mean, sd: nil}), do: fmt(mean)
  def stat_fmt(%{mean: mean, sd: sd}), do: "#{fmt(mean)} ± #{fmt(sd)}"

  @doc "Parses a URL query param into an integer id, or nil if absent/invalid."
  def parse_int(nil), do: nil

  def parse_int(str) do
    case Integer.parse(str) do
      {id, ""} -> id
      _ -> nil
    end
  end
end
