defmodule MouseTracker.Repo.Migrations.AddPipelineDefaultsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :default_threshold, :integer
      add :default_min_area, :integer
    end
  end
end
