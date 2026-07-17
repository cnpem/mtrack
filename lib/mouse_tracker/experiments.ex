defmodule MouseTracker.Experiments do
  import Ecto.Query
  require Logger
  alias MouseTracker.Repo
  alias MouseTracker.Accounts.Scope

  alias MouseTracker.Experiments.{
    Experiment,
    Video,
    Calibration,
    Roi,
    RoiTime,
    TrackingResult,
    Subject
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

  def update_experiment(%Scope{}, %Experiment{} = experiment, attrs) do
    experiment
    |> Experiment.changeset(attrs)
    |> Repo.update()
  end

  def delete_experiment(%Scope{}, %Experiment{} = experiment) do
    experiment = Repo.preload(experiment, :videos)

    with {:ok, deleted} <- Repo.delete(experiment) do
      Enum.each(experiment.videos, &cleanup_video_files/1)
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
            subject_ref: {:existing, id} | {:new, "M-01"} | nil,
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

  # Only `{:new, name}` entries need creating; `{:existing, id}` entries
  # already reference a real Subject row and require no insert.
  defp create_wizard_subjects(scope, videos) do
    videos
    |> Enum.map(& &1.subject_ref)
    |> Enum.filter(&match?({:new, _name}, &1))
    |> Enum.map(fn {:new, name} -> name end)
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.uniq()
    |> Map.new(fn name ->
      {name, insert_or_rollback(create_subject(scope, %{name: name}))}
    end)
  end

  defp create_wizard_calibrations(scope, calibrations) do
    Map.new(calibrations, fn {ref, params} ->
      {ref, insert_or_rollback(create_calibration(scope, params))}
    end)
  end

  defp create_wizard_rois(scope, experiment_name, rois) do
    Map.new(rois, fn {ref, roi_params_list} ->
      created =
        Enum.map(roi_params_list, fn params ->
          prefixed = Map.put(params, "name", "#{experiment_name} · #{params["name"]}")
          insert_or_rollback(create_roi(scope, prefixed))
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

      for roi <- Map.get(rois, v.roi_ref, []), do: attach_roi_to_video(video, roi)
      video
    end)
  end

  defp resolve_wizard_subject_id({:existing, id}, _new_subjects), do: id
  defp resolve_wizard_subject_id({:new, name}, _new_subjects) when name in [nil, ""], do: nil

  defp resolve_wizard_subject_id({:new, name}, new_subjects),
    do: Map.fetch!(new_subjects, name).id

  defp resolve_wizard_subject_id(nil, _new_subjects), do: nil

  defp insert_or_rollback({:ok, record}), do: record
  defp insert_or_rollback({:error, changeset}), do: Repo.rollback(changeset)

  # --- Videos ---

  def list_videos(%Experiment{} = experiment) do
    Repo.all(from v in Video, where: v.experiment_id == ^experiment.id)
  end

  @doc """
  All of a user's videos across every experiment they own — the Datasets
  library. Newest-first, with `:experiment`, `:subject`, `:calibration` and
  `tracking_result: [roi_times: :roi]` preloaded so the library can show
  origin, subject, calibration status, a metrics preview and the "Por subject"
  aggregate (which reuses `subject_metric_aggregate/1`) without an N+1.
  """
  def list_all_videos(%Scope{user: user}) do
    Repo.all(
      from v in Video,
        join: e in assoc(v, :experiment),
        where: e.user_id == ^user.id,
        order_by: [desc: v.inserted_at, desc: v.id],
        preload: [:experiment, :subject, :calibration, tracking_result: [roi_times: :roi]]
    )
  end

  @doc """
  Aggregate figures for the Datasets header stat cards, computed in memory over
  a list of videos (as returned by `list_all_videos/1`):

    * `:count` — total videos,
    * `:recording_seconds` — summed `duration_seconds` (videos without it count 0),
    * `:tracked` — how many are `"done"`,
    * `:storage_bytes` — summed `file_size_bytes` (videos without it count 0).
  """
  def datasets_summary(videos) do
    %{
      count: length(videos),
      recording_seconds: sum_field(videos, & &1.duration_seconds),
      tracked: Enum.count(videos, &(&1.status == "done")),
      storage_bytes: sum_field(videos, & &1.file_size_bytes)
    }
  end

  defp sum_field(videos, fun) do
    videos
    |> Enum.map(fun)
    |> Enum.reject(&is_nil/1)
    |> Enum.sum()
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

  def update_video(%Video{} = video, attrs) do
    video
    |> Video.changeset(attrs)
    |> Repo.update()
  end

  def delete_video(%Video{} = video) do
    with {:ok, deleted} <- Repo.delete(video) do
      cleanup_video_files(video)
      {:ok, deleted}
    end
  end

  # The DB row is deleted first (source of truth); file removal below is
  # best-effort and non-fatal (logged, not raised) — orphaned files here are
  # a lesser problem than blocking the delete on a filesystem hiccup.
  defp cleanup_video_files(video) do
    remove_file(video.filepath)
    remove_dir(Path.join([static_dir(), "uploads", "results", to_string(video.id)]))
  end

  defp remove_file(nil), do: :ok

  defp remove_file(path) do
    case File.rm(path) do
      :ok ->
        :ok

      {:error, :enoent} ->
        :ok

      {:error, reason} ->
        Logger.warning("Experiments: failed to remove #{path}: #{inspect(reason)}")
    end
  end

  defp remove_dir(dir) do
    File.rm_rf!(dir)
  rescue
    error -> Logger.warning("Experiments: failed to remove #{dir}: #{inspect(error)}")
  end

  defp static_dir, do: Path.join(:code.priv_dir(:mouse_tracker), "static")

  def change_video(%Video{} = video, attrs \\ %{}) do
    Video.changeset(video, attrs)
  end

  # --- Calibrations ---

  def list_calibrations(%Scope{user: user}) do
    Repo.all(from c in Calibration, where: c.user_id == ^user.id)
  end

  def get_calibration!(%Scope{user: user}, id) do
    Repo.get_by!(Calibration, id: id, user_id: user.id)
  end

  def create_calibration(%Scope{user: user}, attrs) do
    %Calibration{user_id: user.id}
    |> Calibration.changeset(attrs)
    |> Repo.insert()
  end

  def update_calibration(%Calibration{} = calibration, attrs) do
    calibration
    |> Calibration.changeset(attrs)
    |> Repo.update()
  end

  def delete_calibration(%Calibration{} = calibration), do: Repo.delete(calibration)

  def change_calibration(%Calibration{} = calibration, attrs \\ %{}) do
    Calibration.changeset(calibration, attrs)
  end

  # --- ROIs ---
  #
  # A ROI is a user-owned, reusable geometry (like Calibration). It is attached
  # to N videos via the `videos_rois` join table. Measured per-video data lives
  # in `roi_times`/`tracking_results`, so sharing a ROI never shares acquired data.

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
  def duplicate_roi(%Scope{user: user} = scope, %Roi{user_id: user_id} = roi)
      when user_id == user.id do
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

  def update_roi(%Scope{user: user}, %Roi{user_id: user_id} = roi, attrs)
      when user_id == user.id do
    roi
    |> Roi.changeset(attrs)
    |> Repo.update()
  end

  def delete_roi(%Scope{user: user}, %Roi{user_id: user_id} = roi) when user_id == user.id do
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

  # --- Subjects ---

  def list_subjects(%Scope{user: user}) do
    Repo.all(from s in Subject, where: s.user_id == ^user.id, order_by: s.name)
  end

  def get_subject!(%Scope{user: user}, id) do
    Repo.get_by!(Subject, id: id, user_id: user.id)
  end

  def create_subject(%Scope{user: user}, attrs) do
    %Subject{user_id: user.id}
    |> Subject.changeset(attrs)
    |> Repo.insert()
  end

  def update_subject(%Subject{} = subject, attrs) do
    subject
    |> Subject.changeset(attrs)
    |> Repo.update()
  end

  def delete_subject(%Subject{} = subject), do: Repo.delete(subject)

  def change_subject(%Subject{} = subject, attrs \\ %{}) do
    Subject.changeset(subject, attrs)
  end

  # --- Subject results aggregation (Results "Por subject" tab) ---

  @doc """
  All of a subject's `"done"` videos, across every experiment owned by
  `scope`'s user (Subject is a reusable resource — see module doc), optionally
  restricted to a single `experiment_id`. Preloads `:calibration`, `:experiment`
  and `tracking_result: [roi_times: :roi]` so heatmaps, the per-video table and
  the metric aggregate can all be built without an N+1.
  """
  def subject_result_videos(%Scope{} = scope, subject_id, experiment_id \\ nil) do
    subject = get_subject!(scope, subject_id)

    query =
      from v in Video,
        where: v.subject_id == ^subject.id and v.status == "done",
        order_by: [desc: v.inserted_at],
        preload: [:calibration, :experiment, tracking_result: [roi_times: :roi]]

    query =
      if experiment_id, do: where(query, [v], v.experiment_id == ^experiment_id), else: query

    Repo.all(query)
  end

  @doc """
  Distinct experiments a subject has at least one `"done"` video in — used to
  populate the "scope" filter (all experiments vs. one) on the results screen.
  """
  def subject_experiments(%Scope{} = scope, subject_id) do
    scope
    |> subject_result_videos(subject_id)
    |> Enum.map(& &1.experiment)
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(& &1.name)
  end

  @doc """
  Groups `videos` by their (shared, reusable) `Calibration` — the closest
  proxy this schema has for "same field/arena", since two videos only end up
  with the same `calibration_id` if the user explicitly reused that
  calibration. Returns `[{calibration_or_nil, videos}]`; videos without a
  calibration are grouped under `nil` and sorted last.
  """
  def group_by_calibration(videos) do
    videos
    |> Enum.group_by(& &1.calibration_id)
    |> Enum.sort_by(fn {cal_id, _videos} -> {cal_id == nil, cal_id} end)
    |> Enum.map(fn {_cal_id, group_videos} ->
      {List.first(group_videos).calibration, group_videos}
    end)
  end

  @doc """
  Aggregates a subject's tracking metrics across `videos` (each expected to
  have `:tracking_result` preloaded, per `subject_result_videos/3`). Returns
  `%{n: total, metrics: %{key => %{mean:, sd:, n:}}, roi_zones: [%{name:, avg_seconds:, avg_share_pct:, n:}]}`.

  Videos without a `tracking_result` are skipped. Immobility is aggregated in
  raw seconds (`immobility_seconds`), the value Python always emits and the
  worker always persists — the video's `duration_seconds` is not reliably
  populated by the upload wizard, so a "share of session" percentage would be
  `nil` for real recordings.
  """
  def subject_metric_aggregate(videos) do
    videos_with_results = Enum.filter(videos, &(&1.tracking_result != nil))
    results = Enum.map(videos_with_results, & &1.tracking_result)

    metrics = %{
      distance_cm: stat(results, & &1.distance_cm),
      speed_mean_cm: stat(results, & &1.speed_mean_cm),
      speed_median_cm: stat(results, & &1.speed_median_cm),
      speed_max_cm: stat(results, & &1.speed_max_cm),
      thigmotaxis_pct: stat(results, & &1.thigmotaxis_pct),
      path_tortuosity: stat(results, & &1.path_tortuosity),
      immobility_seconds: stat(results, & &1.immobility_seconds)
    }

    %{n: length(results), metrics: metrics, roi_zones: roi_zone_aggregate(videos_with_results)}
  end

  defp stat(list, fun) do
    values = list |> Enum.map(fun) |> Enum.reject(&is_nil/1)
    n = length(values)

    case n do
      0 ->
        %{mean: nil, sd: nil, n: 0}

      _ ->
        mean = Enum.sum(values) / n

        sd =
          if n > 1 do
            variance = values |> Enum.map(&:math.pow(&1 - mean, 2)) |> Enum.sum()
            :math.sqrt(variance / (n - 1))
          end

        %{mean: mean, sd: sd, n: n}
    end
  end

  defp roi_zone_aggregate(videos_with_results) do
    videos_with_results
    |> Enum.flat_map(fn video ->
      duration = video.duration_seconds

      Enum.map(video.tracking_result.roi_times, fn rt ->
        share = if is_number(duration) and duration > 0, do: rt.seconds / duration * 100
        {rt.roi_id, rt.roi.name, rt.seconds, share}
      end)
    end)
    |> Enum.group_by(fn {roi_id, _name, _seconds, _share} -> roi_id end)
    |> Enum.map(fn {_roi_id, entries} ->
      [{_roi_id, name, _seconds, _share} | _] = entries
      seconds = Enum.map(entries, fn {_, _, s, _} -> s end)
      shares = entries |> Enum.map(fn {_, _, _, sh} -> sh end) |> Enum.reject(&is_nil/1)

      %{
        name: name,
        avg_seconds: Enum.sum(seconds) / length(seconds),
        avg_share_pct: if(shares != [], do: Enum.sum(shares) / length(shares)),
        n: length(entries)
      }
    end)
    |> Enum.sort_by(& &1.name)
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
