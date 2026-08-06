defmodule MouseTracker.Repo.Migrations.MakeRoiNamesDuplicable do
  use Ecto.Migration

  # ROI names used to be unique per user. Users asked for duplicates: when the
  # camera shifts slightly between recordings they redraw the "same" ROI a bit
  # off and want to reuse the name so it lands in the same exported column
  # (`tempo_<name>_s`). Drop the unique index, keep a plain index for lookups.
  def up do
    drop unique_index(:rois, [:user_id, :name])
    create index(:rois, [:user_id, :name])
  end

  def down do
    drop index(:rois, [:user_id, :name])
    create unique_index(:rois, [:user_id, :name])
  end
end
