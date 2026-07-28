defmodule MouseTracker.Experiments.Reporting do
  @moduledoc """
  Cross-experiment aggregation: the Datasets library and the Results/Analyses
  "por subject" views. `Subject`/`Roi`/`Calibration` are reusable resources
  (see their own modules) — this is what makes "reusable" actually pay off,
  by rolling their data up across every experiment/video that shares them.
  """

  import Ecto.Query

  alias MouseTracker.Repo
  alias MouseTracker.Accounts.Scope
  alias MouseTracker.Experiments.Video
  alias MouseTracker.Experiments.Subjects

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

  @doc """
  All of a subject's `"done"` videos, across every experiment owned by
  `scope`'s user (Subject is a reusable resource — see module doc), optionally
  restricted to a single `experiment_id`. Preloads `:calibration`, `:experiment`
  and `tracking_result: [roi_times: :roi]` so heatmaps, the per-video table and
  the metric aggregate can all be built without an N+1.
  """
  def subject_result_videos(%Scope{} = scope, subject_id, experiment_id \\ nil) do
    subject = Subjects.get_subject!(scope, subject_id)

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
  Groups `videos` (as returned by `list_all_videos/1`) by subject — the
  Datasets library's "Por subject" view. Videos with no subject are grouped
  under a `nil` subject, sorted last. Each group's `:aggregate` reuses
  `subject_metric_aggregate/1` over only that group's `"done"` videos.
  """
  def subject_groups(videos) do
    videos
    |> Enum.group_by(& &1.subject_id)
    |> Enum.map(fn {_subject_id, group} ->
      done = Enum.filter(group, &(&1.status == "done"))

      %{
        subject: List.first(group).subject,
        videos: group,
        aggregate: subject_metric_aggregate(done)
      }
    end)
    |> Enum.sort_by(fn %{subject: subject} ->
      {is_nil(subject), subject && String.downcase(subject.name)}
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

  @doc """
  Total seconds spent across every ROI zone for one tracking result (sum of
  `roi_times`) — the per-video "Time in ROI" stat card and the denominator
  shown next to the per-video zone breakdown table on the Results screen.
  """
  def total_roi_seconds(%{roi_times: roi_times}) when is_list(roi_times) do
    roi_times |> Enum.map(& &1.seconds) |> Enum.sum()
  end

  def total_roi_seconds(_), do: 0.0

  @doc """
  Percentage of a session spent in a zone, or `nil` if `duration_seconds` is
  missing/zero (older videos may lack it) — the same nil convention
  `roi_zone_aggregate/1` already uses for `avg_share_pct`, so a caller only
  has one rule to remember for "can this video's share be computed at all".
  """
  def share_of_session(_seconds, duration) when duration in [nil, 0, 0.0], do: nil

  def share_of_session(seconds, duration) do
    min(seconds / duration * 100, 100.0)
  end

  @doc """
  One time-series point per video that has a value for `metric_key`,
  chronological (oldest first — `subject_result_videos/3` returns
  newest-first) — the Analyses trend chart's one-metric-at-a-time view of a
  subject's sessions. Skips videos with no `tracking_result` at all, then
  skips points whose specific metric is nil (some metrics — thigmotaxis,
  tortuosity, immobility, max speed — are optional on `TrackingResult` and can
  legitimately be missing even on a "done" video).
  """
  def metric_series(videos, metric_key) do
    metric_atom = String.to_existing_atom(metric_key)

    videos
    |> Enum.reverse()
    |> Enum.filter(&(&1.tracking_result != nil))
    |> Enum.map(fn video ->
      %{
        video_id: video.id,
        date: video.inserted_at,
        label: Calendar.strftime(video.inserted_at, "%b %d"),
        experiment_name: video.experiment.name,
        filename: video.filename,
        value: Map.get(video.tracking_result, metric_atom)
      }
    end)
    |> Enum.reject(&is_nil(&1.value))
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
end
