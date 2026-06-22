defmodule MouseTracker.Experiments.TrackingResultTest do
  use MouseTracker.DataCase, async: true

  import MouseTracker.AccountsFixtures
  import MouseTracker.ExperimentsFixtures

  alias MouseTracker.Experiments.TrackingResult

  @valid_attrs %{
    distance_px: 1000.0,
    distance_cm: 33.3,
    speed_mean_px: 5.0,
    speed_mean_cm: 1.5,
    speed_median_px: 4.5,
    speed_median_cm: 1.4,
    processed_at: ~U[2026-01-01 12:00:00Z]
  }

  describe "changeset/2" do
    setup do
      user = user_fixture()
      experiment = experiment_fixture(user)
      video = video_fixture(experiment)
      %{video: video}
    end

    test "válido com todos os campos obrigatórios", %{video: video} do
      changeset = TrackingResult.changeset(%TrackingResult{video_id: video.id}, @valid_attrs)
      assert changeset.valid?
    end

    test "válido com heatmap_path opcional", %{video: video} do
      attrs = Map.put(@valid_attrs, :heatmap_path, "/tmp/heatmap.png")
      changeset = TrackingResult.changeset(%TrackingResult{video_id: video.id}, attrs)
      assert changeset.valid?
    end

    for field <- [:distance_px, :distance_cm, :speed_mean_px, :speed_mean_cm, :speed_median_px, :speed_median_cm] do
      test "inválido sem #{field}", %{video: video} do
        changeset =
          TrackingResult.changeset(
            %TrackingResult{video_id: video.id},
            Map.delete(@valid_attrs, unquote(field))
          )

        assert "can't be blank" in errors_on(changeset)[unquote(field)]
      end
    end

    test "segundo resultado para o mesmo vídeo falha no banco", %{video: video} do
      tracking_result_fixture(video)

      assert {:error, changeset} =
               %TrackingResult{video_id: video.id}
               |> TrackingResult.changeset(@valid_attrs)
               |> Repo.insert()

      assert "has already been taken" in errors_on(changeset).video_id
    end
  end
end
