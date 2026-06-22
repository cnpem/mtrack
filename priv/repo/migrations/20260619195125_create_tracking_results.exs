defmodule MouseTracker.Repo.Migrations.CreateTrackingResults do
  use Ecto.Migration

  def change do
    create table(:tracking_results) do
      add :distance_px, :float, null: false
      add :distance_cm, :float, null: false
      add :speed_mean_px, :float, null: false
      add :speed_mean_cm, :float, null: false
      add :speed_median_px, :float, null: false
      add :speed_median_cm, :float, null: false
      add :heatmap_path, :string
      add :processed_at, :utc_datetime, null: false
      add :video_id, references(:videos, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:tracking_results, [:video_id])
  end
end
