defmodule MouseTrackerWeb.ExportController do
  @moduledoc """
  Downloads one experiment's data as CSV and/or XLSX. LiveView can't trigger a
  browser file download directly, so `ExperimentLive.Show`'s export panel points
  a plain `<.link download>` at this controller, encoding the selected formats and
  metadata groups in the query string (`?csv=1&xlsx=1&date=1&video=1&calibration=0`).

  When more than one output file is selected — either both formats, or any
  images (`heatmap=1`/`speed=1`) alongside a format — the response becomes a
  `.zip` bundling everything; a single selection downloads that one file
  directly. Images already exist on disk under
  `priv/static/uploads/results/<video_id>/`, so this just reads and packs them.
  """
  use MouseTrackerWeb, :controller

  alias MouseTracker.Experiments
  alias MouseTracker.Experiments.Export

  def experiment(conn, %{"id" => id} = params) do
    experiment = Experiments.get_experiment_for_export!(conn.assigns.current_scope, id)

    meta_opts = %{
      date: params["date"] == "1",
      video: params["video"] == "1",
      calibration: params["calibration"] == "1"
    }

    image_opts = %{heatmap: params["heatmap"] == "1", speed: params["speed"] == "1"}

    slug = slugify(experiment.name)
    table = Export.build_rows(experiment, meta_opts)

    metrics_entries =
      for format <- selected_formats(params), do: metrics_file(table, slug, format)

    case metrics_entries ++ collect_images(experiment, image_opts) do
      [] ->
        conn |> put_status(:bad_request) |> text("Select at least one format to export.")

      [{name, bin, type}] ->
        send_download(conn, {:binary, bin}, filename: name, content_type: type)

      entries ->
        zip_entries =
          Enum.map(entries, fn {name, bin, _type} -> {String.to_charlist(name), bin} end)

        {:ok, {_name, zip}} = :zip.create(~c"#{slug}.zip", zip_entries, [:memory])

        send_download(conn, {:binary, zip},
          filename: "#{slug}.zip",
          content_type: "application/zip"
        )
    end
  end

  defp selected_formats(params) do
    for {key, format} <- [{"csv", "csv"}, {"xlsx", "xlsx"}], params[key] == "1", do: format
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
      {"images/#{base}_#{suffix}.png", bytes, "image/png"}
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
