defmodule MouseTracker.Experiments.Rois do
  @moduledoc """
  A ROI is a user-owned, reusable geometry (like Calibration). It is attached
  to N videos via the `videos_rois` join table. Measured per-video data lives
  in `roi_times`/`tracking_results`, so sharing a ROI never shares acquired data.
  """

  import Ecto.Query
  import MouseTracker.Experiments.Ownership

  alias MouseTracker.Repo
  alias MouseTracker.Accounts.Scope
  alias MouseTracker.Experiments.{Roi, RoiTime, TrackingResult, Video}

  def list_rois(%Scope{user: user}) do
    Repo.all(from r in Roi, where: r.user_id == ^user.id, order_by: r.name)
  end

  def get_roi!(%Scope{user: user}, id) do
    Repo.get_by!(Roi, id: id, user_id: user.id)
  end

  def create_roi(%Scope{user: user}, attrs) do
    %Roi{user_id: user.id}
    |> Roi.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Clones `roi`'s geometry into a brand-new ROI owned by `scope`'s user,
  appending " (copy)" (then " (copy 2)", etc.) to the name to satisfy the
  `[:user_id, :name]` uniqueness constraint. The duplicate starts unattached
  to any video, so it's always freely editable — used as the escape hatch
  when the source ROI is `roi_locked?/1`.
  """
  def duplicate_roi(%Scope{user: user} = scope, %Roi{user_id: owner_id} = roi)
      when is_owner(owner_id, user.id) do
    attrs =
      roi
      |> Map.take([:shape, :x, :y, :w, :h, :radius, :x1, :y1, :x2, :y2, :x3, :y3, :x4, :y4])
      |> Map.put(:name, unique_copy_name(scope, roi.name))

    create_roi(scope, attrs)
  end

  defp unique_copy_name(scope, base_name) do
    existing = scope |> list_rois() |> MapSet.new(& &1.name)
    do_unique_copy_name(existing, base_name, 1)
  end

  defp do_unique_copy_name(existing, base_name, n) do
    candidate = if n == 1, do: "#{base_name} (copy)", else: "#{base_name} (copy #{n})"

    if MapSet.member?(existing, candidate),
      do: do_unique_copy_name(existing, base_name, n + 1),
      else: candidate
  end

  def update_roi(%Scope{user: user}, %Roi{user_id: owner_id} = roi, attrs)
      when is_owner(owner_id, user.id) do
    roi
    |> Roi.changeset(attrs)
    |> Repo.update()
  end

  def delete_roi(%Scope{user: user}, %Roi{user_id: owner_id} = roi)
      when is_owner(owner_id, user.id) do
    Repo.delete(roi)
  end

  def change_roi(%Roi{} = roi, attrs \\ %{}) do
    Roi.changeset(roi, attrs)
  end

  @doc "ROIs currently attached to the given video."
  def list_rois_for_video(%Video{} = video) do
    Repo.preload(video, :rois).rois
  end

  @doc """
  True if `roi` is attached to at least one video whose status is `"done"` or
  `"processing"`. Editing geometry in place at that point would change what
  those videos' (already-produced or in-flight) results are based on, so
  callers should block geometry edits and offer `duplicate_roi/2` instead.
  The `name` field has no such hazard and stays editable regardless.
  """
  def roi_locked?(%Roi{} = roi) do
    Repo.exists?(
      from vr in "videos_rois",
        join: v in Video,
        on: v.id == vr.video_id,
        where: vr.roi_id == ^roi.id and v.status in ["done", "processing"]
    )
  end

  @doc """
  Number of videos this ROI is attached to, regardless of status. Unlike
  `roi_locked?/1` (which only cares about done/processing videos, to freeze
  geometry edits), this is used to guard outright deletion — deleting a ROI
  still attached to a pending video would silently drop that video's setup.
  """
  def count_videos_using_roi(%Roi{} = roi) do
    Repo.aggregate(
      from(vr in "videos_rois", where: vr.roi_id == ^roi.id),
      :count
    )
  end

  @doc """
  Attaches an existing ROI to a video (idempotent — a duplicate link is ignored).
  """
  def attach_roi_to_video(%Video{} = video, %Roi{} = roi) do
    Repo.insert_all(
      "videos_rois",
      [%{video_id: video.id, roi_id: roi.id}],
      on_conflict: :nothing
    )

    :ok
  end

  @doc "Removes the link between a video and a ROI (leaves the ROI itself intact)."
  def detach_roi_from_video(%Video{} = video, %Roi{} = roi) do
    from(vr in "videos_rois", where: vr.video_id == ^video.id and vr.roi_id == ^roi.id)
    |> Repo.delete_all()

    :ok
  end

  # --- RoiTimes ---

  def list_roi_times(%Roi{} = roi) do
    Repo.all(from rt in RoiTime, where: rt.roi_id == ^roi.id)
  end

  def get_roi_time!(id), do: Repo.get!(RoiTime, id)

  def create_roi_time(%Roi{} = roi, %TrackingResult{} = result, attrs) do
    %RoiTime{roi_id: roi.id, tracking_result_id: result.id}
    |> RoiTime.changeset(attrs)
    |> Repo.insert()
  end

  def change_roi_time(%RoiTime{} = roi_time, attrs \\ %{}) do
    RoiTime.changeset(roi_time, attrs)
  end
end
