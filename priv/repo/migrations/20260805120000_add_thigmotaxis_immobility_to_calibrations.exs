defmodule MouseTracker.Repo.Migrations.AddThigmotaxisImmobilityToCalibrations do
  use Ecto.Migration

  def change do
    alter table(:calibrations) do
      add :peripheral_pct, :float, null: false, default: 20.0
      add :immobility_threshold_cm, :float, null: false, default: 2.0
    end
  end
end
