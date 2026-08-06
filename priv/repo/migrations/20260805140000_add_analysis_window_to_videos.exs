defmodule MouseTracker.Repo.Migrations.AddAnalysisWindowToVideos do
  use Ecto.Migration

  def change do
    alter table(:videos) do
      # Analysis window (in seconds). start defaults to 0 (beginning); end is
      # nullable — nil/0 means "to the end of the video", matching what the
      # Python headless mode already expects for `end_time`.
      add :start_time_seconds, :float, default: 0.0, null: false
      add :end_time_seconds, :float
    end
  end
end
