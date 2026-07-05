defmodule MouseTracker.Repo.Migrations.AddSpeedProfilePathToTrackingResults do
  use Ecto.Migration

  def change do
    alter table(:tracking_results) do
      add :speed_profile_path, :string
    end
  end
end
