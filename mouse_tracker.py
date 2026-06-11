#!/home/jgcarvalho/anaconda3/bin/python3

# USAGE
# version: 0.3
# python3 mouse_tracker.py -v 2018-06-18-145225.wmv -c 40 -st 200 -th 120 -a 250 -sp perfil.png -sd dist.png -hm heat.png
# requirements: install imutils and opencv

# changes v0.2
# selection of a valid region


# import the necessary packages
from imutils.video import VideoStream
import argparse
import cv2
import numpy as np
from math import sqrt
from matplotlib import pyplot as plt
import seaborn as sns


def video(fn):
    return cv2.VideoCapture(fn)


def video_length(vs):
    return vs.get(cv2.CAP_PROP_FRAME_COUNT)


def video_fps(vs):
    return vs.get(cv2.CAP_PROP_FPS)


def get_background(ff):
    # read has side effect
    # ff = vs.read()[1]
    bg = ff.copy()
    bg = cv2.cvtColor(bg, cv2.COLOR_BGR2GRAY)
    bg = cv2.GaussianBlur(bg, (21, 21), 0)
    return bg


def skip_frames(vs, n_frames):
    for i in range(n_frames):
        # _ = vs.read()
        _ = vs.grab()


def diff_btw_frames(frame, fst_frame):
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    gray = cv2.GaussianBlur(gray, (21, 21), 0)
    return cv2.absdiff(fst_frame, gray)


def exclude_invalid_region(img, valid_region):
    x0 = valid_region[0]
    y0 = valid_region[1]
    x1 = x0 + valid_region[2]
    y1 = y0 + valid_region[3]

    mask = np.zeros(img.shape, np.uint8)
    mask[y0:y1, x0:x1] = img[y0:y1, x0:x1]
    return mask


def apply_threshold(frm_delta, threshold):
    thresh = cv2.threshold(frm_delta, threshold, 255, cv2.THRESH_BINARY)[1]
    return cv2.dilate(thresh, None, iterations=5)


def plot_heatmap(heatmap, fps, background, max_time, fn_plot):
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


def select_roi(frame):
    tmp = frame.copy()
    # Select ROI
    rois = cv2.selectROIs("ROI Select", tmp, True, False)
    cv2.destroyWindow("ROI Select")
    # Show ROI
    i = 1
    for r in rois:
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
        i += 1

    cv2.imshow("ROI", tmp)
    return rois


def select_valid_region(frame):
    tmp = frame.copy()
    # Select ROI
    rois = cv2.selectROIs("Select Valid Region", tmp, False, False)
    cv2.destroyWindow("Select Valid Region")
    # Get only the last ROI as valid region
    r = rois[-1]
    # Show ROI
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
    # return rois[-1]
    return r


def distance(pt0, pt1):
    return sqrt((pt1[0] - pt0[0]) ** 2 + (pt1[1] - pt0[1]) ** 2)


def is_pt_into_roi(pt, roi):
    return (
        pt[0] > roi[0]
        and pt[0] < (roi[0] + roi[2])
        and pt[1] > roi[1]
        and pt[1] < (roi[1] + roi[3])
    )


def process(vs, bg, valid_region, threshold, min_area, rois, len_frames):
    heatmap = None
    _pos_prev = None
    _t_prev = 0
    _t_pos = 0
    _dist = 0.0
    dist_total = 0.0
    speeds = []
    s0 = None
    s1 = None
    t0 = 0
    t1 = 0
    fps = video_fps(vs)
    nframe_into_roi = [0] * len(rois)

    if len_frames > 0:
        use_length = True
    else:
        use_length = False

    while True:
        frame = vs.read()[1]
        # frame = imutils.resize(frame, width=500)
        if frame is None:
            break

        if use_length:
            if len_frames <= 0:
                break
            else:
                len_frames -= 1

        frameDelta = diff_btw_frames(frame, bg)
        frameDelta = exclude_invalid_region(frameDelta, valid_region)
        cv2.imshow("Frame Delta", frameDelta)
        thresh = apply_threshold(frameDelta, threshold)
        #
        # # dilate the thresholded image to fill in holes, then find contours
        # # on thresholded image
        #
        cnts = cv2.findContours(
            thresh.copy(), cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE
        )
        #
        # print(f"length cnts {len(cnts)}")
        cnts = cnts[0]  # if imutils.is_cv2() else cnts[1] # this test wasn't working
        #
        # # loop over the contours
        for c in cnts:
            #     # if the contour is too small, ignore it
            #
            if cv2.contourArea(c) < min_area:
                continue
            #     # compute the bounding box for the contour, draw it on the frame,
            (x, y, w, h) = cv2.boundingRect(c)
            cv2.rectangle(frame, (x, y), (x + w, y + h), (0, 255, 0), 2)
            #
            #     # if number of countours == 1
            if len(cnts) == 1:
                _pos_curr = (x + w / 2, y + h / 2)
                _t_pos += 1
                # position time step
                if _t_pos >= 5:
                    if _pos_prev != None:
                        _dist = distance(_pos_prev, _pos_curr)
                        # dist threshold
                        if _dist > 5:
                            dist_total += _dist
                            # point green and distance accumulated
                            cv2.rectangle(
                                frame,
                                (int(_pos_curr[0] - 1), int(_pos_curr[1] - 1)),
                                (int(_pos_curr[0] + 1), int(_pos_curr[1] + 1)),
                                (0, 255, 0),
                                2,
                            )
                        else:
                            # point red
                            cv2.rectangle(
                                frame,
                                (int(_pos_curr[0] - 1), int(_pos_curr[1] - 1)),
                                (int(_pos_curr[0] + 1), int(_pos_curr[1] + 1)),
                                (0, 0, 255),
                                2,
                            )
                    _pos_prev = _pos_curr
                    _t_pos = 0
                    # print("center: {} {}, distance: {}".format(_pos_curr[0], _pos_curr[1], _dist))

                # speed
                s1 = _pos_curr
                t1 += 1
                if s0 == None:
                    s0 = _pos_curr

                if t1 - t0 >= fps:
                    speeds.append(distance(s1, s0))
                    t0 += fps
                    s0 = s1

                # time (frames) into roi
                for i in range(len(rois)):
                    if is_pt_into_roi(_pos_curr, rois[i]):
                        nframe_into_roi[i] += 1

            else:
                _t_pos += 1

        # draw the text and timestamp on the frame
        # cv2.putText(
        #     frame,
        #     "Room Status: {}".format(text),
        #     (10, 20),
        #     cv2.FONT_HERSHEY_SIMPLEX,
        #     0.5,
        #     (0, 0, 255),
        #     2,
        # )
        # cv2.putText(
        #     frame,
        #     datetime.datetime.now().strftime("%A %d %B %Y %I:%M:%S%p"),
        #     (10, frame.shape[0] - 10),
        #     cv2.FONT_HERSHEY_SIMPLEX,
        #     0.35,
        #     (0, 0, 255),
        #     1,
        # )

        cv2.imshow("Video", frame)
        cv2.imshow("Thresh", thresh)
        #
        if heatmap is None:
            # initialize heatmap
            heatmap = thresh / 255
        else:
            # heatmap iterative mean (can be plotted at runtime)
            # heatmap = heatmap + 1/(t+1)*(thresh/255-heatmap)
            heatmap += thresh / 255

        key = cv2.waitKey(1) & 0xFF

        # if the `q` key is pressed, break from the lop
        if key == ord("q"):
            break
    # vs.stop() if args.get("video", None) is None else vs.release()
    # cv2.destroyAllWindows()

    return heatmap, dist_total, nframe_into_roi, speeds


def calibrate(frame, cage_side_cm):
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
    print("Click the 4 corners of the cage in clockwise order, then press SPACE")

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


def main():
    # construct the argument parser and parse the arguments
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

    vs = video(args["video"])
    # length = video_length(vs)
    fps = video_fps(vs)
    # get first frame
    ff = vs.read()[1]
    bg = get_background(ff)
    valid_region = select_valid_region(ff)

    if args["calibrate"]:
        px_per_10cm = calibrate(ff, args["calibrate"])
    else:
        px_per_10cm = 1.0

    rois = []
    if args["roi"]:
        rois = select_roi(ff)

    skip_frames(vs, int(args["start_time"] * fps))
    len_frames = (int(args["end_time"]) - int(args["start_time"])) * fps

    heatmap, distance, frames_into_roi, speeds = process(
        vs, bg, valid_region, args["threshold"], args["min_area"], rois, len_frames
    )
    conv = 10.0 / px_per_10cm

    distance_cm = distance * conv
    speeds_cm = [s * conv for s in speeds]
    speed_mean_cm = np.mean(speeds_cm)
    speed_median_cm = np.median(speeds_cm)
    speed_mean_px = np.mean(speeds)
    speed_median_px = np.median(speeds)

    print("Distance: {:.2f} px ({:.2f} cm)".format(distance, distance_cm))
    print("Speed mean: {:.2f} px/s ({:.2f} cm/s)".format(speed_mean_px, speed_mean_cm))
    print(
        "Speed median: {:.2f} px/s ({:.2f} cm/s)".format(
            speed_median_px, speed_median_cm
        )
    )
    print("# frames into ROI {}".format(frames_into_roi))
    for i in range(len(frames_into_roi)):
        print("Time into ROI {}: {} seconds".format(i + 1, frames_into_roi[i] / fps))

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
    # max_speed = max(speeds_cm) if speeds_cm else 1
    max_speed = 300 * conv if speeds_cm else 300
    plt.ylim(0, max_speed)
    plt.legend()
    plt.savefig(args["speed_profile"])
    plt.close()

    plt.figure()
    sns.histplot(speeds_cm, bins=20)
    plt.title("Speed Distribution")
    plt.xlabel("Speed (cm/s)")
    plt.ylabel("Frequency")
    plt.xlim(0, max_speed)
    plt.ylim(0, 300)
    plt.savefig(args["speed_distribution"])
    plt.close()

    sns.set_style("white")
    heatmap_max_time = 120
    plot_heatmap(heatmap, fps, bg, heatmap_max_time * fps, args["heatmap"])
    cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
