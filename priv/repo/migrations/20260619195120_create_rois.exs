defmodule MouseTracker.Repo.Migrations.CreateRois do
  use Ecto.Migration

  def change do
    create table(:rois) do
      add :name, :string, null: false
      add :shape, :string, null: false, default: "rectangle"
      add :x, :integer, null: false
      add :y, :integer, null: false
      add :w, :integer
      add :h, :integer
      add :radius, :integer
      add :video_id, references(:videos, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create constraint(:rois, :positive_w, check: "w IS NULL OR w > 0")
    create constraint(:rois, :positive_h, check: "h IS NULL OR h > 0")
    create constraint(:rois, :positive_radius, check: "radius IS NULL OR radius > 0")

    create index(:rois, [:video_id])
    create unique_index(:rois, [:video_id, :name])
  end
end
