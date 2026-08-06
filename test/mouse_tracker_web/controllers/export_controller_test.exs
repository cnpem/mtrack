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
          ~p"/experiments/#{exp.id}/export?#{[format: "csv", date: "1", video: "1", calibration: "1"]}"
        )

      assert get_resp_header(conn, "content-type") |> List.first() =~ "text/csv"
      assert get_resp_header(conn, "content-disposition") |> List.first() =~ "attachment"
      body = response(conn, 200)
      assert body =~ "Cobaia (grupo)"
      assert body =~ "M01 (CNO)"
    end

    test "downloads XLSX (ZIP) binary", %{conn: conn, user: user} do
      exp = experiment_with_result(user)

      conn = get(conn, ~p"/experiments/#{exp.id}/export?#{[format: "xlsx"]}")

      assert get_resp_header(conn, "content-type")
             |> List.first() =~ "spreadsheetml"

      assert response(conn, 200) |> String.starts_with?("PK")
    end

    test "raises for an experiment owned by another user", %{conn: conn} do
      other = MouseTracker.AccountsFixtures.user_fixture()
      exp = experiment_with_result(other)

      assert_raise Ecto.NoResultsError, fn ->
        get(conn, ~p"/experiments/#{exp.id}/export?#{[format: "csv"]}")
      end
    end
  end
end
