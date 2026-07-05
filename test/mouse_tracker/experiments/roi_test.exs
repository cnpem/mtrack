defmodule MouseTracker.Experiments.RoiTest do
  use MouseTracker.DataCase, async: true

  import MouseTracker.AccountsFixtures

  alias MouseTracker.Experiments.Roi

  describe "changeset/2" do
    setup do
      %{user: user_fixture()}
    end

    test "válido com shape rectangle", %{user: user} do
      changeset =
        Roi.changeset(%Roi{user_id: user.id}, %{
          name: "ROI A",
          shape: "rectangle",
          x: 10,
          y: 10,
          w: 100,
          h: 100
        })

      assert changeset.valid?
    end

    test "válido com shape circle", %{user: user} do
      changeset =
        Roi.changeset(%Roi{user_id: user.id}, %{
          name: "ROI B",
          shape: "circle",
          x: 50,
          y: 50,
          radius: 30
        })

      assert changeset.valid?
    end

    test "rectangle sem w falha", %{user: user} do
      changeset =
        Roi.changeset(%Roi{user_id: user.id}, %{
          name: "ROI",
          shape: "rectangle",
          x: 10,
          y: 10,
          h: 100
        })

      assert "can't be blank" in errors_on(changeset).w
    end

    test "rectangle sem h falha", %{user: user} do
      changeset =
        Roi.changeset(%Roi{user_id: user.id}, %{
          name: "ROI",
          shape: "rectangle",
          x: 10,
          y: 10,
          w: 100
        })

      assert "can't be blank" in errors_on(changeset).h
    end

    test "circle sem radius falha", %{user: user} do
      changeset =
        Roi.changeset(%Roi{user_id: user.id}, %{
          name: "ROI",
          shape: "circle",
          x: 50,
          y: 50
        })

      assert "can't be blank" in errors_on(changeset).radius
    end

    test "w <= 0 é inválido", %{user: user} do
      changeset =
        Roi.changeset(%Roi{user_id: user.id}, %{
          name: "ROI",
          shape: "rectangle",
          x: 10,
          y: 10,
          w: 0,
          h: 100
        })

      assert errors_on(changeset).w != []
    end

    test "h <= 0 é inválido", %{user: user} do
      changeset =
        Roi.changeset(%Roi{user_id: user.id}, %{
          name: "ROI",
          shape: "rectangle",
          x: 10,
          y: 10,
          w: 100,
          h: -1
        })

      assert errors_on(changeset).h != []
    end

    test "radius <= 0 é inválido", %{user: user} do
      changeset =
        Roi.changeset(%Roi{user_id: user.id}, %{
          name: "ROI",
          shape: "circle",
          x: 50,
          y: 50,
          radius: 0
        })

      assert errors_on(changeset).radius != []
    end

    test "shape inválido é rejeitado", %{user: user} do
      changeset =
        Roi.changeset(%Roi{user_id: user.id}, %{
          name: "ROI",
          shape: "triangle",
          x: 10,
          y: 10
        })

      assert errors_on(changeset).shape != []
    end

    test "nome duplicado para o mesmo usuário falha no banco", %{user: user} do
      %Roi{user_id: user.id}
      |> Roi.changeset(%{name: "ROI Único", shape: "rectangle", x: 0, y: 0, w: 10, h: 10})
      |> Repo.insert!()

      assert {:error, changeset} =
               %Roi{user_id: user.id}
               |> Roi.changeset(%{
                 name: "ROI Único",
                 shape: "rectangle",
                 x: 0,
                 y: 0,
                 w: 10,
                 h: 10
               })
               |> Repo.insert()

      assert "has already been taken" in errors_on(changeset).name
    end

    test "mesmo nome para usuários diferentes é permitido" do
      user1 = user_fixture()
      user2 = user_fixture()

      %Roi{user_id: user1.id}
      |> Roi.changeset(%{name: "ROI Compartilhado", shape: "rectangle", x: 0, y: 0, w: 10, h: 10})
      |> Repo.insert!()

      assert {:ok, _} =
               %Roi{user_id: user2.id}
               |> Roi.changeset(%{
                 name: "ROI Compartilhado",
                 shape: "rectangle",
                 x: 0,
                 y: 0,
                 w: 10,
                 h: 10
               })
               |> Repo.insert()
    end
  end
end
