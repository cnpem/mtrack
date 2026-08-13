defmodule MouseTracker.Repo.Migrations.AddThigmotaxisImmobilityDefaultsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :default_peripheral_pct, :float
      add :default_immobility_threshold_cm, :float
    end
  end
end
