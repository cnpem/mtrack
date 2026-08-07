# User guide

A task-oriented walkthrough of MTrack for researchers. It assumes the app is
running (see [setup.md](setup.md)); no command line is needed after that.

## 1. Account & sign-in

- **Register** at `/users/register` with your name (required), email, password and
  optionally your institution. The account is confirmed immediately.
- **Sign in** at `/users/log-in` with your password, or request a **magic link**
  (a one-time email link). In development, magic-link emails appear in the mailbox
  preview at `/dev/mailbox` rather than a real inbox.

After sign-in you land on **Experiments**.

## 2. Create an experiment (3-step wizard)

Click **New experiment**. Everything happens in one guided wizard.

### Step 1 — Upload

Upload a **single** video or a **batch**. Each file is saved and its first frame is
extracted so you can mark it up visually in the next step.

### Step 2 — Calibration & ROIs (drawn on the frame)

You draw directly on the first frame of each video (on a canvas). There is no
numeric coordinate form.

- **Valid region** — draw a box around the arena to ignore movement outside it.
- **Scale (2 segments)** — draw **two** reference segments and type the real length
  (cm) of each. MTrack averages them into the pixels-to-cm factor. If the two
  disagree by more than 8%, you get a non-blocking warning — re-draw a segment if a
  click was off, or continue anyway.
- **ROIs** — draw zones of interest as a **4-point polygon** or a **circle**. Time
  spent in each is reported per video.
- **Background frame** — if the first frame is contaminated (e.g. a hand still
  placing the animal), pick a cleaner frame index and reload it. Your drawings stay
  valid because they're in native pixels.
- **Advanced parameters** — `threshold`, `min area`, `peripheral %` and
  `immobility threshold` (explained below). These prefill from your Pipeline
  Settings defaults and are editable per video/batch.

**Batches — reference & inheritance.** Mark one video as the **reference**; the
others **inherit** its scale and ROIs (choose which reference from a dropdown), so
you calibrate once for the whole batch. Reference applies to scale and ROIs
together.

### Step 3 — Review & create

Name the experiment, and for each video pick a **subject** — an existing one from
your library or a new one ("+ New subject"). Reusing a subject links sessions of
the same animal across experiments. Click create; each video is queued for
processing.

### Tracking parameters, in plain language

| Parameter | What it does | When to change |
|-----------|--------------|----------------|
| **Threshold** | Motion-detection sensitivity vs. the background. Lower = more sensitive | Raise if noise/shadows are detected as movement; lower if a still animal is missed |
| **Min area** | Smallest blob (px) counted as the animal | Raise to ignore small artifacts; lower for a small animal / zoomed-out video |
| **Peripheral %** | Width of the wall-hugging (thigmotaxis) border, as % of the arena | Match your arena definition of "periphery" |
| **Immobility threshold** | Speed (cm/s) below which the animal counts as immobile | Adjust to your freezing/immobility criterion |

## 3. Watch processing

From the experiment page, open a processing video to see **live progress** — a
percentage bar, a pipeline step indicator and a log console — updating in real time
over the websocket. Status pills on the Experiments and detail pages also update on
their own; no refresh needed.

## 4. Read results

Open **Results** for an experiment.

- **Per-video tab** — stat cards (distance, mean/median/max speed, thigmotaxis,
  path tortuosity, immobility, time-in-ROI), the **heatmap** and **speed-profile**
  images, and a per-zone ROI table.
- **Per-subject tab** — aggregates a subject's `"done"` videos **across
  experiments**, with an optional filter by experiment. Toggle **Average**
  (mean ± SD, with n) or **Per video**. Heatmaps are grouped by calibration ("same
  field" = same calibration) and shown side by side.

## 5. Datasets

`/datasets` is a read-only library of **all your videos across experiments**, with
summary cards (totals, recorded seconds, how many are done, storage), search,
status filter, thumbnails, and a **Per-video / Per-subject** toggle.

## 6. Analyses

`/analyses` shows how a subject's metrics evolve across its sessions over time
(chronologically, across experiments). Pick a metric (distance, speeds,
thigmotaxis, tortuosity, immobility) and **overlay multiple subjects** on the same
trend chart to compare them. A table below lists every session's metrics.

## 7. Pipeline Settings

`/pipeline-settings` is your resource library and defaults:

- **Calibrations / ROIs / Subjects** tabs — search, rename inline, delete (delete is
  blocked while a resource is still used by any video), duplicate an ROI.
- **Pipeline defaults** — set your personal `threshold`, `min area`, `peripheral %`
  and `immobility threshold`. These prefill the wizard's Advanced step.

## 8. Export

On an experiment's detail page, use the **export panel**:

- **Format** — CSV or XLSX (one row per processed video/session, with the core
  locomotion metrics and one time-in-zone column per ROI).
- **Optional metadata groups** — date, video, calibration columns.
- **Images** — include the **heatmap** and/or **speed-profile** PNGs; when either is
  selected the download becomes a **`.zip`** bundling the metrics file plus those
  images for every processed video.

Only processed ("done") videos are included in exports.
