defmodule MouseTrackerWeb.ExportController do
  @moduledoc """
  Downloads one experiment's data as CSV or XLSX. LiveView can't trigger a
  browser file download directly, so `ExperimentLive.Show`'s export panel points
  a plain `<.link download>` at this controller, encoding the selected format and
  metadata groups in the query string (`?format=csv&date=1&video=1&calibration=0`).

  When `heatmap=1` and/or `speed=1` are set, the response becomes a `.zip`
  bundling the metrics file (in the chosen format) plus those PNGs for every
  "done" video — the images already exist on disk under
  `priv/static/uploads/results/<video_id>/`, so this just reads and packs them.
  """
  use MouseTrackerWeb, :controller

  alias MouseTracker.Experiments
  alias MouseTracker.Experiments.Export

  def experiment(conn, %{"id" => id} = params) do
    experiment = Experiments.get_experiment_for_export!(conn.assigns.current_scope, id)

    opts = %{
      date: params["date"] == "1",
      video: params["video"] == "1",
      calibration: params["calibration"] == "1"
    }

    table = Export.build_rows(experiment, opts)
    slug = slugify(experiment.name)
    format = if params["format"] == "xlsx", do: "xlsx", else: "csv"
    {metrics_name, metrics_bin, metrics_type} = metrics_file(table, slug, format)

    image_opts = %{heatmap: params["heatmap"] == "1", speed: params["speed"] == "1"}

    if image_opts.heatmap or image_opts.speed do
      entries = [
        {String.to_charlist(metrics_name), metrics_bin} | collect_images(experiment, image_opts)
      ]

      {:ok, {_name, zip}} = :zip.create(~c"#{slug}.zip", entries, [:memory])

      send_download(conn, {:binary, zip},
        filename: "#{slug}.zip",
        content_type: "application/zip"
      )
    else
      send_download(conn, {:binary, metrics_bin},
        filename: metrics_name,
        content_type: metrics_type
      )
    end
  end

  defp metrics_file(table, slug, "xlsx"),
    do:
      {"#{slug}.xlsx", Export.to_xlsx(table, "Experiment"),
       "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"}

  defp metrics_file(table, slug, _csv),
    do: {"#{slug}.csv", table |> Export.to_csv() |> IO.iodata_to_binary(), "text/csv"}

  # One PNG entry per (done video × selected image kind) that actually exists on
  # disk — missing files are skipped so a partially-processed experiment still
  # exports the images it does have.
  defp collect_images(experiment, opts) do
    for video <- experiment.videos,
        video.status == "done",
        result = video.tracking_result,
        not is_nil(result),
        {want?, web_path, suffix} <- [
          {opts.heatmap, result.heatmap_path, "heatmap"},
          {opts.speed, result.speed_profile_path, "speed"}
        ],
        want?,
        is_binary(web_path),
        bytes = read_static(web_path),
        not is_nil(bytes) do
      base = "#{Path.rootname(video.filename)}_#{video.id}"
      {String.to_charlist("images/#{base}_#{suffix}.png"), bytes}
    end
  end

  defp read_static(web_path) do
    case File.read(Path.join(static_dir(), web_path)) do
      {:ok, bin} -> bin
      _ -> nil
    end
  end

  defp static_dir, do: Path.join(:code.priv_dir(:mouse_tracker), "static")

  defp slugify(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "_")
    |> String.trim("_")
    |> case do
      "" -> "experiment"
      slug -> slug
    end
  end
end
