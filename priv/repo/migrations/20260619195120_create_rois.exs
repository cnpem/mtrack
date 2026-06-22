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

    create index(:rois, [:video_id])
  end
end
