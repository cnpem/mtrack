"""
metrics.py
Responsible for: pure mathematical/statistical calculations.
No I/O, no OpenCV calls, no rendering.
"""

from collections import namedtuple
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


def is_pt_into_polygon(pt, flat_pts):
    """Return True if point pt lies inside the polygon.

    `flat_pts` is a flat list of vertex coordinates `[x0, y0, x1, y1, ...]`
    (e.g. 8 values for a quadrilateral). Uses the ray-casting (even-odd) rule,
    so it also works for concave polygons. Pure Python — no OpenCV.
    """
    verts = [(flat_pts[i], flat_pts[i + 1]) for i in range(0, len(flat_pts), 2)]
    n = len(verts)
    if n < 3:
        return False

    x, y = pt[0], pt[1]
    inside = False
    j = n - 1
    for i in range(n):
        xi, yi = verts[i]
        xj, yj = verts[j]
        if (yi > y) != (yj > y):
            x_cross = (xj - xi) * (y - yi) / (yj - yi) + xi
            if x < x_cross:
                inside = not inside
        j = i
    return inside


MotionState = namedtuple(
    "MotionState",
    "pos_prev t_pos dist_total initial_pos final_pos s0 t0 t1 speeds",
)


def new_motion_state():
    """Initial accumulator state for a `process/9` run — same starting values
    the loop used to initialise as loose local variables."""
    return MotionState(
        pos_prev=None,
        t_pos=0,
        dist_total=0.0,
        initial_pos=None,
        final_pos=None,
        s0=None,
        t0=0,
        t1=0,
        speeds=[],
    )


def skip_motion_sample(state):
    """Advance past a frame with an ambiguous detection (0 or >1 contours) —
    only `t_pos` moves, mirroring the previous inline `_t_pos += 1`."""
    return state._replace(t_pos=state.t_pos + 1)


def update_motion(state, pos, fps):
    """Advance motion/speed accumulation by one unambiguous detected
    position. Returns (new_state, moved), where `moved` is `None` when the
    position-update interval didn't fire this frame (nothing for the
    interactive renderer to draw), and otherwise `True`/`False` for whether
    the displacement exceeded the 5px noise threshold — used to pick the
    green/red debug marker color."""
    t_pos = state.t_pos + 1
    pos_prev = state.pos_prev
    dist_total = state.dist_total
    moved = None

    if t_pos >= 5:
        if pos_prev is not None:
            d = distance(pos_prev, pos)
            moved = d > 5
            if moved:
                dist_total += d
        pos_prev = pos
        t_pos = 0

    initial_pos = state.initial_pos if state.initial_pos is not None else pos
    final_pos = pos

    s0 = state.s0 if state.s0 is not None else pos
    t1 = state.t1 + 1
    speeds = state.speeds
    if t1 - state.t0 >= fps:
        speeds = speeds + [distance(pos, s0)]
        t0 = state.t0 + fps
        s0 = pos
    else:
        t0 = state.t0

    new_state = state._replace(
        pos_prev=pos_prev,
        t_pos=t_pos,
        dist_total=dist_total,
        initial_pos=initial_pos,
        final_pos=final_pos,
        s0=s0,
        t0=t0,
        t1=t1,
        speeds=speeds,
    )
    return new_state, moved


def is_pt_in_shape(pt, shape):
    """Dispatch point-in-shape membership by `len(shape)`: 3 = circle
    (cx, cy, r), 4 = axis-aligned rect (x, y, w, h), >=6 (even) = polygon
    (flat list of vertices). Same convention used to distinguish ROI shapes
    coming from the Elixir side."""
    if len(shape) == 3:
        return is_pt_into_circle(pt, shape)
    elif len(shape) == 4:
        return is_pt_into_roi(pt, shape)
    else:
        return is_pt_into_polygon(pt, shape)


def rois_containing(pt, rois):
    """Return a list of booleans, one per roi in `rois`, indicating whether
    `pt` lies inside that roi (shape auto-detected via `is_pt_in_shape`)."""
    return [is_pt_in_shape(pt, roi) for roi in rois]


def compute_thigmotaxis_pct(nframe_peripheral, nframe_detected):
    """
    Return % of detected frames where the animal was in the peripheral zone (0–100).
    """
    if nframe_detected == 0:
        return 0.0
    return round(100.0 * nframe_peripheral / nframe_detected, 2)


def compute_all(
    dist_px,
    speeds_px,
    initial_pos,
    final_pos,
    nframe_peripheral,
    nframe_detected,
    px_per_10cm,
    immobility_threshold_cm=2.0,
):
    """
    Derive every per-run metric from the raw outputs of `analyzer.process/9`.
    Used by both the headless (--json) and interactive entry points in run.py
    so the px->cm conversion and each derived stat has exactly one definition.
    """
    conv = 10.0 / px_per_10cm
    speeds_cm = [s * conv for s in speeds_px]

    speed_mean_cm, speed_median_cm = compute_speed_stats(speeds_cm)
    speed_mean_px, speed_median_px = compute_speed_stats(speeds_px)
    tortuosity = (
        compute_tortuosity(dist_px, initial_pos, final_pos)
        if initial_pos and final_pos
        else 0.0
    )

    return {
        "distance_px": dist_px,
        "distance_cm": dist_px * conv,
        "speed_mean_px": speed_mean_px,
        "speed_mean_cm": speed_mean_cm,
        "speed_median_px": speed_median_px,
        "speed_median_cm": speed_median_cm,
        "speed_max_px": compute_speed_max(speeds_px),
        "speed_max_cm": compute_speed_max(speeds_cm),
        "immobility_seconds": compute_immobility_seconds(speeds_cm, immobility_threshold_cm),
        "path_tortuosity": tortuosity,
        "thigmotaxis_pct": compute_thigmotaxis_pct(nframe_peripheral, nframe_detected),
        "speeds_cm": speeds_cm,
        "conv": conv,
    }
