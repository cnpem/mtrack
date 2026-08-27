"""
run.py
Responsible for: entry point / orchestrator.
Parses arguments, manages video setup, calls analyzer / render / metrics modules, and displays/saves outputs.
"""

import json
import sys
import argparse
import cv2
import numpy as np

from . import detector
from . import render
from . import analyzer
from . import metrics


def _downsample(seq, cap=2000):
    """Evenly-strided subsample of ``seq`` to at most ``cap`` values (rounded).

    Preserves the overall shape of the distribution while bounding the size of
    the persisted per-frame speed array — a boxplot only needs the shape, not
    every frame.
    """
    n = len(seq)
    if n == 0:
        return []
    if n <= cap:
        return [round(float(v), 2) for v in seq]
    step = n / cap
    return [round(float(seq[int(i * step)]), 2) for i in range(cap)]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-v", "--video", help="path to the video file")
    ap.add_argument(
        "-st", "--start-time", type=int, default=0, help="start time in seconds"
    )
    ap.add_argument(
        "-et", "--end-time", type=int, default=0, help="end time in seconds"
    )
    ap.add_argument(
        "-roi", "--roi", action="store_true", help="select region of interest (ROI)"
    )
    ap.add_argument("-a", "--min-area", type=int, default=250, help="minimum area size")
    ap.add_argument("-th", "--threshold", type=int, default=80, help="threshold")
    ap.add_argument(
        "-c",
        "--calibrate",
        type=float,
        help="cage side in cm (enables interactive calibration)",
    )
    ap.add_argument(
        "-sp", "--speed-profile", help="speed profile plot (cm/s along the video)"
    )
    ap.add_argument("-sd", "--speed-distribution", help="speed distribution histogram")
    ap.add_argument("-hm", "--heatmap", help="occupancy heatmap")
    ap.add_argument(
        "--json", dest="json_params",
        help="JSON string com parâmetros (modo headless, sem janelas OpenCV)",
    )
    ap.add_argument(
        "--extract-frame", type=int, dest="extract_frame", default=None,
        help="Extrai o frame N como PNG (modo headless) e sai",
    )
    ap.add_argument(
        "--extract-output", dest="extract_output",
        help="Caminho de saída do PNG para --extract-frame",
    )

    args = vars(ap.parse_args())

    if args["extract_frame"] is not None:
        _extract_frame(args["video"], args["extract_frame"], args["extract_output"])
    elif args["json_params"]:
        _run_headless(args["json_params"])
    else:
        _run_interactive(args)


def _extract_frame(video_path, frame_num, output_path):
    """Save frame `frame_num` of the video as a PNG at `output_path` (headless)."""
    vs = cv2.VideoCapture(video_path)
    if not vs.isOpened():
        print(json.dumps({"type": "error", "message": "could not open video"}), flush=True)
        sys.exit(1)

    fps = analyzer.video_fps(vs)
    frame_count = analyzer.video_length(vs)
    width = vs.get(cv2.CAP_PROP_FRAME_WIDTH)
    height = vs.get(cv2.CAP_PROP_FRAME_HEIGHT)
    duration = frame_count / fps if fps and fps > 0 else None

    if frame_num > 0:
        vs.set(cv2.CAP_PROP_POS_FRAMES, frame_num)
    ok, frame = vs.read()
    vs.release()

    if not ok or frame is None:
        print(json.dumps({"type": "error", "message": "could not read frame"}), flush=True)
        sys.exit(1)

    cv2.imwrite(output_path, frame)
    print(json.dumps({
        "type": "video_info",
        "fps": round(fps) if fps else None,
        "frame_count": int(frame_count) if frame_count else None,
        "width": int(width) if width else None,
        "height": int(height) if height else None,
        "duration_seconds": round(duration, 2) if duration else None,
    }), flush=True)
    print(json.dumps({"type": "frame", "path": output_path}), flush=True)


def _run_headless(json_str):
    params = json.loads(json_str)

    vs = cv2.VideoCapture(params["video"])
    fps = analyzer.video_fps(vs)

    # The background model is built from a single "empty arena" frame. Frame 0 is
    # the default, but the user can pick another (via the wizard) when the first
    # frame is contaminated — e.g. a hand still placing the animal — which would
    # otherwise leak into the heatmap and cause false motion for the whole video.
    background_frame = int(params.get("background_frame", 0) or 0)
    if background_frame > 0:
        vs.set(cv2.CAP_PROP_POS_FRAMES, background_frame)
    ff = vs.read()[1]
    bg = detector.get_background(ff)
    if background_frame > 0:
        vs.set(cv2.CAP_PROP_POS_FRAMES, 0)

    valid_region = params["valid_region"]
    px_per_10cm = params.get("px_per_10cm", 1.0)
    rois = params.get("rois", [])
    start_time = params.get("start_time", 0)
    end_time = params.get("end_time", 0)
    threshold = params.get("threshold", 80)
    min_area = params.get("min_area", 250)
    progress_every = params.get("progress_every", 50)

    thigmotaxis_margin_pct = params.get("thigmotaxis_margin_pct", 0.20)
    arena_shape = params.get("arena_shape", "rect")
    if arena_shape == "circle":
        central_zone = metrics.get_central_zone_circular(valid_region, thigmotaxis_margin_pct)
    else:
        central_zone = metrics.get_central_zone_rectangular(valid_region, thigmotaxis_margin_pct)

    analyzer.skip_frames(vs, int(start_time * fps))
    len_frames = (int(end_time) - int(start_time)) * fps

    heatmap, dist_px, frames_into_roi, speeds_px, initial_pos, final_pos, nframe_peripheral, nframe_detected, positions = analyzer.process(
        vs, bg, valid_region, threshold, min_area, rois, len_frames,
        headless=True, progress_every=progress_every, thigmotaxis_zone=central_zone,
    )

    immobility_threshold = params.get("immobility_threshold_cm", 2.0)
    m = metrics.compute_all(
        dist_px, speeds_px, nframe_peripheral, nframe_detected,
        px_per_10cm, immobility_threshold, positions=positions,
    )

    print(json.dumps({
        "type":               "result",
        "distance_px":        round(m["distance_px"], 2),
        "distance_cm":        round(m["distance_cm"], 2),
        "speed_mean_px":      round(m["speed_mean_px"], 2),
        "speed_mean_cm":      round(m["speed_mean_cm"], 2),
        "speed_median_px":    round(m["speed_median_px"], 2),
        "speed_median_cm":    round(m["speed_median_cm"], 2),
        "speed_max_px":       round(m["speed_max_px"], 2),
        "speed_max_cm":       round(m["speed_max_cm"], 2),
        "immobility_seconds": round(m["immobility_seconds"], 2),
        "path_tortuosity":    round(m["path_tortuosity"], 4),
        "thigmotaxis_pct":    m["thigmotaxis_pct"],
        "frames_into_roi":    list(frames_into_roi),
        "time_into_roi_s":    [round(f / fps, 2) for f in frames_into_roi],
        # Downsampled per-frame speeds (cm/s) for the Analyses "Speed
        # distribution" boxplot — capped so a long recording doesn't bloat the
        # result line / DB row.
        "speed_samples":      _downsample(m["speeds_cm"]),
    }), flush=True)

    speeds_cm = m["speeds_cm"]
    max_speed = 300 * m["conv"] if speeds_cm else 300
    if params.get("speed_profile"):
        render.plot_speed_profile(speeds_cm, m["speed_mean_cm"], m["speed_median_cm"], max_speed, params["speed_profile"])
    if params.get("speed_distribution"):
        render.plot_speed_distribution(speeds_cm, max_speed, params["speed_distribution"])
    if params.get("heatmap"):
        render.plot_heatmap(
            heatmap, fps, bg, 120 * fps, params["heatmap"],
            valid_region=valid_region, rois=rois,
        )


def _run_interactive(args):
    # 1. Initialize video reader
    vs = cv2.VideoCapture(args["video"])
    fps = analyzer.video_fps(vs)

    # Read the very first frame to establish background model
    ff = vs.read()[1]
    bg = detector.get_background(ff)

    # 2. Select valid tracking region
    valid_region = render.select_valid_region(ff)

    # 3. Handle calibration
    if args["calibrate"]:
        px_per_10cm = render.calibrate(ff, args["calibrate"])
    else:
        px_per_10cm = 1.0

    # 4. Handle regions of interest (ROI)
    rois = []
    if args["roi"]:
        rois = render.select_roi(ff)

    # 5. Fast-forward video to start-time
    analyzer.skip_frames(vs, int(args["start_time"] * fps))
    len_frames = (int(args["end_time"]) - int(args["start_time"])) * fps

    # 6. Run the main processing loop
    central_zone = metrics.get_central_zone_rectangular(valid_region)
    heatmap, dist_px, frames_into_roi, speeds_px, initial_pos, final_pos, nframe_peripheral, nframe_detected, positions = analyzer.process(
        vs, bg, valid_region, args["threshold"], args["min_area"], rois, len_frames,
        thigmotaxis_zone=central_zone,
    )

    # 7. Convert pixels to metric scale (cm) and derive every stat
    m = metrics.compute_all(
        dist_px, speeds_px, nframe_peripheral, nframe_detected,
        px_per_10cm, positions=positions,
    )

    # 8. Print report
    print("Distance: {:.2f} px ({:.2f} cm)".format(m["distance_px"], m["distance_cm"]))
    print("Speed mean: {:.2f} px/s ({:.2f} cm/s)".format(m["speed_mean_px"], m["speed_mean_cm"]))
    print("Speed median: {:.2f} px/s ({:.2f} cm/s)".format(m["speed_median_px"], m["speed_median_cm"]))
    print("Speed max: {:.2f} px/s ({:.2f} cm/s)".format(m["speed_max_px"], m["speed_max_cm"]))
    print("Immobility: {:.2f} s".format(m["immobility_seconds"]))
    print("Tortuosity (sinuosity index): {:.4f}".format(m["path_tortuosity"]))
    print("Thigmotaxis: {:.2f}%".format(m["thigmotaxis_pct"]))

    print("# frames into ROI {}".format(frames_into_roi))
    for i in range(len(frames_into_roi)):
        print("Time into ROI {}: {} seconds".format(i + 1, frames_into_roi[i] / fps))

    # 9. Plotting and saving visualizations
    speeds_cm = m["speeds_cm"]
    max_speed = 300 * m["conv"] if speeds_cm else 300

    if args["speed_profile"]:
        render.plot_speed_profile(speeds_cm, m["speed_mean_cm"], m["speed_median_cm"], max_speed, args["speed_profile"])

    if args["speed_distribution"]:
        render.plot_speed_distribution(speeds_cm, max_speed, args["speed_distribution"])

    if args["heatmap"]:
        heatmap_max_time = 120
        render.plot_heatmap(
            heatmap, fps, bg, heatmap_max_time * fps, args["heatmap"],
            valid_region=valid_region, rois=rois,
        )

    cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
