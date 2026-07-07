defmodule MouseTracker.Experiments.SubjectTest do
  use MouseTracker.DataCase, async: true

  import MouseTracker.AccountsFixtures

  alias MouseTracker.Experiments.Subject

  describe "changeset/2" do
    setup do
      %{user: user_fixture()}
    end

    test "válido com nome apenas", %{user: user} do
      changeset = Subject.changeset(%Subject{user_id: user.id}, %{name: "M-01"})
      assert changeset.valid?
    end

    test "inválido sem nome", %{user: user} do
      changeset = Subject.changeset(%Subject{user_id: user.id}, %{})
      assert "can't be blank" in errors_on(changeset).name
    end

    test "sex fora de [M, F] é inválido", %{user: user} do
      changeset = Subject.changeset(%Subject{user_id: user.id}, %{name: "M-01", sex: "X"})
      assert errors_on(changeset).sex != []
    end

    test "age_days <= 0 é inválido", %{user: user} do
      changeset = Subject.changeset(%Subject{user_id: user.id}, %{name: "M-01", age_days: 0})
      assert errors_on(changeset).age_days != []
    end

    test "weight_g <= 0 é inválido", %{user: user} do
      changeset = Subject.changeset(%Subject{user_id: user.id}, %{name: "M-01", weight_g: 0.0})
      assert errors_on(changeset).weight_g != []
    end

    test "user_id não é aceito via cast", %{user: user} do
      other_user = user_fixture()

      changeset =
        Subject.changeset(
          %Subject{user_id: user.id},
          %{name: "M-01", user_id: other_user.id}
        )

      refute changeset.changes[:user_id]
    end

    test "nome duplicado para o mesmo usuário falha no banco", %{user: user} do
      %Subject{user_id: user.id}
      |> Subject.changeset(%{name: "M-01"})
      |> Repo.insert!()

      assert {:error, changeset} =
               %Subject{user_id: user.id}
               |> Subject.changeset(%{name: "M-01"})
               |> Repo.insert()

      assert "has already been taken" in errors_on(changeset).name
    end

    test "mesmo nome para usuários diferentes é permitido" do
      user1 = user_fixture()
      user2 = user_fixture()

      %Subject{user_id: user1.id}
      |> Subject.changeset(%{name: "M-01"})
      |> Repo.insert!()

      assert {:ok, _} =
               %Subject{user_id: user2.id}
               |> Subject.changeset(%{name: "M-01"})
               |> Repo.insert()
    end
  end
end
