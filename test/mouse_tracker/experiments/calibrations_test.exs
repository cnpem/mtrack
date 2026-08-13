defmodule MouseTracker.Experiments.CalibrationsTest do
  use MouseTracker.DataCase, async: true

  import MouseTracker.AccountsFixtures
  import MouseTracker.ExperimentsFixtures

  alias MouseTracker.Experiments.Calibrations

  describe "update_calibration/3" do
    test "atualiza threshold da calibração" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      cal = calibration_fixture(user)

      assert {:ok, updated} = Calibrations.update_calibration(scope, cal, %{threshold: 120})
      assert updated.threshold == 120

      assert Calibrations.get_calibration!(scope, cal.id).threshold == 120
    end

    test "retorna erro com cage_side_cm <= 0" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      cal = calibration_fixture(user)

      assert {:error, changeset} =
               Calibrations.update_calibration(scope, cal, %{cage_side_cm: -1.0})

      assert errors_on(changeset).cage_side_cm != []
    end

    test "levanta erro se a calibração pertencer a outro usuário" do
      cal = calibration_fixture(user_fixture())
      other_scope = user_scope_fixture(user_fixture())

      assert_raise FunctionClauseError, fn ->
        Calibrations.update_calibration(other_scope, cal, %{threshold: 100})
      end
    end
  end

  describe "delete_calibration/2" do
    test "remove a calibração do banco" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      cal = calibration_fixture(user)

      assert {:ok, _} = Calibrations.delete_calibration(scope, cal)

      assert_raise Ecto.NoResultsError, fn ->
        Calibrations.get_calibration!(scope, cal.id)
      end
    end

    test "levanta erro se a calibração pertencer a outro usuário" do
      cal = calibration_fixture(user_fixture())
      other_scope = user_scope_fixture(user_fixture())

      assert_raise FunctionClauseError, fn ->
        Calibrations.delete_calibration(other_scope, cal)
      end
    end
  end

  describe "count_videos_using_calibration/1" do
    test "0 quando nenhum vídeo usa a calibração" do
      cal = calibration_fixture(user_fixture())
      assert Calibrations.count_videos_using_calibration(cal) == 0
    end

    test "conta vídeos apontando para a calibração, de qualquer status" do
      user = user_fixture()
      exp = experiment_fixture(user)
      cal = calibration_fixture(user)
      video_fixture(exp, cal, %{status: "pending"})
      video_fixture(exp, cal, %{status: "done"})
      _other = video_fixture(exp)

      assert Calibrations.count_videos_using_calibration(cal) == 2
    end
  end
end
