defmodule MouseTrackerWeb.ExportController do
  @moduledoc """
  Downloads one experiment's data as CSV or XLSX. LiveView can't trigger a
  browser file download directly, so `ExperimentLive.Show`'s export panel points
  a plain `<.link download>` at this controller, encoding the selected format and
  metadata groups in the query string (`?format=csv&date=1&video=1&calibration=0`).
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

    case params["format"] do
      "xlsx" ->
        conn
        |> send_download({:binary, Export.to_xlsx(table, "Experimento")},
          filename: "#{slug}.xlsx",
          content_type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        )

      _ ->
        csv = table |> Export.to_csv() |> IO.iodata_to_binary()

        conn
        |> send_download({:binary, csv}, filename: "#{slug}.csv", content_type: "text/csv")
    end
  end

  defp slugify(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "_")
    |> String.trim("_")
    |> case do
      "" -> "experimento"
      slug -> slug
    end
  end
end
