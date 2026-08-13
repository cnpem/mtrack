defmodule MouseTracker.Repo.Migrations.AddMetricsToTrackingResults do
  use Ecto.Migration

  def change do
    alter table(:tracking_results) do
      add :thigmotaxis_pct, :float
      add :immobility_seconds, :float
      add :path_tortuosity, :float
      add :speed_max_px, :float
      add :speed_max_cm, :float
    end
  end
end
