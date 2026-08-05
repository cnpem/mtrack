defmodule MouseTracker.Experiments.ReportingTest do
  use MouseTracker.DataCase, async: true

  import Ecto.Query
  import MouseTracker.AccountsFixtures
  import MouseTracker.ExperimentsFixtures

  alias MouseTracker.Experiments.{Reporting, Rois, Video}

  defp set_inserted_at(video, %DateTime{} = dt) do
    Repo.update_all(from(v in Video, where: v.id == ^video.id), set: [inserted_at: dt])
  end

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

  describe "group_result_videos/3" do
    test "retorna apenas vídeos done cujo subject pertence ao group informado" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      cal = calibration_fixture(user)

      s1 = subject_fixture(user, %{name: "M-01", group: "Control"})
      s2 = subject_fixture(user, %{name: "M-02", group: "Control"})
      s3 = subject_fixture(user, %{name: "M-03", group: "Treated"})

      exp1 = experiment_fixture(user)
      exp2 = experiment_fixture(user)

      v1 = video_fixture(exp1, cal, %{status: "done", subject_id: s1.id})
      v2 = video_fixture(exp2, cal, %{status: "done", subject_id: s2.id})
      _pending = video_fixture(exp1, cal, %{status: "pending", subject_id: s1.id})
      _other_group = video_fixture(exp1, cal, %{status: "done", subject_id: s3.id})

      tracking_result_fixture(v1)
      tracking_result_fixture(v2)

      videos = Reporting.group_result_videos(scope, "Control")

      assert Enum.map(videos, & &1.id) |> Enum.sort() == Enum.sort([v1.id, v2.id])
      assert Enum.all?(videos, & &1.tracking_result)
      assert Enum.all?(videos, & &1.subject)
    end

    test "filtra por experiment_id quando informado" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      cal = calibration_fixture(user)
      subject = subject_fixture(user, %{group: "Control"})

      exp1 = experiment_fixture(user)
      exp2 = experiment_fixture(user)

      v1 = video_fixture(exp1, cal, %{status: "done", subject_id: subject.id})
      _v2 = video_fixture(exp2, cal, %{status: "done", subject_id: subject.id})

      videos = Reporting.group_result_videos(scope, "Control", exp1.id)

      assert Enum.map(videos, & &1.id) == [v1.id]
    end

    test "vazio para um group desconhecido" do
      scope = user_scope_fixture(user_fixture())
      assert Reporting.group_result_videos(scope, "Nonexistent") == []
    end
  end

  describe "group_experiments/2" do
    test "retorna experimentos distintos (com vídeo done no group) ordenados por nome" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      cal = calibration_fixture(user)
      s1 = subject_fixture(user, %{group: "Control"})
      s2 = subject_fixture(user, %{group: "Control"})

      exp_b = experiment_fixture(user, %{name: "B experimento"})
      exp_a = experiment_fixture(user, %{name: "A experimento"})

      video_fixture(exp_b, cal, %{status: "done", subject_id: s1.id})
      video_fixture(exp_a, cal, %{status: "done", subject_id: s2.id})

      assert Enum.map(Reporting.group_experiments(scope, "Control"), & &1.id) ==
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

  describe "subject_groups/1" do
    test "agrupa por subject (nil por último), com aggregate sobre os vídeos done do grupo" do
      user = user_fixture()
      exp = experiment_fixture(user)
      subject = subject_fixture(user, %{name: "M-01"})

      v1 = video_fixture(exp, nil, %{status: "done", subject_id: subject.id})
      v2_pending = video_fixture(exp, nil, %{status: "pending", subject_id: subject.id})
      v3_no_subject = video_fixture(exp, nil, %{status: "done"})

      tracking_result_fixture(v1, %{distance_cm: 42.0})

      videos =
        Repo.preload([v1, v2_pending, v3_no_subject], [
          :subject,
          tracking_result: [roi_times: :roi]
        ])

      assert [%{subject: %{id: sid}, aggregate: aggregate}, %{subject: nil}] =
               Reporting.subject_groups(videos)

      assert sid == subject.id
      # só o vídeo "done" do grupo entra no aggregate (o pending fica de fora)
      assert aggregate.n == 1
      assert aggregate.metrics.distance_cm.mean == 42.0
    end
  end

  describe "groups_summary/1" do
    test "agrupa por subject.group (nil/vazio por último), com aggregate sobre os vídeos done" do
      user = user_fixture()
      exp = experiment_fixture(user)
      control = subject_fixture(user, %{name: "M-01", group: "Control"})
      no_group_subject = subject_fixture(user, %{name: "M-02", group: ""})

      v1 = video_fixture(exp, nil, %{status: "done", subject_id: control.id})
      v2_pending = video_fixture(exp, nil, %{status: "pending", subject_id: control.id})
      v3_no_group = video_fixture(exp, nil, %{status: "done", subject_id: no_group_subject.id})
      v4_no_subject = video_fixture(exp, nil, %{status: "done"})

      tracking_result_fixture(v1, %{distance_cm: 42.0})

      videos =
        Repo.preload([v1, v2_pending, v3_no_group, v4_no_subject], [
          :subject,
          tracking_result: [roi_times: :roi]
        ])

      assert [
               %{group: "Control", aggregate: aggregate} = control_group,
               %{group: nil} = nil_group
             ] =
               Reporting.groups_summary(videos)

      assert Enum.map(control_group.videos, & &1.id) |> Enum.sort() ==
               Enum.sort([v1.id, v2_pending.id])

      # só o vídeo "done" entra no aggregate do grupo
      assert aggregate.n == 1
      assert aggregate.metrics.distance_cm.mean == 42.0

      # vídeos sem group (string vazia normalizada) e sem subject caem no
      # mesmo bucket nil
      assert Enum.map(nil_group.videos, & &1.id) |> Enum.sort() ==
               Enum.sort([v3_no_group.id, v4_no_subject.id])
    end
  end

  # ---------------------------------------------------------------------------
  # Per-video helpers (Results screen)
  # ---------------------------------------------------------------------------

  describe "total_roi_seconds/1" do
    test "soma os segundos de todas as zonas" do
      exp = experiment_fixture(user_fixture())
      video = video_fixture(exp)
      roi1 = roi_fixture(video)
      roi2 = roi_fixture(video)
      result = tracking_result_fixture(video)
      roi_time_fixture(roi1, result, %{seconds: 20.0})
      roi_time_fixture(roi2, result, %{seconds: 15.0})

      result = Repo.preload(result, :roi_times)

      assert Reporting.total_roi_seconds(result) == 35.0
    end

    test "0.0 quando não há roi_times ou o shape é inesperado" do
      assert Reporting.total_roi_seconds(%{roi_times: []}) == 0.0
      assert Reporting.total_roi_seconds(nil) == 0.0
    end
  end

  describe "share_of_session/2" do
    test "calcula a porcentagem, limitada a 100%" do
      assert Reporting.share_of_session(20.0, 100.0) == 20.0
      assert Reporting.share_of_session(150.0, 100.0) == 100.0
    end

    test "nil quando a duração é ausente ou zero" do
      assert Reporting.share_of_session(20.0, nil) == nil
      assert Reporting.share_of_session(20.0, 0) == nil
      assert Reporting.share_of_session(20.0, 0.0) == nil
    end
  end

  describe "metric_series/2" do
    test "ordena do mais antigo para o mais novo e ignora vídeos sem tracking_result" do
      user = user_fixture()
      exp = experiment_fixture(user)

      v_new = video_fixture(exp, nil, %{status: "done"})
      v_old = video_fixture(exp, nil, %{status: "done"})
      v_no_result = video_fixture(exp, nil, %{status: "done"})

      tracking_result_fixture(v_new, %{distance_cm: 200.0})
      tracking_result_fixture(v_old, %{distance_cm: 100.0})

      videos =
        [v_new, v_old, v_no_result]
        |> Repo.preload([:experiment, tracking_result: [roi_times: :roi]])

      # simula o contrato de `subject_result_videos/3` (mais novo primeiro)
      series = Reporting.metric_series(videos, "distance_cm")

      assert Enum.map(series, & &1.value) == [100.0, 200.0]
    end

    test "ignora pontos cujo valor da métrica selecionada é nil" do
      user = user_fixture()
      exp = experiment_fixture(user)
      video = video_fixture(exp, nil, %{status: "done"})
      tracking_result_fixture(video, %{path_tortuosity: nil})

      videos = Repo.preload([video], [:experiment, tracking_result: [roi_times: :roi]])

      assert Reporting.metric_series(videos, "path_tortuosity") == []
    end
  end

  describe "group_metric_series/4" do
    test "faz a média por índice de sessão entre os subjects do group" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      exp = experiment_fixture(user)
      s1 = subject_fixture(user, %{group: "Control"})
      s2 = subject_fixture(user, %{group: "Control"})

      s1v1 = video_fixture(exp, nil, %{status: "done", subject_id: s1.id})
      s1v2 = video_fixture(exp, nil, %{status: "done", subject_id: s1.id})
      s2v1 = video_fixture(exp, nil, %{status: "done", subject_id: s2.id})
      s2v2 = video_fixture(exp, nil, %{status: "done", subject_id: s2.id})

      set_inserted_at(s1v1, ~U[2026-01-01 00:00:00Z])
      set_inserted_at(s1v2, ~U[2026-01-02 00:00:00Z])
      set_inserted_at(s2v1, ~U[2026-01-01 00:00:00Z])
      set_inserted_at(s2v2, ~U[2026-01-02 00:00:00Z])

      tracking_result_fixture(s1v1, %{distance_cm: 10.0})
      tracking_result_fixture(s1v2, %{distance_cm: 30.0})
      tracking_result_fixture(s2v1, %{distance_cm: 20.0})
      tracking_result_fixture(s2v2, %{distance_cm: 50.0})

      series = Reporting.group_metric_series(scope, "Control", "distance_cm")

      assert [
               %{index: 0, value: 15.0, n: 2, sd: sd0},
               %{index: 1, value: 40.0, n: 2, sd: sd1}
             ] = series

      assert sd0 != nil
      assert sd1 != nil
    end

    test "para de contribuir quando um subject acaba as sessões (sem preencher/repetir)" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      exp = experiment_fixture(user)
      s1 = subject_fixture(user, %{group: "Control"})
      s2 = subject_fixture(user, %{group: "Control"})

      s1v1 = video_fixture(exp, nil, %{status: "done", subject_id: s1.id})
      s2v1 = video_fixture(exp, nil, %{status: "done", subject_id: s2.id})
      s2v2 = video_fixture(exp, nil, %{status: "done", subject_id: s2.id})

      set_inserted_at(s1v1, ~U[2026-01-01 00:00:00Z])
      set_inserted_at(s2v1, ~U[2026-01-01 00:00:00Z])
      set_inserted_at(s2v2, ~U[2026-01-02 00:00:00Z])

      tracking_result_fixture(s1v1, %{distance_cm: 10.0})
      tracking_result_fixture(s2v1, %{distance_cm: 20.0})
      tracking_result_fixture(s2v2, %{distance_cm: 40.0})

      series = Reporting.group_metric_series(scope, "Control", "distance_cm")

      assert [%{index: 0, value: 15.0, n: 2, sd: _}, %{index: 1, value: 40.0, n: 1, sd: nil}] =
               series
    end

    test "vazio quando o group não tem subjects ou sessões" do
      scope = user_scope_fixture(user_fixture())
      assert Reporting.group_metric_series(scope, "Nonexistent", "distance_cm") == []
    end

    test "respeita o filtro por experiment_id" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      subject = subject_fixture(user, %{group: "Control"})

      exp1 = experiment_fixture(user)
      exp2 = experiment_fixture(user)

      v1 = video_fixture(exp1, nil, %{status: "done", subject_id: subject.id})
      v2 = video_fixture(exp2, nil, %{status: "done", subject_id: subject.id})

      tracking_result_fixture(v1, %{distance_cm: 10.0})
      tracking_result_fixture(v2, %{distance_cm: 20.0})

      series = Reporting.group_metric_series(scope, "Control", "distance_cm", exp1.id)

      assert [%{value: 10.0, n: 1}] = series
    end
  end
end
