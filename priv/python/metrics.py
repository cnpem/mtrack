"""
metrics.py
Responsible for: pure mathematical/statistical calculations.
No I/O, no OpenCV calls, no rendering.
"""

from math import sqrt


def distance(pt0, pt1):
    """Euclidean distance between two 2-D points."""
    return sqrt((pt1[0] - pt0[0]) ** 2 + (pt1[1] - pt0[1]) ** 2)


def is_pt_into_roi(pt, roi):
    """Return True if point pt lies inside roi (x, y, w, h)."""
    return (
        pt[0] > roi[0]
        and pt[0] < (roi[0] + roi[2])
        and pt[1] > roi[1]
        and pt[1] < (roi[1] + roi[3])
    )


def px_to_cm(px_value, px_per_10cm):
    """Convert a pixel measurement to centimetres using the calibration factor."""
    conv = 10.0 / px_per_10cm
    return px_value * conv


def compute_speed_stats(speeds_cm):
    """
    Return (mean, median) in cm/s given a list of per-second speeds in cm/s.
    Returns (0.0, 0.0) for empty input.
    """
    import numpy as np

    if not speeds_cm:
        return 0.0, 0.0
    return float(np.mean(speeds_cm)), float(np.median(speeds_cm))

def compute_speed_max(speeds):
    """Returns the maximum speed, or 0.0 if there is none."""
    return float(max(speeds)) if speeds else 0.0

def compute_immobility_seconds(speeds_cm, threshold_cm=2.0):
    """Returns the total immobility time (speed < threshold per second)."""
    return float(sum(1 for s in speeds_cm if s < threshold_cm))

def compute_tortuosity(total_distance, initial_pos, final_pos):
    """
    Toruosity = total distance/straight line movement
    0.0 if displacement == 0
    """
    displacement = distance(initial_pos, final_pos)

    if displacement == 0:
        return 0.0
    return total_distance/displacement

def get_central_zone_rectangular(valid_region, margin_pct=0.20):
    """Return (x, y, w, h) of the central zone, each edge inset by margin_pct of that dimension."""
    x, y, w, h = valid_region
    mx = int(w * margin_pct)
    my = int(h * margin_pct)
    return (x + mx, y + my, w - 2 * mx, h - 2 * my)


def get_central_zone_circular(valid_region, margin_pct=0.20):
    """Return (cx, cy, r) of the central circular zone.

    The peripheral zone is the outer ring of thickness margin_pct * r_arena from the wall,
    so r_central = (1 - margin_pct) * r_arena where r_arena = min(w, h) / 2.
    """
    x, y, w, h = valid_region
    cx = x + w / 2
    cy = y + h / 2
    r_arena = min(w, h) / 2
    r = int((1 - margin_pct) * r_arena)
    return (cx, cy, r)


def is_pt_into_circle(pt, circle):
    """Return True if point pt lies inside the circle (cx, cy, r)."""
    cx, cy, r = circle
    return distance(pt, (cx, cy)) < r


def compute_thigmotaxis_pct(nframe_peripheral, nframe_detected):
    """
    Return % of detected frames where the animal was in the peripheral zone (0–100).
    """
    if nframe_detected == 0:
        return 0.0
    return round(100.0 * nframe_peripheral / nframe_detected, 2)
