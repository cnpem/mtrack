"""
render.py
Responsible for: all visual output.
  - Interactive OpenCV windows (ROI selection, valid region, calibration)
  - Matplotlib/Seaborn plot generation and saving
"""

import cv2
import numpy as np
from matplotlib import pyplot as plt
import seaborn as sns

from .metrics import distance


# ---------------------------------------------------------------------------
# Interactive setup windows (OpenCV)
# ---------------------------------------------------------------------------


def select_roi(frame):
    """
    Open an OpenCV window for the user to draw one or more ROIs.
    Returns a list of (x, y, w, h) tuples.
    """
    tmp = frame.copy()
    rois = cv2.selectROIs("ROI Select", tmp, True, False)
    cv2.destroyWindow("ROI Select")

    for i, r in enumerate(rois, start=1):
        cv2.rectangle(tmp, (r[0], r[1]), (r[0] + r[2], r[1] + r[3]), (0, 0, 255), 2)
        cv2.putText(
            tmp,
            "ROI {}".format(i),
            (r[0] + 5, r[1] + 20),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.5,
            (0, 0, 255),
            2,
        )

    cv2.imshow("ROI", tmp)
    return rois


def select_valid_region(frame):
    """
    Open an OpenCV window for the user to draw the valid analysis region.
    Returns the last drawn region as a single (x, y, w, h) tuple.
    """
    tmp = frame.copy()
    rois = cv2.selectROIs("Select Valid Region", tmp, False, False)
    cv2.destroyWindow("Select Valid Region")

    r = rois[-1]
    cv2.rectangle(tmp, (r[0], r[1]), (r[0] + r[2], r[1] + r[3]), (0, 0, 255), 2)
    cv2.putText(
        tmp,
        "Valid Region",
        (r[0] + 5, r[1] + 20),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.5,
        (0, 0, 255),
        2,
    )
    cv2.imshow("ROI", tmp)
    return r


def calibrate(frame, cage_side_cm):
    """
    Interactive calibration: the user clicks the 4 corners of the cage.
    Returns px_per_10cm (float) — the pixel-to-centimetre conversion factor.
    """
    points = []
    window_name = "Calibrate"

    def draw_overlay(pts):
        display = frame.copy()
        for i, pt in enumerate(pts):
            cv2.circle(display, pt, 6, (0, 0, 255), -1)
            cv2.putText(
                display,
                str(i + 1),
                (pt[0] + 10, pt[1] + 10),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.7,
                (0, 0, 255),
                2,
            )
            if i > 0:
                d = distance(pts[i - 1], pt)
                cv2.line(display, pts[i - 1], pt, (255, 0, 0), 2)
                mid = ((pts[i - 1][0] + pt[0]) // 2, (pts[i - 1][1] + pt[1]) // 2)
                cv2.putText(
                    display,
                    "{:.0f} px".format(d),
                    mid,
                    cv2.FONT_HERSHEY_SIMPLEX,
                    0.5,
                    (255, 0, 0),
                    2,
                )
        if len(pts) == 4:
            d = distance(pts[3], pts[0])
            cv2.line(display, pts[3], pts[0], (255, 0, 0), 2)
            mid = ((pts[3][0] + pts[0][0]) // 2, (pts[3][1] + pts[0][1]) // 2)
            cv2.putText(
                display,
                "{:.0f} px".format(d),
                mid,
                cv2.FONT_HERSHEY_SIMPLEX,
                0.5,
                (255, 0, 0),
                2,
            )
        return display

    def mouse_callback(event, x, y, flags, param):
        nonlocal points
        if event == cv2.EVENT_LBUTTONDOWN and len(points) < 4:
            points.append((x, y))
            cv2.imshow(window_name, draw_overlay(points))

    cv2.namedWindow(window_name)
    cv2.setMouseCallback(window_name, mouse_callback)
    cv2.imshow(window_name, frame)
    print("Click the 4 corners of the cage in clockwise order, then press SPACE") # Pensar se cage por ter mais de 4 pontos, ou ter um centro e um raio

    while True:
        key = cv2.waitKey(0) & 0xFF
        if key == ord(" ") and len(points) == 4:
            sides = [
                distance(points[0], points[1]),
                distance(points[1], points[2]),
                distance(points[2], points[3]),
                distance(points[3], points[0]),
            ]
            avg_px = sum(sides) / 4
            px_per_10cm = (avg_px / cage_side_cm) * 10
            print("Calibration:")
            for i, s in enumerate(sides):
                print("  Side {}: {:.2f} px".format(i + 1, s))
            print("  Average side: {:.2f} px".format(avg_px))
            print("  Cage side: {} cm".format(cage_side_cm))
            print("  px_per_10cm: {:.2f}".format(px_per_10cm))
            cv2.destroyWindow(window_name)
            return px_per_10cm
        elif key == 27:
            points = []
            cv2.imshow(window_name, frame)
            print("Points reset. Click the 4 corners again.")


# ---------------------------------------------------------------------------
# Plot generation (Matplotlib / Seaborn)
# ---------------------------------------------------------------------------


def plot_heatmap(heatmap, fps, background, max_time, fn_plot):
    """Save an occupancy heatmap overlaid on the background image."""
    plt.figure()
    heatmap[0, 0] = max_time
    plt.imshow(background, cmap="gray")
    im = plt.imshow(heatmap / fps, cmap="nipy_spectral", alpha=0.85)
    cbar = plt.colorbar(im, orientation="vertical")
    cbar.ax.set_ylabel("seconds")
    plt.title("Occupancy Heatmap")
    plt.axis("off")
    plt.savefig(fn_plot)
    plt.close()


def plot_speed_profile(speeds_cm, speed_mean_cm, speed_median_cm, max_speed, fn_plot):
    """Save a speed-over-time line plot with mean/median reference lines."""
    sns.set_style("darkgrid")
    plt.figure()
    plt.plot(speeds_cm)
    plt.axhline(
        y=speed_mean_cm,
        color="r",
        linestyle="--",
        label="mean: {:.2f} cm/s".format(speed_mean_cm),
    )
    plt.axhline(
        y=speed_median_cm,
        color="g",
        linestyle=":",
        label="median: {:.2f} cm/s".format(speed_median_cm),
    )
    plt.title("Speed Profile")
    plt.xlabel("Time (s)")
    plt.ylabel("Speed (cm/s)")
    plt.ylim(0, max_speed)
    plt.legend()
    plt.savefig(fn_plot)
    plt.close()


def plot_speed_distribution(speeds_cm, max_speed, fn_plot):
    """Save a histogram of speed values."""
    plt.figure()
    sns.histplot(speeds_cm, bins=20)
    plt.title("Speed Distribution")
    plt.xlabel("Speed (cm/s)")
    plt.ylabel("Frequency")
    plt.xlim(0, max_speed)
    plt.ylim(0, 300)
    plt.savefig(fn_plot)
    plt.close()
