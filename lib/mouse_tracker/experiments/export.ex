defmodule MouseTracker.Experiments.Export do
  @moduledoc """
  Builds a tabular export of one experiment's data and encodes it as CSV or
  XLSX. Pure functions (no `conn`/`socket`) so they're easily testable — the
  `MouseTrackerWeb.ExportController` just loads the experiment (see
  `MouseTracker.Experiments.get_experiment_for_export!/2`), calls `build_rows/2`
  and pipes the result through `to_csv/1` or `to_xlsx/2`.

  Layout (one row per processed video/session):

    * column 1 is always `Cobaia (grupo)` (`subject.name` + ` (group)` when set),
    * the core locomotion metrics and one `tempo_<roi>_s` column per ROI used in
      the experiment are always present,
    * the `:date`, `:video` and `:calibration` metadata groups are opt-in via the
      `opts` map (chosen by the user in the export panel).

  Only videos that have a `tracking_result` (i.e. processed) are exported; the
  rest are skipped. Cells are kept as native values (numbers, `Date`, strings,
  `nil`) so each encoder decides serialization — XLSX keeps numbers numeric,
  CSV stringifies with a `.` decimal separator.
  """

  NimbleCSV.define(MouseTracker.Experiments.Export.CSV, separator: ",", escape: "\"")

  alias MouseTracker.Experiments.Export.CSV

  @metric_fields [
    {"distância_cm", :distance_cm},
    {"vel_média_cm_s", :speed_mean_cm},
    {"vel_mediana_cm_s", :speed_median_cm},
    {"vel_máx_cm_s", :speed_max_cm},
    {"tigmotaxia_pct", :thigmotaxis_pct},
    {"imobilidade_s", :immobility_seconds},
    {"tortuosidade", :path_tortuosity}
  ]

  @video_fields [
    {"arquivo", :filename},
    {"duração_s", :duration_seconds},
    {"fps", :fps},
    {"análise_início_s", :start_time_seconds},
    {"análise_fim_s", :end_time_seconds}
  ]

  @calibration_fields [
    {"px_per_10cm", :px_per_10cm},
    {"threshold", :threshold},
    {"min_area", :min_area},
    {"peripheral_pct", :peripheral_pct},
    {"immobility_threshold_cm", :immobility_threshold_cm}
  ]

  @doc """
  Builds `{headers, rows}` for `experiment` (preloaded via
  `get_experiment_for_export!/2`). `opts` is a map of booleans toggling the
  optional metadata groups: `%{date: bool, video: bool, calibration: bool}`
  (missing keys default to `false`).
  """
  def build_rows(experiment, opts \\ %{}) do
    opts = %{
      date: Map.get(opts, :date, false),
      video: Map.get(opts, :video, false),
      calibration: Map.get(opts, :calibration, false)
    }

    videos =
      experiment.videos
      |> Enum.filter(&(&1.tracking_result != nil))
      |> Enum.sort_by(&{subject_sort_key(&1.subject), &1.id})

    roi_names = roi_names(videos)
    headers = header_row(opts, roi_names)
    rows = Enum.map(videos, &video_row(&1, opts, roi_names))

    {headers, rows}
  end

  # UTF-8 byte-order mark. Prepended to the CSV so Excel (notably pt-BR/Windows,
  # which otherwise assumes Windows-1252) detects UTF-8 and renders accented
  # headers/labels (e.g. "distância_cm") correctly.
  @utf8_bom "﻿"

  @doc "Encodes a `{headers, rows}` table as RFC4180 CSV (`,` separator, `.` decimal), BOM-prefixed for Excel."
  def to_csv({headers, rows}) do
    body =
      [headers | rows]
      |> Enum.map(fn row -> Enum.map(row, &csv_cell/1) end)
      |> CSV.dump_to_iodata()

    [@utf8_bom | body]
  end

  @doc "Encodes a `{headers, rows}` table as an `.xlsx` binary (single sheet)."
  def to_xlsx({headers, rows}, sheet_name) do
    sheet_rows = [headers | Enum.map(rows, fn row -> Enum.map(row, &xlsx_cell/1) end)]
    sheet = %Elixlsx.Sheet{name: sheet_name, rows: sheet_rows}

    {:ok, {_name, binary}} =
      Elixlsx.write_to_memory(%Elixlsx.Workbook{sheets: [sheet]}, "export.xlsx")

    binary
  end

  # --- headers ---

  defp header_row(opts, roi_names) do
    ["Cobaia (grupo)"]
    |> maybe_concat(opts.video, Enum.map(@video_fields, &elem(&1, 0)))
    |> maybe_concat(opts.date, ["processado_em"])
    |> Kernel.++(Enum.map(@metric_fields, &elem(&1, 0)))
    |> Kernel.++(Enum.map(roi_names, &"tempo_#{&1}_s"))
    |> maybe_concat(opts.calibration, Enum.map(@calibration_fields, &elem(&1, 0)))
  end

  # --- one data row ---

  defp video_row(video, opts, roi_names) do
    result = video.tracking_result

    [cobaia_label(video.subject)]
    |> maybe_concat(opts.video, Enum.map(@video_fields, fn {_h, f} -> Map.get(video, f) end))
    |> maybe_concat(opts.date, [as_date(result.processed_at)])
    |> Kernel.++(Enum.map(@metric_fields, fn {_h, f} -> Map.get(result, f) end))
    |> Kernel.++(roi_seconds_cells(result, roi_names))
    |> maybe_concat(opts.calibration, calibration_cells(video.calibration))
  end

  defp calibration_cells(nil), do: Enum.map(@calibration_fields, fn _ -> nil end)

  defp calibration_cells(cal),
    do: Enum.map(@calibration_fields, fn {_h, f} -> Map.get(cal, f) end)

  defp roi_seconds_cells(result, roi_names) do
    by_name =
      Map.new(result.roi_times, fn rt -> {rt.roi.name, rt.seconds} end)

    Enum.map(roi_names, &Map.get(by_name, &1))
  end

  # --- helpers ---

  defp roi_names(videos) do
    videos
    |> Enum.flat_map(fn v -> Enum.map(v.tracking_result.roi_times, & &1.roi.name) end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp cobaia_label(nil), do: ""

  defp cobaia_label(%{name: name, group: group}) when is_binary(group) and group != "",
    do: "#{name} (#{group})"

  defp cobaia_label(%{name: name}), do: name

  defp subject_sort_key(nil), do: "￿"
  defp subject_sort_key(%{name: name}), do: name

  defp maybe_concat(list, true, extra), do: list ++ extra
  defp maybe_concat(list, false, _extra), do: list

  defp as_date(%DateTime{} = dt), do: DateTime.to_date(dt)
  defp as_date(%NaiveDateTime{} = dt), do: NaiveDateTime.to_date(dt)
  defp as_date(%Date{} = d), do: d
  defp as_date(_), do: nil

  # --- cell serialization ---

  defp csv_cell(nil), do: ""
  defp csv_cell(value) when is_binary(value), do: value
  defp csv_cell(value) when is_integer(value), do: Integer.to_string(value)
  defp csv_cell(value) when is_float(value), do: value |> Float.round(3) |> Float.to_string()
  defp csv_cell(%Date{} = d), do: Date.to_iso8601(d)
  defp csv_cell(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp csv_cell(value), do: to_string(value)

  defp xlsx_cell(nil), do: ""
  defp xlsx_cell(value) when is_number(value), do: value
  defp xlsx_cell(%Date{} = d), do: Date.to_iso8601(d)
  defp xlsx_cell(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp xlsx_cell(value), do: value
end
