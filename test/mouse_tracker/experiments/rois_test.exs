defmodule MouseTracker.Experiments.RoisTest do
  use MouseTracker.DataCase, async: true

  import MouseTracker.AccountsFixtures
  import MouseTracker.ExperimentsFixtures

  alias MouseTracker.Experiments.Rois

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

      assert Rois.get_roi!(scope, roi.id) == roi
    end

    test "levanta erro se ROI pertencer a outro usuário" do
      exp = experiment_fixture(user_fixture())
      video = video_fixture(exp)
      roi = roi_fixture(video)

      other_scope = user_scope_fixture(user_fixture())

      assert_raise Ecto.NoResultsError, fn ->
        Rois.get_roi!(other_scope, roi.id)
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

      assert Rois.list_rois(scope) == [roi]
    end
  end

  describe "attach/detach ROI em vídeo" do
    test "anexa e lista ROIs de um vídeo, e remove o vínculo" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      exp = experiment_fixture(user)
      video = video_fixture(exp)

      {:ok, roi} =
        Rois.create_roi(scope, %{name: "Zona A", x: 0, y: 0, w: 10, h: 10})

      assert :ok = Rois.attach_roi_to_video(video, roi)
      assert Rois.list_rois_for_video(video) |> Enum.map(& &1.id) == [roi.id]

      # idempotente: anexar de novo não duplica
      assert :ok = Rois.attach_roi_to_video(video, roi)
      assert length(Rois.list_rois_for_video(video)) == 1

      assert :ok = Rois.detach_roi_from_video(video, roi)
      assert Rois.list_rois_for_video(video) == []
      # a ROI continua existindo, só o vínculo foi removido
      assert Rois.get_roi!(scope, roi.id).id == roi.id
    end
  end

  describe "update_roi/3" do
    test "atualiza as coordenadas da ROI" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      exp = experiment_fixture(user)
      video = video_fixture(exp)
      roi = roi_fixture(video)

      assert {:ok, updated} = Rois.update_roi(scope, roi, %{x: 50, y: 50})
      assert updated.x == 50
      assert updated.y == 50
    end

    test "retorna erro com w <= 0" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      exp = experiment_fixture(user)
      video = video_fixture(exp)
      roi = roi_fixture(video)

      assert {:error, changeset} = Rois.update_roi(scope, roi, %{w: 0})
      assert errors_on(changeset).w != []
    end

    test "levanta erro se a ROI pertencer a outro usuário" do
      exp = experiment_fixture(user_fixture())
      video = video_fixture(exp)
      roi = roi_fixture(video)

      other_scope = user_scope_fixture(user_fixture())

      assert_raise FunctionClauseError, fn ->
        Rois.update_roi(other_scope, roi, %{x: 50})
      end
    end
  end

  describe "delete_roi/2" do
    test "remove a ROI do banco" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      exp = experiment_fixture(user)
      video = video_fixture(exp)
      roi = roi_fixture(video)

      assert {:ok, _} = Rois.delete_roi(scope, roi)
      assert Rois.list_rois(scope) == []
      assert Rois.list_rois_for_video(video) == []
    end
  end

  describe "roi_locked?/1" do
    test "false quando a ROI não está anexada a nenhum vídeo" do
      exp = experiment_fixture(user_fixture())
      video = video_fixture(exp)
      roi = roi_fixture(video)
      Rois.detach_roi_from_video(video, roi)

      refute Rois.roi_locked?(roi)
    end

    test "false quando só há vídeos pending usando a ROI" do
      exp = experiment_fixture(user_fixture())
      video = video_fixture(exp, nil, %{status: "pending"})
      roi = roi_fixture(video)

      refute Rois.roi_locked?(roi)
    end

    test "true quando há um vídeo done usando a ROI" do
      exp = experiment_fixture(user_fixture())
      video = video_fixture(exp, nil, %{status: "done"})
      roi = roi_fixture(video)

      assert Rois.roi_locked?(roi)
    end

    test "true quando há um vídeo processing usando a ROI" do
      exp = experiment_fixture(user_fixture())
      video = video_fixture(exp, nil, %{status: "processing"})
      roi = roi_fixture(video)

      assert Rois.roi_locked?(roi)
    end

    test "false quando o único vídeo usando a ROI está com erro" do
      exp = experiment_fixture(user_fixture())
      video = video_fixture(exp, nil, %{status: "error"})
      roi = roi_fixture(video)

      refute Rois.roi_locked?(roi)
    end
  end

  describe "duplicate_roi/2" do
    test "clona a geometria da ROI numa nova ROI não anexada a nenhum vídeo" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      exp = experiment_fixture(user)
      video = video_fixture(exp)
      roi = roi_fixture(video, %{name: "Centro", shape: "rectangle", x: 1, y: 2, w: 3, h: 4})

      assert {:ok, copy} = Rois.duplicate_roi(scope, roi)
      assert copy.id != roi.id
      assert copy.name == "Centro (copy)"
      assert copy.shape == "rectangle"
      assert copy.x == 1
      assert copy.y == 2
      assert copy.w == 3
      assert copy.h == 4
      assert Rois.list_rois_for_video(video) |> Enum.map(& &1.id) == [roi.id]
    end

    test "preserva os campos de um polígono" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      exp = experiment_fixture(user)
      video = video_fixture(exp)

      roi =
        roi_fixture(video, %{
          name: "Zona poligonal",
          shape: "polygon",
          x: 0,
          y: 0,
          x1: 0,
          y1: 0,
          x2: 10,
          y2: 0,
          x3: 10,
          y3: 10,
          x4: 0,
          y4: 10
        })

      assert {:ok, copy} = Rois.duplicate_roi(scope, roi)
      assert copy.shape == "polygon"

      assert {copy.x1, copy.y1, copy.x2, copy.y2, copy.x3, copy.y3, copy.x4, copy.y4} ==
               {0, 0, 10, 0, 10, 10, 0, 10}
    end

    test "usa nome incremental se \"(copy)\" já existir" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      exp = experiment_fixture(user)
      video = video_fixture(exp)
      roi = roi_fixture(video, %{name: "Centro"})

      assert {:ok, first_copy} = Rois.duplicate_roi(scope, roi)
      assert first_copy.name == "Centro (copy)"

      assert {:ok, second_copy} = Rois.duplicate_roi(scope, roi)
      assert second_copy.name == "Centro (copy 2)"
    end
  end

  describe "count_videos_using_roi/1" do
    test "0 quando a ROI não está anexada a nenhum vídeo" do
      exp = experiment_fixture(user_fixture())
      video = video_fixture(exp)
      roi = roi_fixture(video)
      Rois.detach_roi_from_video(video, roi)

      assert Rois.count_videos_using_roi(roi) == 0
    end

    test "conta vídeos anexados, mesmo com status pending (diferente de roi_locked?/1)" do
      exp = experiment_fixture(user_fixture())
      video = video_fixture(exp, nil, %{status: "pending"})
      roi = roi_fixture(video)

      assert Rois.count_videos_using_roi(roi) == 1
      refute Rois.roi_locked?(roi)
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

      assert Rois.list_roi_times(roi1) == [rt]
    end
  end

  describe "get_roi_time!/1" do
    test "retorna o roi_time pelo id" do
      exp = experiment_fixture(user_fixture())
      video = video_fixture(exp)
      roi = roi_fixture(video)
      result = tracking_result_fixture(video)
      rt = roi_time_fixture(roi, result)

      assert Rois.get_roi_time!(rt.id) == rt
    end

    test "levanta erro para id inexistente" do
      assert_raise Ecto.NoResultsError, fn ->
        Rois.get_roi_time!(0)
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
               Rois.create_roi_time(roi, result, %{frame_count: 90, seconds: 3.0})

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
               Rois.create_roi_time(roi, result, %{frame_count: 10, seconds: 0.5})

      assert "has already been taken" in errors_on(changeset).roi_id
    end
  end
end
