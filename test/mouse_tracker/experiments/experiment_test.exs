defmodule MouseTracker.Experiments.ExperimentTest do
  use MouseTracker.DataCase, async: true

  import MouseTracker.AccountsFixtures
  import MouseTracker.ExperimentsFixtures

  alias MouseTracker.Experiments.Experiment

  describe "changeset/2" do
    setup do
      %{user: user_fixture()}
    end

    test "válido com campos obrigatórios", %{user: user} do
      changeset = Experiment.changeset(%Experiment{user_id: user.id}, %{name: "Exp A"})
      assert changeset.valid?
    end

    test "válido com descrição opcional", %{user: user} do
      changeset =
        Experiment.changeset(%Experiment{user_id: user.id}, %{
          name: "Exp A",
          description: "Descrição do experimento"
        })

      assert changeset.valid?
    end

    test "inválido sem name", %{user: user} do
      changeset = Experiment.changeset(%Experiment{user_id: user.id}, %{})
      assert "can't be blank" in errors_on(changeset).name
    end

    test "inválido com name vazio", %{user: user} do
      changeset = Experiment.changeset(%Experiment{user_id: user.id}, %{name: ""})
      assert "can't be blank" in errors_on(changeset).name
    end

    test "inválido com name acima de 255 caracteres", %{user: user} do
      long_name = String.duplicate("a", 256)
      changeset = Experiment.changeset(%Experiment{user_id: user.id}, %{name: long_name})
      assert "should be at most 255 character(s)" in errors_on(changeset).name
    end

    test "user_id não é aceito via cast", %{user: user} do
      other_user = user_fixture()

      changeset =
        Experiment.changeset(%Experiment{user_id: user.id}, %{
          name: "Exp A",
          user_id: other_user.id
        })

      refute changeset.changes[:user_id]
    end

    test "nome duplicado para o mesmo usuário falha no banco", %{user: user} do
      experiment_fixture(user, %{name: "Nome Único"})

      assert {:error, changeset} =
               %Experiment{user_id: user.id}
               |> Experiment.changeset(%{name: "Nome Único"})
               |> Repo.insert()

      assert "has already been taken" in errors_on(changeset).name
    end

    test "mesmo nome para usuários diferentes é permitido" do
      user1 = user_fixture()
      user2 = user_fixture()
      experiment_fixture(user1, %{name: "Nome Compartilhado"})

      assert {:ok, _} =
               %Experiment{user_id: user2.id}
               |> Experiment.changeset(%{name: "Nome Compartilhado"})
               |> Repo.insert()
    end
  end
end
