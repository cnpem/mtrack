defmodule MouseTracker.Repo.Migrations.CreateVideos do
  use Ecto.Migration

  def change do
    create table(:videos) do
      add :filename, :string, null: false
      add :filepath, :string, null: false
      add :format, :string
      add :fps, :integer
      add :duration_seconds, :float
      add :frame_count, :integer
      add :width, :integer
      add :height, :integer
      add :status, :string, null: false, default: "pending"
      add :experiment_id, references(:experiments, on_delete: :delete_all), null: false
      add :calibration_id, references(:calibrations, on_delete: :nilify_all), null: true

      timestamps(type: :utc_datetime)
    end

    create constraint(:videos, :valid_status,
      check: "status IN ('pending', 'processing', 'done', 'error')")

    create index(:videos, [:experiment_id])
    create index(:videos, [:calibration_id])
    create unique_index(:videos, [:filepath])
  end
end
