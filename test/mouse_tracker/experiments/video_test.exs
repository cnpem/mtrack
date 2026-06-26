defmodule MouseTracker.Experiments.VideoTest do
  use MouseTracker.DataCase, async: true

  import MouseTracker.AccountsFixtures
  import MouseTracker.ExperimentsFixtures

  alias MouseTracker.Experiments.Video

  @valid_attrs %{
    filename: "video.mp4",
    filepath: "/tmp/video.mp4"
  }

  describe "changeset/2" do
    setup do
      user = user_fixture()
      experiment = experiment_fixture(user)
      %{experiment: experiment}
    end

    test "válido com campos obrigatórios", %{experiment: experiment} do
      changeset = Video.changeset(%Video{experiment_id: experiment.id}, @valid_attrs)
      assert changeset.valid?
    end

    test "status padrão é pending", %{experiment: experiment} do
      changeset = Video.changeset(%Video{experiment_id: experiment.id}, @valid_attrs)
      assert get_field(changeset, :status) == "pending"
    end

    test "inválido sem filename", %{experiment: experiment} do
      changeset =
        Video.changeset(%Video{experiment_id: experiment.id}, Map.delete(@valid_attrs, :filename))

      assert "can't be blank" in errors_on(changeset).filename
    end

    test "inválido sem filepath", %{experiment: experiment} do
      changeset =
        Video.changeset(%Video{experiment_id: experiment.id}, Map.delete(@valid_attrs, :filepath))

      assert "can't be blank" in errors_on(changeset).filepath
    end

    test "status válido é aceito", %{experiment: experiment} do
      for status <- ~w[pending processing done error] do
        changeset =
          Video.changeset(
            %Video{experiment_id: experiment.id},
            Map.put(@valid_attrs, :status, status)
          )

        assert changeset.valid?, "esperava válido para status=#{status}"
      end
    end

    test "status inválido é rejeitado", %{experiment: experiment} do
      changeset =
        Video.changeset(
          %Video{experiment_id: experiment.id},
          Map.put(@valid_attrs, :status, "unknown")
        )

      assert errors_on(changeset).status != []
    end

    test "filepath duplicado falha no banco", %{experiment: experiment} do
      video_fixture(experiment, nil, %{filepath: "/tmp/mesmo.mp4", filename: "mesmo.mp4"})

      assert {:error, changeset} =
               %Video{experiment_id: experiment.id}
               |> Video.changeset(%{filename: "outro.mp4", filepath: "/tmp/mesmo.mp4"})
               |> Repo.insert()

      assert "has already been taken" in errors_on(changeset).filepath
    end
  end
end
