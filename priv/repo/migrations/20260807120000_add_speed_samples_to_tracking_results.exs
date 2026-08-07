defmodule MouseTracker.Repo.Migrations.AddSpeedSamplesToTrackingResults do
  use Ecto.Migration

  def change do
    # A downsampled per-frame speed array (cm/s) so the Analyses "Speed
    # distribution" boxplot can pool a subject's instantaneous speeds across
    # sessions. Nullable — older results predate it and simply don't appear in
    # that chart until re-processed.
    alter table(:tracking_results) do
      add :speed_samples, {:array, :float}
    end
  end
end
