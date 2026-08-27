"""
analyzer.py
Responsible for: core tracking loop.
Takes video source, background, valid region, ROIs, and thresholds.
Processes frames and yields/returns raw coordinates, speeds, distances, and times inside ROIs.
"""

import json
import cv2
import numpy as np
from . import metrics, render
from .detector import diff_btw_frames, exclude_invalid_region, apply_threshold


def video_length(vs):
    return vs.get(cv2.CAP_PROP_FRAME_COUNT)


def video_fps(vs):
    return vs.get(cv2.CAP_PROP_FPS)


def skip_frames(vs, n_frames):
    for _ in range(n_frames):
        _ = vs.grab()


def process(vs, bg, valid_region, threshold, min_area, rois, len_frames,
            headless=False, progress_every=50, thigmotaxis_zone=None):
    """
    Main tracking algorithm loop.
    Returns:
        heatmap: 2D numpy array
        dist_total: accumulated distance in pixels
        nframe_into_roi: list of frame counts per ROI
        speeds: list of pixel distances calculated at 1-second intervals
        initial_pos, final_pos: first/last detected position
        nframe_peripheral, nframe_detected: thigmotaxis frame counts
        positions: trajectory sampled at the same 1-second cadence as
            `speeds` (positions[i-1] -> positions[i] is the step measured
            in speeds[i-1]); used to compute path sinuosity
    """
    heatmap = None
    motion = metrics.new_motion_state()
    fps = video_fps(vs)
    nframe_into_roi = [0] * len(rois)
    nframe_peripheral = 0
    nframe_detected = 0

    use_length = len_frames > 0
    frames_processed = 0

    while True:
        frame = vs.read()[1]
        if frame is None:
            break

        frames_processed += 1

        if use_length:
            if len_frames <= 0:
                break
            else:
                len_frames -= 1

        frameDelta = diff_btw_frames(frame, bg)
        frameDelta = exclude_invalid_region(frameDelta, valid_region)
        thresh = apply_threshold(frameDelta, threshold)

        cnts = cv2.findContours(
            thresh.copy(), cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE
        )
        cnts = cnts[0]

        for c in cnts:
            if cv2.contourArea(c) < min_area:
                continue

            (x, y, w, h) = cv2.boundingRect(c)
            if not headless:
                render.draw_detection_box(frame, x, y, w, h)

            if len(cnts) == 1:
                pos_curr = (x + w / 2, y + h / 2)

                motion, moved = metrics.update_motion(motion, pos_curr, fps)
                if not headless and moved is not None:
                    render.draw_position_marker(frame, pos_curr, moved)

                for i, inside in enumerate(metrics.rois_containing(pos_curr, rois)):
                    if inside:
                        nframe_into_roi[i] += 1

                nframe_detected += 1
                if thigmotaxis_zone is not None:
                    if not metrics.is_pt_in_shape(pos_curr, thigmotaxis_zone):
                        nframe_peripheral += 1
            else:
                motion = metrics.skip_motion_sample(motion)

        if not headless:
            render.show_debug_windows(frameDelta, frame, thresh)

        if heatmap is None:
            heatmap = thresh / 255
        else:
            heatmap += thresh / 255

        if headless:
            if use_length and frames_processed % progress_every == 0:
                total = frames_processed + len_frames
                pct = round(frames_processed / total * 100, 1)
                print(json.dumps({"type": "progress", "value": pct}), flush=True)
        else:
            key = cv2.waitKey(1) & 0xFF
            if key == ord("q"):
                break

    return (
        heatmap,
        motion.dist_total,
        nframe_into_roi,
        motion.speeds,
        motion.initial_pos,
        motion.final_pos,
        nframe_peripheral,
        nframe_detected,
        motion.positions,
    )
