defmodule MouseTracker.Repo.Migrations.AddSecondScaleSegmentToCalibrations do
  use Ecto.Migration

  def change do
    alter table(:calibrations) do
      add :coordinate_x3, :integer
      add :coordinate_y3, :integer
      add :coordinate_x4, :integer
      add :coordinate_y4, :integer
      add :scale_cm_2, :float
    end
  end
end
