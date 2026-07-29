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

    test "levanta erro se o experimento pertencer a outro usuário" do
      exp = experiment_fixture(user_fixture())
      other_scope = user_scope_fixture(user_fixture())

      assert_raise FunctionClauseError, fn ->
        Experiments.update_experiment(other_scope, exp, %{name: "Hackeado"})
      end
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

    test "levanta erro se o experimento pertencer a outro usuário" do
      exp = experiment_fixture(user_fixture())
      other_scope = user_scope_fixture(user_fixture())

      assert_raise FunctionClauseError, fn ->
        Experiments.delete_experiment(other_scope, exp)
      end
    end

    test "remove do disco o arquivo de vídeo e o diretório de resultados de cada vídeo" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      exp = experiment_fixture(user)

      filepath =
        Path.join(System.tmp_dir!(), "exp_test_#{System.unique_integer([:positive])}.mp4")

      File.write!(filepath, "x")
      video = video_fixture(exp, nil, %{filepath: filepath})

      results_dir = results_dir_for(video)
      File.mkdir_p!(results_dir)
      File.write!(Path.join(results_dir, "heatmap.png"), "x")

      assert {:ok, _} = Experiments.delete_experiment(scope, exp)

      refute File.exists?(filepath)
      refute File.exists?(results_dir)
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

    test "remove do disco o arquivo de vídeo e o diretório de resultados" do
      exp = experiment_fixture(user_fixture())

      filepath =
        Path.join(System.tmp_dir!(), "exp_test_#{System.unique_integer([:positive])}.mp4")

      File.write!(filepath, "x")
      video = video_fixture(exp, nil, %{filepath: filepath})

      results_dir = results_dir_for(video)
      File.mkdir_p!(results_dir)
      File.write!(Path.join(results_dir, "speed_profile.png"), "x")

      assert {:ok, _} = Experiments.delete_video(video)

      refute File.exists?(filepath)
      refute File.exists?(results_dir)
    end
  end

  describe "update_video/3" do
    test "atualiza o vídeo quando o experimento pertence ao usuário do scope" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      exp = experiment_fixture(user)
      video = exp |> video_fixture() |> then(&Experiments.get_video_with_experiment!(&1.id))

      assert {:ok, updated} = Experiments.update_video(scope, video, %{status: "done"})
      assert updated.status == "done"
    end

    test "levanta erro se o vídeo pertencer a experimento de outro usuário" do
      exp = experiment_fixture(user_fixture())
      video = exp |> video_fixture() |> then(&Experiments.get_video_with_experiment!(&1.id))
      other_scope = user_scope_fixture(user_fixture())

      assert_raise FunctionClauseError, fn ->
        Experiments.update_video(other_scope, video, %{status: "done"})
      end
    end
  end

  describe "delete_video/2" do
    test "remove o vídeo quando o experimento pertence ao usuário do scope" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      exp = experiment_fixture(user)
      video = exp |> video_fixture() |> then(&Experiments.get_video_with_experiment!(&1.id))

      assert {:ok, _} = Experiments.delete_video(scope, video)
      assert Experiments.list_videos(exp) == []
    end

    test "levanta erro se o vídeo pertencer a experimento de outro usuário" do
      exp = experiment_fixture(user_fixture())
      video = exp |> video_fixture() |> then(&Experiments.get_video_with_experiment!(&1.id))
      other_scope = user_scope_fixture(user_fixture())

      assert_raise FunctionClauseError, fn ->
        Experiments.delete_video(other_scope, video)
      end
    end
  end

  # Mirrors VideoProcessingWorker.output_path/2's directory formula
  # (lib/mouse_tracker/workers/video_processing_worker.ex), so tests can
  # verify Experiments.delete_experiment/2 and delete_video/1 clean it up.
  defp results_dir_for(video) do
    Path.join([
      :code.priv_dir(:mouse_tracker),
      "static",
      "uploads",
      "results",
      to_string(video.id)
    ])
  end
end
