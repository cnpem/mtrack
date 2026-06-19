"""
run.py
Responsible for: entry point / orchestrator.
Parses arguments, manages video setup, calls analyzer / render / metrics modules, and displays/saves outputs.
"""

import argparse
import cv2
import numpy as np

from . import detector
from . import render
from . import analyzer
from . import metrics


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

    args = vars(ap.parse_args())

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
    heatmap, dist_px, frames_into_roi, speeds_px = analyzer.process(
        vs, bg, valid_region, args["threshold"], args["min_area"], rois, len_frames
    )

    # 7. Convert pixels to metric scale (cm)
    conv = 10.0 / px_per_10cm
    distance_cm = dist_px * conv
    speeds_cm = [s * conv for s in speeds_px]
    
    speed_mean_cm, speed_median_cm = metrics.compute_speed_stats(speeds_cm)
    speed_mean_px, speed_median_px = metrics.compute_speed_stats(speeds_px)

    # 8. Print report
    print("Distance: {:.2f} px ({:.2f} cm)".format(dist_px, distance_cm))
    print("Speed mean: {:.2f} px/s ({:.2f} cm/s)".format(speed_mean_px, speed_mean_cm))
    print("Speed median: {:.2f} px/s ({:.2f} cm/s)".format(speed_median_px, speed_median_cm))
    
    print("# frames into ROI {}".format(frames_into_roi))
    for i in range(len(frames_into_roi)):
        print("Time into ROI {}: {} seconds".format(i + 1, frames_into_roi[i] / fps))

    # 9. Plotting and saving visualizations
    max_speed = 300 * conv if speeds_cm else 300

    if args["speed_profile"]:
        render.plot_speed_profile(speeds_cm, speed_mean_cm, speed_median_cm, max_speed, args["speed_profile"])

    if args["speed_distribution"]:
        render.plot_speed_distribution(speeds_cm, max_speed, args["speed_distribution"])

    if args["heatmap"]:
        heatmap_max_time = 120
        render.plot_heatmap(heatmap, fps, bg, heatmap_max_time * fps, args["heatmap"])

    cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
