# Architecture

MTrack has two halves that meet at a subprocess boundary:

1. A **Phoenix/Elixir web application** (`lib/`) — auth, experiment management,
   the LiveView UI, background jobs, and persistence in PostgreSQL.
2. A **Python OpenCV tracking engine** (`priv/python/`) — the actual computer
   vision, invoked as a headless subprocess.

They communicate over stdout using line-delimited JSON. This document explains how
a video flows through the system and maps every module to its job. For the schema
details see [data-model.md](data-model.md); for the Python side see
[python-engine.md](python-engine.md).

## Lifecycle of a video

```
1. Upload         ExperimentLive.New (wizard step 1)
                    └─ save file to priv/static/uploads/videos/<token>/
                    └─ FrameExtractor extracts the first frame (Python --extract-frame)
2. Calibrate/ROI  ExperimentLive.New (wizard step 2)
                    └─ draw valid region + 2 scale segments + ROIs on a <canvas>
3. Review/create  ExperimentLive.New (wizard step 3)
                    └─ Experiments.create_experiment_with_videos/2
                    └─ Experiments.enqueue_video_processing/1  (one Oban job per video)
4. Process        VideoProcessingWorker.perform/1
                    └─ status "processing", broadcast {:status, id, "processing"}
                    └─ PythonPort.run/2  → Python subprocess (OpenCV)
                         · reads {"type":"progress","value":N} lines
                           → broadcast {:progress, id, pct}
                         · reads {"type":"result", ...} at the end
                    └─ persist TrackingResult + per-zone RoiTime rows
                    └─ write heatmap.png + speed_profile.png
                    └─ status "done", broadcast {:status,...} + {:processing_done, id}
5. Watch          VideoLive.Processing subscribes to "video:<id>" and renders
                    live % / status. Index & Show update their status pills too.
6. Read results   ExperimentLive.Results renders metrics, images, ROI table.
```

If the Python subprocess fails, the worker sets status `"error"`, broadcasts
`{:processing_error, id, reason}` and returns `{:error, reason}` so Oban retries
(max 3 attempts).

## Elixir domain (`lib/mouse_tracker/`)

### Contexts & modules

| Module | Responsibility |
|--------|----------------|
| `MouseTracker.Accounts` | User registration, login, magic-link auth, password/profile |
| `MouseTracker.Experiments` | Root context: Experiment/Video CRUD, wizard orchestration (`create_experiment_with_videos/2`), `enqueue_video_processing/1`, `TrackingResult` |
| `MouseTracker.Experiments.Calibrations` | Calibration CRUD + ownership + usage counts |
| `MouseTracker.Experiments.Rois` | ROI CRUD, video attach/detach, `roi_locked?/1`, `duplicate_roi/2`, `RoiTime` |
| `MouseTracker.Experiments.Subjects` | Subject CRUD + ownership + usage counts |
| `MouseTracker.Experiments.Reporting` | Cross-experiment aggregation: dataset summaries, per-subject metrics, calibration grouping, metric time-series |
| `MouseTracker.Experiments.FileCleanup` | Removes on-disk files when a video/experiment is deleted |
| `MouseTracker.Experiments.Ownership` | `defguard is_owner/2` shared by the resource contexts |
| `MouseTracker.Experiments.Export` | Builds CSV/XLSX rows for an experiment (pure functions) |
| `MouseTracker.Tracking.PythonPort` | Runs the Python subprocess via `Port.open`, streams progress |
| `MouseTracker.Tracking.PythonPortBehaviour` | Behaviour backing the Mox mock in tests |
| `MouseTracker.Tracking.FrameExtractor` | Extracts the first/Nth frame + video metadata (Python `--extract-frame`) |
| `MouseTracker.Workers.VideoProcessingWorker` | Oban worker: orchestrates tracking, persists results, broadcasts |
| `MouseTracker.Workers.OrphanUploadCleanupWorker` | Oban Cron worker: deletes abandoned uploads/frames |

Domain schemas live in `lib/mouse_tracker/tracking/` (`Experiment`, `Video`,
`Calibration`, `Roi`, `Subject`, `TrackingResult`, `RoiTime`) and
`lib/mouse_tracker/accounts/` (`User`, `UserToken`, `Scope`). See
[data-model.md](data-model.md).

**Ownership pattern.** `Calibration`, `Roi` and `Subject` are user-owned resources.
Their context functions take a `%Scope{}` and enforce ownership via the
`is_owner/2` guard, raising `FunctionClauseError` for another user's records.

## Web layer (`lib/mouse_tracker_web/`)

### Routes

From `router.ex`. Authenticated routes live in the `:require_authenticated_user`
live session; auth screens in the `:current_user` session.

| Path | LiveView / Controller |
|------|-----------------------|
| `/` | `RootRedirectController` → `/experiments` or `/users/log-in` |
| `/experiments` | `ExperimentLive.Index` |
| `/experiments/new`, `/new/roi`, `/new/review` | `ExperimentLive.New` (3-step wizard, one LiveView) |
| `/experiments/:id` | `ExperimentLive.Show` |
| `/experiments/:id/results` | `ExperimentLive.Results` |
| `/experiments/:id/export` | `ExportController` (plain HTTP download) |
| `/videos/:video_id/processing` | `VideoLive.Processing` |
| `/videos/:video_id/rois/:roi_id/edit` | `ExperimentLive.RoiEdit` |
| `/datasets` | `DatasetLive.Index` |
| `/analyses` | `AnalysesLive.Index` |
| `/pipeline-settings` | `PipelineSettingsLive.Index` |
| `/users/register`, `/users/log-in`, `/users/settings` | `UserLive.*` |
| `/users/log-in`, `/users/log-out`, `/users/update-password` | `UserSessionController` |

### Shared web helpers

- `LocomoComponents` — app-specific UI (status pills, stat cards, trend chart,
  subject colors).
- `CoreComponents` — generic inputs/buttons/tables/flash (Tailwind, no DaisyUI).
- `Formatters` — number/stat formatting, imported globally.
- `LiveHelpers` — `patch_params/2` for building `push_patch` query strings.
- `VideoStatusSync` — `subscribe_all/1` + `patch_status/3`, the "subscribe to each
  video's topic and update the right one on `{:status,...}`" logic reused by Index,
  Show and Datasets.
- `UserAuth` — the plug/on-mount that loads `current_scope` and enforces auth.

### Controllers (non-LiveView)

- `RootRedirectController` — `/` redirect.
- `ExportController` — streams an experiment's data as CSV/XLSX, or a `.zip`
  bundling the metrics file plus heatmap/speed PNGs. LiveView can't trigger a file
  download, so the Show export panel links here with options in the query string
  (`?format=xlsx&date=1&heatmap=1&...`).
- `UserSessionController` — session create/delete, password update.

## Background jobs (Oban)

- **`video_processing` queue** — one job per video; each spawns one Python
  subprocess. Concurrency defaults to 4, overridable in prod via
  `OBAN_VIDEO_PROCESSING_CONCURRENCY`. Retries up to 3 times on failure.
- **`maintenance` queue** — `OrphanUploadCleanupWorker`, scheduled daily by Oban
  Cron (`@daily`). Cron is disabled in the test env.

## Real-time (Phoenix PubSub)

All video updates are broadcast to the topic **`"video:<id>"`**
(`VideoProcessingWorker.topic/1`). Message types:

| Message | Meaning | Consumed by |
|---------|---------|-------------|
| `{:status, id, status}` | status changed | Index, Show, Datasets, Processing |
| `{:progress, id, pct}` | % of frames processed | Processing |
| `{:processing_done, id}` | finished successfully | Processing |
| `{:processing_error, id, reason}` | failed | Processing |

Screens subscribe on `mount` (only when `connected?/1`). Because status pills and
action buttons are derived from `video.status` on every render, applying the new
status to the right video is enough to update the UI with no manual refresh.

## The Python boundary

`PythonPort.run(params, on_progress)` opens the subprocess with `Port.open` (not
`System.cmd`) so stdout is read line-by-line as it's produced. Each line is one
JSON object. It returns `{:ok, result_map}` or `{:error, reason}`.

The caller (the worker) decides output image paths and passes them in the params
(`heatmap` / `speed_profile`); the Python result JSON does **not** echo them. The
worker maps the ROI list and calibration/subject records into the JSON params. See
[python-engine.md](python-engine.md) for the exact contract.
