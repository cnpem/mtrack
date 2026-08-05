defmodule MouseTracker.Experiments do
  @moduledoc """
  Experiment/Video CRUD and the upload wizard's orchestration. Per-resource
  concerns live in sibling modules: `MouseTracker.Experiments.Calibrations`,
  `.Rois`, `.Subjects` (CRUD + ownership for each reusable resource),
  `.Reporting` (cross-experiment aggregation) and `.FileCleanup` (disk cleanup
  on delete).
  """

  import Ecto.Query
  alias MouseTracker.Repo
  alias MouseTracker.Accounts.Scope

  import MouseTracker.Experiments.Ownership
  alias MouseTracker.Experiments.{Calibrations, Rois, Subjects, FileCleanup}

  alias MouseTracker.Experiments.{
    Experiment,
    Video,
    TrackingResult
  }

  # --- Experiments ---

  def list_experiments(%Scope{user: user}) do
    Repo.all(from e in Experiment, where: e.user_id == ^user.id, order_by: [desc: e.inserted_at])
  end

  def get_experiment!(%Scope{user: user}, id) do
    Repo.get_by!(Experiment, id: id, user_id: user.id)
  end

  @doc """
  Lists the user's experiments with `:videos` (and each video's `:subject`)
  preloaded, so the list/detail screens can derive an aggregate status and show
  subjects without an N+1. Ordered newest-first.
  """
  def list_experiments_with_details(%Scope{user: user}) do
    Repo.all(
      from e in Experiment,
        where: e.user_id == ^user.id,
        order_by: [desc: e.inserted_at],
        preload: [videos: [:subject]]
    )
  end

  @doc """
  Loads one experiment (scoped to the user) with its `:videos` (each video's
  `:subject` and `:tracking_result` preloaded) for the detail screen.
  """
  def get_experiment_with_details!(%Scope{user: user}, id) do
    Repo.one!(
      from e in Experiment,
        where: e.id == ^id and e.user_id == ^user.id,
        preload: [videos: [:subject, :tracking_result, :rois]]
    )
  end

  @doc """
  Loads one experiment (scoped to the user) for the results screen, preloading
  each video's `:subject` and its `:tracking_result` with `roi_times: :roi`, so
  the per-video metrics, heatmap/speed-profile paths and per-zone times can all
  be rendered without an N+1.
  """
  def get_experiment_for_results!(%Scope{user: user}, id) do
    Repo.one!(
      from e in Experiment,
        where: e.id == ^id and e.user_id == ^user.id,
        preload: [videos: [:subject, tracking_result: [roi_times: :roi]]]
    )
  end

  @doc """
  Subject is a reusable, user-owned resource (like Calibration/ROI) — it no
  longer belongs to a single experiment. "An experiment's subjects" means the
  distinct subjects its videos currently point at. Requires `:videos` (with
  `:subject`) preloaded on `experiment`.
  """
  def experiment_subjects(%Experiment{videos: videos}) when is_list(videos) do
    videos
    |> Enum.map(& &1.subject)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(& &1.name)
  end

  @doc """
  Derives a single status for an experiment from its (preloaded) videos:

    * `"error"` if any video errored,
    * `"processing"` if any video is still processing (or pending while others run),
    * `"done"` if there is at least one video and all are done,
    * `"pending"` otherwise (no videos yet, or all pending).
  """
  def experiment_status(%Experiment{videos: videos}) when is_list(videos) do
    statuses = Enum.map(videos, & &1.status)

    cond do
      "error" in statuses -> "error"
      "processing" in statuses -> "processing"
      statuses != [] and Enum.all?(statuses, &(&1 == "done")) -> "done"
      "done" in statuses -> "processing"
      true -> "pending"
    end
  end

  def create_experiment(%Scope{user: user}, attrs) do
    %Experiment{user_id: user.id}
    |> Experiment.changeset(attrs)
    |> Repo.insert()
  end

  def update_experiment(%Scope{user: user}, %Experiment{user_id: owner_id} = experiment, attrs)
      when is_owner(owner_id, user.id) do
    experiment
    |> Experiment.changeset(attrs)
    |> Repo.update()
  end

  def delete_experiment(%Scope{user: user}, %Experiment{user_id: owner_id} = experiment)
      when is_owner(owner_id, user.id) do
    experiment = Repo.preload(experiment, :videos)

    with {:ok, deleted} <- Repo.delete(experiment) do
      Enum.each(experiment.videos, &FileCleanup.cleanup_video_files/1)
      {:ok, deleted}
    end
  end

  def change_experiment(%Experiment{} = experiment, attrs \\ %{}) do
    Experiment.changeset(experiment, attrs)
  end

  @doc """
  Creates an experiment and all of its videos (with subjects, shared
  calibrations and shared ROIs) in a single transaction — the commit step of the
  upload wizard.

  `payload` is a plain map, already resolved by the wizard, of the form:

      %{
        name: "My experiment",
        # one entry per video that is a *reference* for that resource; keyed by
        # the upload entry ref that owns it:
        calibrations: %{ref => calibration_params_map},
        rois: %{ref => [roi_params_map, ...]},
        videos: [
          %{
            filename: "...", filepath: "/abs/path",
            subject_ref: {:existing, id} | {:new, "M-01", "control"} | {:new, "M-01", nil} | nil,
            cal_ref: ref,   # which calibration reference this video uses
            roi_ref: ref    # which ROI reference this video uses (nil => no ROIs)
          }
        ]
      }

  ROI names are unique per user, so each ROI is stored prefixed with the
  experiment name to avoid collisions across experiments. Returns
  `{:ok, {experiment, videos}}` or `{:error, changeset}` (rolls back on any
  insert failure, so no partial experiment is left behind).
  """
  def create_experiment_with_videos(%Scope{} = scope, payload) do
    Repo.transaction(fn ->
      experiment = insert_or_rollback(create_experiment(scope, %{name: payload.name}))
      new_subjects = create_wizard_subjects(scope, payload.videos)
      calibrations = create_wizard_calibrations(scope, payload.calibrations)
      rois = create_wizard_rois(scope, payload.name, payload.rois)
      videos = create_wizard_videos(experiment, payload.videos, new_subjects, calibrations, rois)

      {experiment, videos}
    end)
  end

  # Only `{:new, name, group}` entries need creating; `{:existing, id}` entries
  # already reference a real Subject row and require no insert. When the same
  # new name appears on multiple videos with conflicting groups, the last one
  # in `videos` order wins (same "last write wins" rule already implicit for
  # name-only duplicates before `group` existed).
  defp create_wizard_subjects(scope, videos) do
    videos
    |> Enum.map(& &1.subject_ref)
    |> Enum.filter(&match?({:new, _name, _group}, &1))
    |> Enum.reject(fn {:new, name, _group} -> name in [nil, ""] end)
    |> Map.new(fn {:new, name, group} -> {name, group} end)
    |> Map.new(fn {name, group} ->
      {name, insert_or_rollback(Subjects.create_subject(scope, %{name: name, group: group}))}
    end)
  end

  defp create_wizard_calibrations(scope, calibrations) do
    Map.new(calibrations, fn {ref, params} ->
      {ref, insert_or_rollback(Calibrations.create_calibration(scope, params))}
    end)
  end

  defp create_wizard_rois(scope, experiment_name, rois) do
    Map.new(rois, fn {ref, roi_params_list} ->
      created =
        Enum.map(roi_params_list, fn params ->
          prefixed = Map.put(params, "name", "#{experiment_name} · #{params["name"]}")
          insert_or_rollback(Rois.create_roi(scope, prefixed))
        end)

      {ref, created}
    end)
  end

  defp create_wizard_videos(experiment, videos, new_subjects, calibrations, rois) do
    Enum.map(videos, fn v ->
      cal = Map.get(calibrations, v.cal_ref)

      attrs = %{
        filename: v.filename,
        filepath: v.filepath,
        background_frame: Map.get(v, :background_frame, 0),
        file_size_bytes: Map.get(v, :file_size_bytes),
        fps: Map.get(v, :fps),
        duration_seconds: Map.get(v, :duration_seconds),
        frame_count: Map.get(v, :frame_count),
        width: Map.get(v, :width),
        height: Map.get(v, :height),
        calibration_id: cal && cal.id,
        subject_id: resolve_wizard_subject_id(v.subject_ref, new_subjects)
      }

      video = insert_or_rollback(create_video(experiment, attrs))

      for roi <- Map.get(rois, v.roi_ref, []), do: Rois.attach_roi_to_video(video, roi)
      video
    end)
  end

  defp resolve_wizard_subject_id({:existing, id}, _new_subjects), do: id

  defp resolve_wizard_subject_id({:new, name, _group}, _new_subjects) when name in [nil, ""],
    do: nil

  defp resolve_wizard_subject_id({:new, name, _group}, new_subjects),
    do: Map.fetch!(new_subjects, name).id

  defp resolve_wizard_subject_id(nil, _new_subjects), do: nil

  defp insert_or_rollback({:ok, record}), do: record
  defp insert_or_rollback({:error, changeset}), do: Repo.rollback(changeset)

  # --- Videos ---

  def list_videos(%Experiment{} = experiment) do
    Repo.all(from v in Video, where: v.experiment_id == ^experiment.id)
  end

  def get_video!(id), do: Repo.get!(Video, id)

  @doc "Loads a video with its `:experiment` and `:subject` preloaded."
  def get_video_with_experiment!(id) do
    Repo.get!(Video, id) |> Repo.preload([:experiment, :subject])
  end

  def create_video(%Experiment{} = experiment, attrs) do
    %Video{experiment_id: experiment.id}
    |> Video.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Unscoped — for system-level callers that are not acting on behalf of a
  specific end user (the `mouse_tracker.backfill_video_metadata` mix task,
  which sweeps videos across every user by design). LiveView code acting on
  behalf of a logged-in user should use `update_video/3` instead.
  """
  def update_video(%Video{} = video, attrs) do
    video
    |> Video.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Scoped variant of `update_video/2`, for LiveView callers acting on behalf of
  a logged-in user. `video` must have `:experiment` preloaded (see
  `get_video_with_experiment!/1`) so ownership can be checked without an extra
  query — a `Video` has no `user_id` of its own, only via its experiment.
  """
  def update_video(
        %Scope{user: user},
        %Video{experiment: %Experiment{user_id: owner_id}} = video,
        attrs
      )
      when is_owner(owner_id, user.id) do
    update_video(video, attrs)
  end

  @doc "Unscoped — see `update_video/2`."
  def delete_video(%Video{} = video) do
    with {:ok, deleted} <- Repo.delete(video) do
      FileCleanup.cleanup_video_files(video)
      {:ok, deleted}
    end
  end

  @doc "Scoped variant of `delete_video/1` — see `update_video/3`."
  def delete_video(%Scope{user: user}, %Video{experiment: %Experiment{user_id: owner_id}} = video)
      when is_owner(owner_id, user.id) do
    delete_video(video)
  end

  def change_video(%Video{} = video, attrs \\ %{}) do
    Video.changeset(video, attrs)
  end

  # --- Video Processing ---

  def enqueue_video_processing(video_id) do
    %{video_id: video_id}
    |> MouseTracker.Workers.VideoProcessingWorker.new()
    |> Oban.insert()
  end

  # --- Tracking Results ---

  def get_tracking_result_for_video(%Video{} = video) do
    Repo.get_by(TrackingResult, video_id: video.id)
  end

  def create_tracking_result(%Video{} = video, attrs) do
    %TrackingResult{video_id: video.id}
    |> TrackingResult.changeset(attrs)
    |> Repo.insert()
  end
end
