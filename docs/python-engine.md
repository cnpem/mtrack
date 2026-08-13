# Python tracking engine

The computer-vision engine lives in `priv/python/` and is run through `uv`. It has
two modes: an **interactive** CLI (OpenCV windows, for standalone use) and a
**headless** JSON mode (how Phoenix invokes it as a subprocess). Every line of
stdout in headless mode is a single JSON object.

> `priv/mouse_tracker.py` is the original monolithic script and is **deprecated**.
> Use the `priv/python/` module.

## Module split

| File | Responsibility |
|------|----------------|
| `run.py` | Entry point / orchestrator. Parses args, dispatches to interactive / headless / frame-extract |
| `analyzer.py` | Core tracking loop `process/9` — frame diff, position/speed sampling, ROI & thigmotaxis counting, optional OpenCV drawing |
| `detector.py` | Frame differencing and thresholding (pure functions) |
| `metrics.py` | Distance, speed stats, px↔cm conversion, ROI/polygon geometry; `compute_all/8` derives every metric |
| `render.py` | Interactive OpenCV setup + Matplotlib/Seaborn plot generation (imports are lazy) |

## Modes

```bash
# Interactive — OpenCV windows for calibration and ROI selection
uv run python -m priv.python.run -v <video> -c <cage_side_cm> [options]

# Headless — JSON in, progress/result JSON out (used by Phoenix)
uv run python -m priv.python.run --json '<json>'

# Frame extraction — write frame N as PNG, emit metadata, exit
uv run python -m priv.python.run -v <video> --extract-frame <N> --extract-output <path.png>
```

Interactive options: `-st`/`-et` (start/end seconds), `-th` (threshold, default 80),
`-a` (min contour area, default 250), `-roi` (enable ROI selection), `-c` (cage side
cm, enables calibration), `-sp`/`-sd`/`-hm` (speed-profile / speed-distribution /
heatmap output paths).

## Headless JSON contract

### Input (`--json '<json>'`)

**Required:** `video`, `valid_region` (`[x, y, w, h]`).

**Optional (with defaults):**

| Key | Default | Meaning |
|-----|---------|---------|
| `start_time` / `end_time` | `0` | analysis window in seconds |
| `threshold` | `80` | motion-detection threshold (lower = more sensitive) |
| `min_area` | `250` | minimum contour area (px) to count as the animal |
| `px_per_10cm` | `1.0` | pixels per 10 cm (from calibration); `1.0` ⇒ output stays in px |
| `rois` | `[]` | list of ROI shapes (see below) |
| `progress_every` | `50` | emit a progress line every N frames |
| `background_frame` | `0` | frame index used to build the background model |
| `thigmotaxis_margin_pct` | `0.20` | peripheral-zone margin as a fraction of the arena |
| `immobility_threshold_cm` | `2.0` | speed (cm/s) below which a frame counts as immobile |
| `arena_shape` | `"rect"` | `"rect"` or `"circle"` (affects the thigmotaxis central zone) |
| `speed_profile` / `speed_distribution` / `heatmap` | — | output PNG paths; the Python side writes them |

### ROI format

ROIs are flat lists; the shape is inferred from the length:

- `[x, y, radius]` — **circle** (length 3)
- `[x, y, w, h]` — **axis-aligned rectangle** (length 4)
- `[x1, y1, x2, y2, x3, y3, x4, y4]` — **free 4-point polygon** (length ≥ 6, even),
  tested with ray-casting (`metrics.is_pt_into_polygon/2`, handles concave quads)

### Output (stdout, line-delimited JSON)

During processing, repeatedly:

```json
{"type": "progress", "value": 42.5}
```

At the end, once:

```json
{"type": "result",
 "distance_px": …, "distance_cm": …,
 "speed_mean_px": …, "speed_mean_cm": …,
 "speed_median_px": …, "speed_median_cm": …,
 "speed_max_px": …, "speed_max_cm": …,
 "immobility_seconds": …, "path_tortuosity": …, "thigmotaxis_pct": …,
 "frames_into_roi": [...], "time_into_roi_s": [...]}
```

> Note: the result does **not** echo `heatmap_path` / `speed_profile_path`. The
> caller passes those paths in (`heatmap` / `speed_profile`) and the engine writes
> the PNGs there.

### Frame-extract output

`--extract-frame` emits two lines: video metadata then the frame path.

```json
{"type": "video_info", "fps": 30, "frame_count": 9000, "width": 640, "height": 480, "duration_seconds": 300.0}
{"type": "frame", "path": "…/frame.png"}
```

## Metrics

All computed in `metrics.py` and surfaced in the `result` JSON:

| Field | Description |
|-------|-------------|
| `distance_px` / `distance_cm` | total path length |
| `speed_mean/median/max_*` | speed statistics (sampled at 1-second intervals) |
| `thigmotaxis_pct` | % of time in the peripheral zone (margin configurable; rect or circular arena) |
| `immobility_seconds` | total seconds with speed below `immobility_threshold_cm` |
| `path_tortuosity` | total distance ÷ straight-line displacement |
| `time_into_roi_s` | seconds spent inside each ROI (parallel to the `rois` input order) |

## How Phoenix calls it

- `MouseTracker.Tracking.PythonPort.run/2` runs headless mode via `Port.open`,
  reading progress/result lines as they arrive.
- `MouseTracker.Tracking.FrameExtractor` runs `--extract-frame` (via `System.cmd`)
  for wizard previews and thumbnails, parsing the `video_info` line to populate
  `Video` metadata.

See [architecture.md](architecture.md) for the Elixir side of this boundary.
