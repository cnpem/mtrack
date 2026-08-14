defmodule MouseTrackerWeb.ExportControllerTest do
  use MouseTrackerWeb.ConnCase, async: true

  import MouseTracker.ExperimentsFixtures

  setup :register_and_log_in_user

  defp experiment_with_result(user) do
    cal = calibration_fixture(user)
    exp = experiment_fixture(user, %{name: "Open Field"})
    subject = subject_fixture(user, %{name: "M01", group: "CNO"})
    video = video_fixture(exp, cal, %{status: "done", subject_id: subject.id})
    tracking_result_fixture(video)
    exp
  end

  describe "GET /experiments/:id/export" do
    test "downloads CSV with attachment headers and subject data", %{conn: conn, user: user} do
      exp = experiment_with_result(user)

      conn =
        get(
          conn,
          ~p"/experiments/#{exp.id}/export?#{[csv: "1", date: "1", video: "1", calibration: "1"]}"
        )

      assert get_resp_header(conn, "content-type") |> List.first() =~ "text/csv"
      assert get_resp_header(conn, "content-disposition") |> List.first() =~ "attachment"
      body = response(conn, 200)
      assert body =~ "Subject (group)"
      assert body =~ "M01 (CNO)"
    end

    test "downloads XLSX (ZIP) binary", %{conn: conn, user: user} do
      exp = experiment_with_result(user)

      conn = get(conn, ~p"/experiments/#{exp.id}/export?#{[xlsx: "1"]}")

      assert get_resp_header(conn, "content-type")
             |> List.first() =~ "spreadsheetml"

      assert response(conn, 200) |> String.starts_with?("PK")
    end

    test "downloads both CSV and XLSX together as a single .zip", %{conn: conn, user: user} do
      exp = experiment_with_result(user)

      conn = get(conn, ~p"/experiments/#{exp.id}/export?#{[csv: "1", xlsx: "1"]}")

      assert get_resp_header(conn, "content-type") |> List.first() =~ "application/zip"
      body = response(conn, 200)
      {:ok, entries} = :zip.extract(body, [:memory])
      names = Enum.map(entries, fn {name, _} -> to_string(name) end)
      assert Enum.any?(names, &String.ends_with?(&1, ".csv"))
      assert Enum.any?(names, &String.ends_with?(&1, ".xlsx"))
    end

    test "returns 400 when no format is selected", %{conn: conn, user: user} do
      exp = experiment_with_result(user)

      conn = get(conn, ~p"/experiments/#{exp.id}/export")

      assert conn.status == 400
    end

    test "bundles selected images into a .zip alongside the metrics", %{conn: conn, user: user} do
      cal = calibration_fixture(user)
      exp = experiment_fixture(user, %{name: "Open Field"})
      video = video_fixture(exp, cal, %{status: "done", filename: "m01.mp4"})

      tracking_result_fixture(video, %{
        heatmap_path: "/uploads/results/#{video.id}/heatmap.png",
        speed_profile_path: "/uploads/results/#{video.id}/speed_profile.png"
      })

      # The controller reads the PNGs from disk under priv/static — write fakes.
      dir =
        Path.join([
          :code.priv_dir(:mouse_tracker),
          "static",
          "uploads",
          "results",
          to_string(video.id)
        ])

      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "heatmap.png"), "PNG-heatmap")
      File.write!(Path.join(dir, "speed_profile.png"), "PNG-speed")
      on_exit(fn -> File.rm_rf(dir) end)

      conn =
        get(conn, ~p"/experiments/#{exp.id}/export?#{[csv: "1", heatmap: "1", speed: "1"]}")

      assert get_resp_header(conn, "content-type") |> List.first() =~ "application/zip"
      body = response(conn, 200)
      assert String.starts_with?(body, "PK")

      {:ok, entries} = :zip.extract(body, [:memory])
      names = Enum.map(entries, fn {name, _} -> to_string(name) end)
      assert Enum.any?(names, &String.ends_with?(&1, ".csv"))
      assert Enum.any?(names, &String.contains?(&1, "heatmap"))
      assert Enum.any?(names, &String.contains?(&1, "speed"))
    end

    test "bundles just the requested images into a .zip when no format is selected", %{
      conn: conn,
      user: user
    } do
      cal = calibration_fixture(user)
      exp = experiment_fixture(user, %{name: "Open Field"})
      video = video_fixture(exp, cal, %{status: "done", filename: "m01.mp4"})

      tracking_result_fixture(video, %{
        heatmap_path: "/uploads/results/#{video.id}/heatmap.png"
      })

      dir =
        Path.join([
          :code.priv_dir(:mouse_tracker),
          "static",
          "uploads",
          "results",
          to_string(video.id)
        ])

      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "heatmap.png"), "PNG-heatmap")
      on_exit(fn -> File.rm_rf(dir) end)

      conn = get(conn, ~p"/experiments/#{exp.id}/export?#{[heatmap: "1"]}")

      assert get_resp_header(conn, "content-type") |> List.first() =~ "image/png"
      assert response(conn, 200) == "PNG-heatmap"
    end

    test "raises for an experiment owned by another user", %{conn: conn} do
      other = MouseTracker.AccountsFixtures.user_fixture()
      exp = experiment_with_result(other)

      assert_raise Ecto.NoResultsError, fn ->
        get(conn, ~p"/experiments/#{exp.id}/export?#{[csv: "1"]}")
      end
    end
  end
end
