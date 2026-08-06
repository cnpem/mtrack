defmodule MouseTracker.Experiments.ExportTest do
  use MouseTracker.DataCase, async: true

  import MouseTracker.AccountsFixtures
  import MouseTracker.ExperimentsFixtures

  alias MouseTracker.Experiments
  alias MouseTracker.Experiments.Export

  @all_opts %{date: true, video: true, calibration: true}

  defp fixture_experiment(_) do
    user = user_fixture()
    scope = user_scope_fixture(user)
    cal = calibration_fixture(user)
    exp = experiment_fixture(user, %{name: "Open Field 1"})

    m01 = subject_fixture(user, %{name: "M01", group: "CNO"})
    m02 = subject_fixture(user, %{name: "M02", group: "Saline"})

    v1 = video_fixture(exp, cal, %{status: "done", subject_id: m01.id})
    tr1 = tracking_result_fixture(v1)
    roi = roi_fixture(v1, %{name: "centro"})
    roi_time_fixture(roi, tr1, %{seconds: 4.0})

    v2 = video_fixture(exp, cal, %{status: "done", subject_id: m02.id})
    tracking_result_fixture(v2)

    # A pending video without a tracking result — must be skipped by the export.
    video_fixture(exp, cal, %{status: "pending", subject_id: m01.id})

    %{scope: scope, experiment: Experiments.get_experiment_for_export!(scope, exp.id)}
  end

  describe "build_rows/2" do
    setup :fixture_experiment

    test "first column is the subject label and metrics/ROI columns are present", %{
      experiment: experiment
    } do
      {headers, rows} = Export.build_rows(experiment, @all_opts)

      assert List.first(headers) == "Cobaia (grupo)"
      assert "distância_cm" in headers
      assert "tempo_centro_s" in headers
      assert "px_per_10cm" in headers

      # Only the two "done" videos (with a tracking_result) are exported.
      assert length(rows) == 2

      # Rows are sorted by subject name, so M01 comes first.
      assert List.first(List.first(rows)) == "M01 (CNO)"
      assert List.first(Enum.at(rows, 1)) == "M02 (Saline)"
    end

    test "ROI time lands in the matching dynamic column", %{experiment: experiment} do
      {headers, rows} = Export.build_rows(experiment, @all_opts)
      idx = Enum.find_index(headers, &(&1 == "tempo_centro_s"))

      # M01's video had a roi_time of 4.0s in "centro"; M02's had none.
      assert Enum.at(List.first(rows), idx) == 4.0
      assert Enum.at(Enum.at(rows, 1), idx) == nil
    end

    test "calibration group is omitted when disabled", %{experiment: experiment} do
      {headers, _rows} = Export.build_rows(experiment, %{@all_opts | calibration: false})

      refute "px_per_10cm" in headers
      refute "threshold" in headers
    end

    test "video/date groups are omitted when disabled", %{experiment: experiment} do
      {headers, _rows} =
        Export.build_rows(experiment, %{date: false, video: false, calibration: false})

      refute "arquivo" in headers
      refute "processado_em" in headers
      # Metrics are always present.
      assert "distância_cm" in headers
    end
  end

  describe "to_csv/1" do
    setup :fixture_experiment

    test "produces a header row plus one row per video, with a dot decimal separator", %{
      experiment: experiment
    } do
      csv = experiment |> Export.build_rows(@all_opts) |> Export.to_csv() |> IO.iodata_to_binary()

      # UTF-8 BOM so Excel (pt-BR/Windows) renders the accented headers correctly.
      assert String.starts_with?(csv, "﻿")

      lines =
        csv
        |> String.trim_leading("﻿")
        |> String.split(~r/\r?\n/, trim: true)

      # header + 2 data rows
      assert length(lines) == 3
      assert lines |> List.first() |> String.starts_with?("Cobaia (grupo),")
      assert Enum.any?(lines, &String.contains?(&1, "M01 (CNO)"))
      # dot decimal, comma separator (the 4.0s ROI time)
      assert Enum.any?(lines, &String.contains?(&1, "4.0"))
    end
  end

  describe "to_xlsx/2" do
    setup :fixture_experiment

    test "produces a non-empty xlsx (ZIP) binary", %{experiment: experiment} do
      bin = experiment |> Export.build_rows(@all_opts) |> Export.to_xlsx("Experimento")

      assert is_binary(bin)
      assert byte_size(bin) > 0
      # xlsx is a ZIP container; ZIP files start with the "PK" local-file signature.
      assert String.starts_with?(bin, "PK")
    end
  end
end
