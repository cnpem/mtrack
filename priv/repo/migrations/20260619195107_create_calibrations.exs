defmodule MouseTracker.Repo.Migrations.CreateCalibrations do
  use Ecto.Migration

  def change do
    create table(:calibrations) do
      add :name, :string
      add :coordinate_x1, :integer
      add :coordinate_y1, :integer
      add :coordinate_x2, :integer
      add :coordinate_y2, :integer
      add :cage_side_cm, :float, null: false
      add :px_per_10cm, :float, null: false
      add :threshold, :integer, null: false, default: 80
      add :min_area, :integer, null: false, default: 250
      add :valid_region_x, :integer
      add :valid_region_y, :integer
      add :valid_region_w, :integer
      add :valid_region_h, :integer
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:calibrations, [:user_id])
  end
end
