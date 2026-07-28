defmodule MouseTracker.Experiments.ReportingTest do
  use MouseTracker.DataCase, async: true

  import MouseTracker.AccountsFixtures
  import MouseTracker.ExperimentsFixtures

  alias MouseTracker.Experiments.{Reporting, Rois}

  # ---------------------------------------------------------------------------
  # Subject results aggregation (Results "Por subject" tab)
  # ---------------------------------------------------------------------------

  describe "subject_result_videos/3" do
    test "retorna apenas vídeos done do subject, entre experimentos diferentes" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      subject = subject_fixture(user)
      other_subject = subject_fixture(user)
      cal = calibration_fixture(user)

      exp1 = experiment_fixture(user)
      exp2 = experiment_fixture(user)

      v1 = video_fixture(exp1, cal, %{status: "done", subject_id: subject.id})
      v2 = video_fixture(exp2, cal, %{status: "done", subject_id: subject.id})
      _pending = video_fixture(exp1, cal, %{status: "pending", subject_id: subject.id})
      _other = video_fixture(exp1, cal, %{status: "done", subject_id: other_subject.id})

      tracking_result_fixture(v1)
      tracking_result_fixture(v2)

      videos = Reporting.subject_result_videos(scope, subject.id)

      assert Enum.map(videos, & &1.id) |> Enum.sort() == Enum.sort([v1.id, v2.id])
      assert Enum.all?(videos, & &1.tracking_result)
      assert Enum.all?(videos, & &1.experiment)
    end

    test "filtra por experiment_id quando informado" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      subject = subject_fixture(user)
      cal = calibration_fixture(user)

      exp1 = experiment_fixture(user)
      exp2 = experiment_fixture(user)

      v1 = video_fixture(exp1, cal, %{status: "done", subject_id: subject.id})
      v2 = video_fixture(exp2, cal, %{status: "done", subject_id: subject.id})
      tracking_result_fixture(v1)
      tracking_result_fixture(v2)

      videos = Reporting.subject_result_videos(scope, subject.id, exp1.id)

      assert Enum.map(videos, & &1.id) == [v1.id]
    end

    test "levanta erro se o subject pertencer a outro usuário" do
      user = user_fixture()
      other = user_fixture()
      scope = user_scope_fixture(user)
      other_subject = subject_fixture(other)

      assert_raise Ecto.NoResultsError, fn ->
        Reporting.subject_result_videos(scope, other_subject.id)
      end
    end
  end

  describe "subject_experiments/2" do
    test "retorna experimentos distintos (com vídeo done) ordenados por nome" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      subject = subject_fixture(user)
      cal = calibration_fixture(user)

      exp_b = experiment_fixture(user, %{name: "B experimento"})
      exp_a = experiment_fixture(user, %{name: "A experimento"})

      video_fixture(exp_b, cal, %{status: "done", subject_id: subject.id})
      video_fixture(exp_a, cal, %{status: "done", subject_id: subject.id})
      video_fixture(exp_a, cal, %{status: "done", subject_id: subject.id})

      assert Enum.map(Reporting.subject_experiments(scope, subject.id), & &1.id) ==
               [exp_a.id, exp_b.id]
    end
  end

  describe "group_by_calibration/1" do
    test "agrupa vídeos pela mesma calibration; sem calibration fica por último" do
      user = user_fixture()
      exp = experiment_fixture(user)
      cal1 = calibration_fixture(user, %{name: "Campo A"})
      cal2 = calibration_fixture(user, %{name: "Campo B"})

      v1 = video_fixture(exp, cal1, %{status: "done"})
      v2 = video_fixture(exp, cal1, %{status: "done"})
      v3 = video_fixture(exp, cal2, %{status: "done"})
      v4 = video_fixture(exp, nil, %{status: "done"})

      videos = Repo.preload([v1, v2, v3, v4], :calibration)

      assert [{^cal1, group1}, {^cal2, group2}, {nil, group3}] =
               Reporting.group_by_calibration(videos)

      assert Enum.map(group1, & &1.id) |> Enum.sort() == Enum.sort([v1.id, v2.id])
      assert Enum.map(group2, & &1.id) == [v3.id]
      assert Enum.map(group3, & &1.id) == [v4.id]
    end
  end

  describe "subject_metric_aggregate/1" do
    test "calcula média e desvio padrão por métrica, ignorando vídeos sem tracking_result" do
      user = user_fixture()
      exp = experiment_fixture(user)
      cal = calibration_fixture(user)

      v1 = video_fixture(exp, cal, %{status: "done", duration_seconds: 100.0})
      v2 = video_fixture(exp, cal, %{status: "done", duration_seconds: 200.0})
      v3_no_result = video_fixture(exp, cal, %{status: "done", duration_seconds: 100.0})

      tracking_result_fixture(v1, %{distance_cm: 100.0, immobility_seconds: 10.0})
      tracking_result_fixture(v2, %{distance_cm: 200.0, immobility_seconds: 40.0})

      videos =
        Repo.preload([v1, v2, v3_no_result], tracking_result: [roi_times: :roi])

      aggregate = Reporting.subject_metric_aggregate(videos)

      assert aggregate.n == 2
      assert aggregate.metrics.distance_cm.mean == 150.0
      assert_in_delta aggregate.metrics.distance_cm.sd, 70.71, 0.01
      # imobilidade em segundos brutos: (10 + 40) / 2
      assert aggregate.metrics.immobility_seconds.mean == 25.0
    end

    test "agrega tempo em zona por roi_id, com share médio de sessão" do
      user = user_fixture()
      exp = experiment_fixture(user)
      cal = calibration_fixture(user)

      v1 = video_fixture(exp, cal, %{status: "done", duration_seconds: 100.0})
      v2 = video_fixture(exp, cal, %{status: "done", duration_seconds: 200.0})

      roi = roi_fixture(v1, %{name: "Centro"})
      :ok = Rois.attach_roi_to_video(v2, roi)

      r1 = tracking_result_fixture(v1)
      r2 = tracking_result_fixture(v2)
      roi_time_fixture(roi, r1, %{seconds: 20.0})
      roi_time_fixture(roi, r2, %{seconds: 60.0})

      videos = Repo.preload([v1, v2], tracking_result: [roi_times: :roi])

      assert [%{name: "Centro", avg_seconds: 40.0, avg_share_pct: 25.0, n: 2}] =
               Reporting.subject_metric_aggregate(videos).roi_zones
    end
  end

  # ---------------------------------------------------------------------------
  # Datasets library
  # ---------------------------------------------------------------------------

  describe "list_all_videos/1" do
    test "retorna os vídeos do usuário atravessando experimentos, mais novos primeiro" do
      user = user_fixture()
      other = user_fixture()
      scope = user_scope_fixture(user)

      exp_a = experiment_fixture(user)
      exp_b = experiment_fixture(user)
      other_exp = experiment_fixture(other)

      v1 = video_fixture(exp_a)
      v2 = video_fixture(exp_b)
      _other = video_fixture(other_exp)

      ids = Reporting.list_all_videos(scope) |> Enum.map(& &1.id)

      assert Enum.sort(ids) == Enum.sort([v1.id, v2.id])
      # newest-first: v2 was inserted after v1
      assert hd(ids) == v2.id
    end

    test "pré-carrega experiment, subject, calibration e tracking_result" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      cal = calibration_fixture(user)
      subject = subject_fixture(user)
      exp = experiment_fixture(user)
      video = video_fixture(exp, cal, %{status: "done", subject_id: subject.id})
      tracking_result_fixture(video)

      [loaded] = Reporting.list_all_videos(scope)

      assert loaded.experiment.id == exp.id
      assert loaded.subject.id == subject.id
      assert loaded.calibration.id == cal.id
      assert loaded.tracking_result.video_id == video.id
    end
  end

  describe "datasets_summary/1" do
    test "conta vídeos, soma duração/tamanho e conta os rastreados, ignorando nils" do
      user = user_fixture()
      exp = experiment_fixture(user)

      v1 =
        video_fixture(exp, nil, %{status: "done", duration_seconds: 100.0, file_size_bytes: 1000})

      v2 =
        video_fixture(exp, nil, %{status: "pending", duration_seconds: 50.0, file_size_bytes: 500})

      # sem duração/tamanho (vídeo antigo) — deve contar como 0 nas somas
      v3 = video_fixture(exp, nil, %{status: "processing"})

      summary = Reporting.datasets_summary([v1, v2, v3])

      assert summary.count == 3
      assert summary.recording_seconds == 150.0
      assert summary.storage_bytes == 1500
      assert summary.tracked == 1
    end

    test "zera as somas quando a lista está vazia" do
      assert Reporting.datasets_summary([]) == %{
               count: 0,
               recording_seconds: 0,
               tracked: 0,
               storage_bytes: 0
             }
    end
  end
end
