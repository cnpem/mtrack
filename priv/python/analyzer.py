"""
analyzer.py
Responsible for: core tracking loop.
Takes video source, background, valid region, ROIs, and thresholds.
Processes frames and yields/returns raw coordinates, speeds, distances, and times inside ROIs.
"""

import json
import cv2
import numpy as np
from .metrics import distance, is_pt_into_roi, is_pt_into_circle
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
    """
    heatmap = None
    _pos_prev = None
    _t_pos = 0
    dist_total = 0.0
    initial_pos = None
    final_position = None
    speeds = []
    s0 = None
    t0 = 0
    t1 = 0
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
                cv2.rectangle(frame, (x, y), (x + w, y + h), (0, 255, 0), 2)

            if len(cnts) == 1:
                _pos_curr = (x + w / 2, y + h / 2)
                if initial_pos is None:
                    initial_pos = _pos_curr
                final_position = _pos_curr
                _t_pos += 1

                # Position update interval
                if _t_pos >= 5:
                    if _pos_prev is not None:
                        _dist = distance(_pos_prev, _pos_curr)
                        if _dist > 5:
                            dist_total += _dist
                            if not headless:
                                cv2.rectangle(
                                    frame,
                                    (int(_pos_curr[0] - 1), int(_pos_curr[1] - 1)),
                                    (int(_pos_curr[0] + 1), int(_pos_curr[1] + 1)),
                                    (0, 255, 0),
                                    2,
                                )
                        else:
                            if not headless:
                                cv2.rectangle(
                                    frame,
                                    (int(_pos_curr[0] - 1), int(_pos_curr[1] - 1)),
                                    (int(_pos_curr[0] + 1), int(_pos_curr[1] + 1)),
                                    (0, 0, 255),
                                    2,
                                )
                    _pos_prev = _pos_curr
                    _t_pos = 0

                # Speed estimation
                s1 = _pos_curr
                t1 += 1
                if s0 is None:
                    s0 = _pos_curr

                if t1 - t0 >= fps:
                    speeds.append(distance(s1, s0))
                    t0 += fps
                    s0 = s1

                # ROI statistics
                for i in range(len(rois)):
                    roi = rois[i]
                    if len(roi) == 3:
                        inside = is_pt_into_circle(_pos_curr, roi)
                    else:
                        inside = is_pt_into_roi(_pos_curr, roi)
                    if inside:
                        nframe_into_roi[i] += 1

                # Thigmotaxis
                nframe_detected += 1
                if thigmotaxis_zone is not None:
                    if len(thigmotaxis_zone) == 3:
                        in_central = is_pt_into_circle(_pos_curr, thigmotaxis_zone)
                    else:
                        in_central = is_pt_into_roi(_pos_curr, thigmotaxis_zone)
                    if not in_central:
                        nframe_peripheral += 1
            else:
                _t_pos += 1

        if not headless:
            cv2.imshow("Frame Delta", frameDelta)
            cv2.imshow("Video", frame)
            cv2.imshow("Thresh", thresh)

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
                
    return heatmap, dist_total, nframe_into_roi, speeds, initial_pos, final_position, nframe_peripheral, nframe_detected
