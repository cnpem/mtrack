defmodule MouseTracker.Repo.Migrations.CreateRoiTimes do
  use Ecto.Migration

  def change do
    create table(:roi_times) do
      add :roi_id, references(:rois, on_delete: :delete_all), null: false
      add :tracking_result_id, references(:tracking_results, on_delete: :delete_all), null: false
      add :frame_count, :integer, null: false
      add :seconds, :float, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:roi_times, [:roi_id])
    create index(:roi_times, [:tracking_result_id])
    # Add a unique constraint to ensure a ROI has at most one time entry per tracking result
    create unique_index(:roi_times, [:roi_id, :tracking_result_id])
  end
end
