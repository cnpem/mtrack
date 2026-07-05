defmodule MouseTracker.Repo.Migrations.MakeRoisShareable do
  use Ecto.Migration

  @moduledoc """
  Turns a ROI from "belongs to one video" into a reusable, user-owned resource
  that can be attached to N videos (many-to-many via `videos_rois`), mirroring
  how `Calibration` is already shared across videos.

  The ROI row holds only the *geometry* (name/shape/coords); all measured
  per-video data (time-in-ROI, heatmaps) lives in `roi_times`/`tracking_results`
  keyed per video, so sharing the geometry never superimposes acquired data.
  """

  def up do
    create table(:videos_rois, primary_key: false) do
      add :video_id, references(:videos, on_delete: :delete_all), null: false
      add :roi_id, references(:rois, on_delete: :delete_all), null: false
    end

    create unique_index(:videos_rois, [:video_id, :roi_id])
    create index(:videos_rois, [:roi_id])

    # New owner column, nullable during backfill.
    alter table(:rois) do
      add :user_id, references(:users, on_delete: :delete_all)
    end

    flush()

    # Preserve existing links: every ROI currently belongs to exactly one video.
    execute """
    INSERT INTO videos_rois (video_id, roi_id)
    SELECT r.video_id, r.id FROM rois r
    """

    # Backfill ownership from video -> experiment -> user.
    execute """
    UPDATE rois r
    SET user_id = e.user_id
    FROM videos v
    JOIN experiments e ON e.id = v.experiment_id
    WHERE v.id = r.video_id
    """

    # Any orphan ROI whose owner could not be resolved would violate the
    # NOT NULL below; there should be none because rois.video_id was NOT NULL.
    # Set NOT NULL via raw SQL so we don't re-declare the FK (which `modify`
    # with a `references/2` type would, duplicating rois_user_id_fkey).
    execute "ALTER TABLE rois ALTER COLUMN user_id SET NOT NULL"

    drop unique_index(:rois, [:video_id, :name])
    drop index(:rois, [:video_id])

    alter table(:rois) do
      remove :video_id
    end

    create unique_index(:rois, [:user_id, :name])
  end

  def down do
    alter table(:rois) do
      add :video_id, references(:videos, on_delete: :delete_all)
    end

    flush()

    # Best-effort restore: pick one owning video per ROI (arbitrary if shared).
    execute """
    UPDATE rois r
    SET video_id = vr.video_id
    FROM (
      SELECT roi_id, MIN(video_id) AS video_id
      FROM videos_rois
      GROUP BY roi_id
    ) vr
    WHERE vr.roi_id = r.id
    """

    drop unique_index(:rois, [:user_id, :name])

    alter table(:rois) do
      remove :user_id
    end

    create index(:rois, [:video_id])
    create unique_index(:rois, [:video_id, :name])

    drop table(:videos_rois)
  end
end
