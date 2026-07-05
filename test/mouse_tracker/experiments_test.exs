defmodule MouseTracker.ExperimentsTest do
  use MouseTracker.DataCase, async: true

  import MouseTracker.AccountsFixtures
  import MouseTracker.ExperimentsFixtures

  alias MouseTracker.Experiments

  # ---------------------------------------------------------------------------
  # Experiments
  # ---------------------------------------------------------------------------

  describe "list_experiments/1" do
    test "retorna apenas os experimentos do usuário" do
      user = user_fixture()
      other = user_fixture()
      scope = user_scope_fixture(user)
      exp = experiment_fixture(user)
      _other_exp = experiment_fixture(other)

      assert Experiments.list_experiments(scope) == [exp]
    end

    test "retorna lista vazia quando usuário não tem experimentos" do
      scope = user_scope_fixture()
      assert Experiments.list_experiments(scope) == []
    end
  end

  describe "get_experiment!/2" do
    test "retorna o experimento pelo id" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      exp = experiment_fixture(user)

      assert Experiments.get_experiment!(scope, exp.id) == exp
    end

    test "levanta erro se o experimento pertencer a outro usuário" do
      user = user_fixture()
      other = user_fixture()
      scope = user_scope_fixture(user)
      other_exp = experiment_fixture(other)

      assert_raise Ecto.NoResultsError, fn ->
        Experiments.get_experiment!(scope, other_exp.id)
      end
    end
  end

  describe "create_experiment/2" do
    test "cria experimento com attrs válidos" do
      scope = user_scope_fixture()

      assert {:ok, exp} = Experiments.create_experiment(scope, %{name: "Novo experimento"})
      assert exp.name == "Novo experimento"
    end

    test "retorna erro com nome em branco" do
      scope = user_scope_fixture()

      assert {:error, changeset} = Experiments.create_experiment(scope, %{name: ""})
      assert "can't be blank" in errors_on(changeset).name
    end

    test "retorna erro com nome duplicado para o mesmo usuário" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      experiment_fixture(user, %{name: "Nome Único"})

      assert {:error, changeset} = Experiments.create_experiment(scope, %{name: "Nome Único"})
      assert "has already been taken" in errors_on(changeset).name
    end

    test "permite o mesmo nome para usuários diferentes" do
      user1 = user_fixture()
      user2 = user_fixture()
      experiment_fixture(user1, %{name: "Compartilhado"})

      scope2 = user_scope_fixture(user2)
      assert {:ok, _exp} = Experiments.create_experiment(scope2, %{name: "Compartilhado"})
    end
  end

  describe "update_experiment/3" do
    test "atualiza o nome do experimento" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      exp = experiment_fixture(user)

      assert {:ok, updated} = Experiments.update_experiment(scope, exp, %{name: "Novo nome"})
      assert updated.name == "Novo nome"
    end

    test "retorna erro com attrs inválidos" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      exp = experiment_fixture(user)

      assert {:error, changeset} = Experiments.update_experiment(scope, exp, %{name: ""})
      assert "can't be blank" in errors_on(changeset).name
    end
  end

  describe "delete_experiment/2" do
    test "remove o experimento do banco" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      exp = experiment_fixture(user)

      assert {:ok, _} = Experiments.delete_experiment(scope, exp)

      assert_raise Ecto.NoResultsError, fn ->
        Experiments.get_experiment!(scope, exp.id)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Videos
  # ---------------------------------------------------------------------------

  describe "list_videos/1" do
    test "retorna apenas os vídeos do experimento" do
      user = user_fixture()
      exp1 = experiment_fixture(user)
      exp2 = experiment_fixture(user)
      video = video_fixture(exp1)
      _other = video_fixture(exp2)

      assert Experiments.list_videos(exp1) == [video]
    end
  end

  describe "create_video/2" do
    test "cria vídeo com attrs válidos" do
      exp = experiment_fixture(user_fixture())

      assert {:ok, video} =
               Experiments.create_video(exp, %{
                 filename: "clip.mp4",
                 filepath: "/tmp/clip.mp4"
               })

      assert video.filename == "clip.mp4"
      assert video.status == "pending"
    end

    test "retorna erro com filepath duplicado" do
      exp = experiment_fixture(user_fixture())
      video_fixture(exp, nil, %{filepath: "/tmp/dup.mp4"})

      assert {:error, changeset} =
               Experiments.create_video(exp, %{
                 filename: "outro.mp4",
                 filepath: "/tmp/dup.mp4"
               })

      assert "has already been taken" in errors_on(changeset).filepath
    end
  end

  describe "update_video/2" do
    test "atualiza o status do vídeo" do
      exp = experiment_fixture(user_fixture())
      video = video_fixture(exp)

      assert {:ok, updated} = Experiments.update_video(video, %{status: "done"})
      assert updated.status == "done"
    end

    test "retorna erro com status inválido" do
      exp = experiment_fixture(user_fixture())
      video = video_fixture(exp)

      assert {:error, changeset} = Experiments.update_video(video, %{status: "invalido"})
      assert errors_on(changeset).status != []
    end
  end

  describe "delete_video/1" do
    test "remove o vídeo do banco" do
      exp = experiment_fixture(user_fixture())
      video = video_fixture(exp)

      assert {:ok, _} = Experiments.delete_video(video)
      assert Experiments.list_videos(exp) == []
    end
  end

  # ---------------------------------------------------------------------------
  # Calibrations
  # ---------------------------------------------------------------------------

  describe "update_calibration/2" do
    test "atualiza threshold da calibração" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      cal = calibration_fixture(user)

      assert {:ok, updated} = Experiments.update_calibration(cal, %{threshold: 120})
      assert updated.threshold == 120

      assert Experiments.get_calibration!(scope, cal.id).threshold == 120
    end

    test "retorna erro com cage_side_cm <= 0" do
      cal = calibration_fixture(user_fixture())

      assert {:error, changeset} = Experiments.update_calibration(cal, %{cage_side_cm: -1.0})
      assert errors_on(changeset).cage_side_cm != []
    end
  end

  describe "delete_calibration/1" do
    test "remove a calibração do banco" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      cal = calibration_fixture(user)

      assert {:ok, _} = Experiments.delete_calibration(cal)

      assert_raise Ecto.NoResultsError, fn ->
        Experiments.get_calibration!(scope, cal.id)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # ROIs
  # ---------------------------------------------------------------------------

  describe "get_roi!/2" do
    test "retorna a ROI pelo id dentro do escopo do usuário" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      exp = experiment_fixture(user)
      video = video_fixture(exp)
      roi = roi_fixture(video)

      assert Experiments.get_roi!(scope, roi.id) == roi
    end

    test "levanta erro se ROI pertencer a outro usuário" do
      exp = experiment_fixture(user_fixture())
      video = video_fixture(exp)
      roi = roi_fixture(video)

      other_scope = user_scope_fixture(user_fixture())

      assert_raise Ecto.NoResultsError, fn ->
        Experiments.get_roi!(other_scope, roi.id)
      end
    end
  end

  describe "list_rois/1" do
    test "retorna apenas as ROIs do usuário" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      exp = experiment_fixture(user)
      video = video_fixture(exp)
      roi = roi_fixture(video)

      _other = roi_fixture(video_fixture(experiment_fixture(user_fixture())))

      assert Experiments.list_rois(scope) == [roi]
    end
  end

  describe "attach/detach ROI em vídeo" do
    test "anexa e lista ROIs de um vídeo, e remove o vínculo" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      exp = experiment_fixture(user)
      video = video_fixture(exp)

      {:ok, roi} =
        Experiments.create_roi(scope, %{name: "Zona A", x: 0, y: 0, w: 10, h: 10})

      assert :ok = Experiments.attach_roi_to_video(video, roi)
      assert Experiments.list_rois_for_video(video) |> Enum.map(& &1.id) == [roi.id]

      # idempotente: anexar de novo não duplica
      assert :ok = Experiments.attach_roi_to_video(video, roi)
      assert length(Experiments.list_rois_for_video(video)) == 1

      assert :ok = Experiments.detach_roi_from_video(video, roi)
      assert Experiments.list_rois_for_video(video) == []
      # a ROI continua existindo, só o vínculo foi removido
      assert Experiments.get_roi!(scope, roi.id).id == roi.id
    end
  end

  describe "update_roi/2" do
    test "atualiza as coordenadas da ROI" do
      exp = experiment_fixture(user_fixture())
      video = video_fixture(exp)
      roi = roi_fixture(video)

      assert {:ok, updated} = Experiments.update_roi(roi, %{x: 50, y: 50})
      assert updated.x == 50
      assert updated.y == 50
    end

    test "retorna erro com w <= 0" do
      exp = experiment_fixture(user_fixture())
      video = video_fixture(exp)
      roi = roi_fixture(video)

      assert {:error, changeset} = Experiments.update_roi(roi, %{w: 0})
      assert errors_on(changeset).w != []
    end
  end

  describe "delete_roi/1" do
    test "remove a ROI do banco" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      exp = experiment_fixture(user)
      video = video_fixture(exp)
      roi = roi_fixture(video)

      assert {:ok, _} = Experiments.delete_roi(roi)
      assert Experiments.list_rois(scope) == []
      assert Experiments.list_rois_for_video(video) == []
    end
  end

  # ---------------------------------------------------------------------------
  # RoiTimes
  # ---------------------------------------------------------------------------

  describe "list_roi_times/1" do
    test "retorna apenas os roi_times da ROI" do
      exp = experiment_fixture(user_fixture())
      video = video_fixture(exp)
      roi1 = roi_fixture(video)
      roi2 = roi_fixture(video)
      result = tracking_result_fixture(video)

      rt = roi_time_fixture(roi1, result)
      _other = roi_time_fixture(roi2, result, %{frame_count: 60, seconds: 2.0})

      assert Experiments.list_roi_times(roi1) == [rt]
    end
  end

  describe "get_roi_time!/1" do
    test "retorna o roi_time pelo id" do
      exp = experiment_fixture(user_fixture())
      video = video_fixture(exp)
      roi = roi_fixture(video)
      result = tracking_result_fixture(video)
      rt = roi_time_fixture(roi, result)

      assert Experiments.get_roi_time!(rt.id) == rt
    end

    test "levanta erro para id inexistente" do
      assert_raise Ecto.NoResultsError, fn ->
        Experiments.get_roi_time!(0)
      end
    end
  end

  describe "create_roi_time/3" do
    test "cria roi_time com attrs válidos" do
      exp = experiment_fixture(user_fixture())
      video = video_fixture(exp)
      roi = roi_fixture(video)
      result = tracking_result_fixture(video)

      assert {:ok, rt} =
               Experiments.create_roi_time(roi, result, %{frame_count: 90, seconds: 3.0})

      assert rt.frame_count == 90
      assert rt.seconds == 3.0
    end

    test "retorna erro com combinação duplicada roi + tracking_result" do
      exp = experiment_fixture(user_fixture())
      video = video_fixture(exp)
      roi = roi_fixture(video)
      result = tracking_result_fixture(video)
      roi_time_fixture(roi, result)

      assert {:error, changeset} =
               Experiments.create_roi_time(roi, result, %{frame_count: 10, seconds: 0.5})

      assert "has already been taken" in errors_on(changeset).roi_id
    end
  end
end
