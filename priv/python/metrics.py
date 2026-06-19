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
