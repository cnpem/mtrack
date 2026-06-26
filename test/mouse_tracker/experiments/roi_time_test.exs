defmodule MouseTracker.Experiments.RoiTimeTest do
  use MouseTracker.DataCase, async: true

  import MouseTracker.AccountsFixtures
  import MouseTracker.ExperimentsFixtures

  alias MouseTracker.Experiments.RoiTime

  describe "changeset/2" do
    setup do
      user = user_fixture()
      experiment = experiment_fixture(user)
      video = video_fixture(experiment)
      roi = roi_fixture(video)
      tracking_result = tracking_result_fixture(video)
      %{roi: roi, tracking_result: tracking_result}
    end

    test "válido com campos obrigatórios", %{roi: roi, tracking_result: tracking_result} do
      changeset =
        RoiTime.changeset(
          %RoiTime{roi_id: roi.id, tracking_result_id: tracking_result.id},
          %{frame_count: 120, seconds: 4.0}
        )

      assert changeset.valid?
    end

    test "inválido sem frame_count", %{roi: roi, tracking_result: tracking_result} do
      changeset =
        RoiTime.changeset(
          %RoiTime{roi_id: roi.id, tracking_result_id: tracking_result.id},
          %{seconds: 4.0}
        )

      assert "can't be blank" in errors_on(changeset).frame_count
    end

    test "inválido sem seconds", %{roi: roi, tracking_result: tracking_result} do
      changeset =
        RoiTime.changeset(
          %RoiTime{roi_id: roi.id, tracking_result_id: tracking_result.id},
          %{frame_count: 120}
        )

      assert "can't be blank" in errors_on(changeset).seconds
    end

    test "frame_count negativo é inválido", %{roi: roi, tracking_result: tracking_result} do
      changeset =
        RoiTime.changeset(
          %RoiTime{roi_id: roi.id, tracking_result_id: tracking_result.id},
          %{frame_count: -1, seconds: 4.0}
        )

      assert errors_on(changeset).frame_count != []
    end

    test "seconds negativo é inválido", %{roi: roi, tracking_result: tracking_result} do
      changeset =
        RoiTime.changeset(
          %RoiTime{roi_id: roi.id, tracking_result_id: tracking_result.id},
          %{frame_count: 120, seconds: -0.1}
        )

      assert errors_on(changeset).seconds != []
    end

    test "par (roi_id, tracking_result_id) duplicado falha no banco",
         %{roi: roi, tracking_result: tracking_result} do
      roi_time_fixture(roi, tracking_result)

      assert {:error, changeset} =
               %RoiTime{roi_id: roi.id, tracking_result_id: tracking_result.id}
               |> RoiTime.changeset(%{frame_count: 60, seconds: 2.0})
               |> Repo.insert()

      assert "has already been taken" in errors_on(changeset).roi_id
    end
  end
end
