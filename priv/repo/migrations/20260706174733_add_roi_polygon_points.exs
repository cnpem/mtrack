defmodule MouseTracker.Repo.Migrations.AddRoiPolygonPoints do
  use Ecto.Migration

  def change do
    alter table(:rois) do
      add :x1, :integer
      add :y1, :integer
      add :x2, :integer
      add :y2, :integer
      add :x3, :integer
      add :y3, :integer
      add :x4, :integer
      add :y4, :integer
    end
  end
end
