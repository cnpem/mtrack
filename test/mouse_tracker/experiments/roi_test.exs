defmodule MouseTracker.Experiments.RoiTest do
  use MouseTracker.DataCase, async: true

  import MouseTracker.AccountsFixtures
  import MouseTracker.ExperimentsFixtures

  alias MouseTracker.Experiments.Roi

  describe "changeset/2" do
    setup do
      user = user_fixture()
      experiment = experiment_fixture(user)
      video = video_fixture(experiment)
      %{video: video}
    end

    test "válido com shape rectangle", %{video: video} do
      changeset =
        Roi.changeset(%Roi{video_id: video.id}, %{
          name: "ROI A",
          shape: "rectangle",
          x: 10,
          y: 10,
          w: 100,
          h: 100
        })

      assert changeset.valid?
    end

    test "válido com shape circle", %{video: video} do
      changeset =
        Roi.changeset(%Roi{video_id: video.id}, %{
          name: "ROI B",
          shape: "circle",
          x: 50,
          y: 50,
          radius: 30
        })

      assert changeset.valid?
    end

    test "rectangle sem w falha", %{video: video} do
      changeset =
        Roi.changeset(%Roi{video_id: video.id}, %{
          name: "ROI",
          shape: "rectangle",
          x: 10,
          y: 10,
          h: 100
        })

      assert "can't be blank" in errors_on(changeset).w
    end

    test "rectangle sem h falha", %{video: video} do
      changeset =
        Roi.changeset(%Roi{video_id: video.id}, %{
          name: "ROI",
          shape: "rectangle",
          x: 10,
          y: 10,
          w: 100
        })

      assert "can't be blank" in errors_on(changeset).h
    end

    test "circle sem radius falha", %{video: video} do
      changeset =
        Roi.changeset(%Roi{video_id: video.id}, %{
          name: "ROI",
          shape: "circle",
          x: 50,
          y: 50
        })

      assert "can't be blank" in errors_on(changeset).radius
    end

    test "w <= 0 é inválido", %{video: video} do
      changeset =
        Roi.changeset(%Roi{video_id: video.id}, %{
          name: "ROI",
          shape: "rectangle",
          x: 10,
          y: 10,
          w: 0,
          h: 100
        })

      assert errors_on(changeset).w != []
    end

    test "h <= 0 é inválido", %{video: video} do
      changeset =
        Roi.changeset(%Roi{video_id: video.id}, %{
          name: "ROI",
          shape: "rectangle",
          x: 10,
          y: 10,
          w: 100,
          h: -1
        })

      assert errors_on(changeset).h != []
    end

    test "radius <= 0 é inválido", %{video: video} do
      changeset =
        Roi.changeset(%Roi{video_id: video.id}, %{
          name: "ROI",
          shape: "circle",
          x: 50,
          y: 50,
          radius: 0
        })

      assert errors_on(changeset).radius != []
    end

    test "shape inválido é rejeitado", %{video: video} do
      changeset =
        Roi.changeset(%Roi{video_id: video.id}, %{
          name: "ROI",
          shape: "triangle",
          x: 10,
          y: 10
        })

      assert errors_on(changeset).shape != []
    end

    test "nome duplicado no mesmo vídeo falha no banco", %{video: video} do
      roi_fixture(video, %{name: "ROI Único"})

      assert {:error, changeset} =
               %Roi{video_id: video.id}
               |> Roi.changeset(%{name: "ROI Único", shape: "rectangle", x: 0, y: 0, w: 10, h: 10})
               |> Repo.insert()

      assert "has already been taken" in errors_on(changeset).name
    end

    test "mesmo nome em vídeos diferentes é permitido" do
      user = user_fixture()
      experiment = experiment_fixture(user)
      video1 = video_fixture(experiment)
      video2 = video_fixture(experiment)
      roi_fixture(video1, %{name: "ROI Compartilhado"})

      assert {:ok, _} =
               %Roi{video_id: video2.id}
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
