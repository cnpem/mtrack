"""
detector.py
Responsible for: motion detection pipeline.
Converts raw video frames into a binary motion mask.
"""

import cv2
import numpy as np


def get_background(first_frame):
    """
    Build a blurred grayscale background model from the first frame.
    The caller is responsible for reading the frame beforehand.
    """
    bg = first_frame.copy()
    bg = cv2.cvtColor(bg, cv2.COLOR_BGR2GRAY)
    bg = cv2.GaussianBlur(bg, (21, 21), 0)
    return bg


def diff_btw_frames(frame, background):
    """
    Compute the absolute pixel difference between *frame* and the
    pre-computed *background* (both expected to be grayscale after blurring
    is applied internally to *frame*).
    """
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    gray = cv2.GaussianBlur(gray, (21, 21), 0)
    return cv2.absdiff(background, gray)


def exclude_invalid_region(img, valid_region):
    """
    Zero-out every pixel outside *valid_region* (x, y, w, h).
    Returns a new image of the same shape with the invalid area masked.
    """
    x0, y0 = valid_region[0], valid_region[1]
    x1, y1 = x0 + valid_region[2], y0 + valid_region[3]

    mask = np.zeros(img.shape, np.uint8)
    mask[y0:y1, x0:x1] = img[y0:y1, x0:x1]
    return mask


def apply_threshold(frame_delta, threshold):
    """
    Apply a binary threshold to *frame_delta* and dilate to fill holes.
    Returns the resulting binary mask.
    """
    thresh = cv2.threshold(frame_delta, threshold, 255, cv2.THRESH_BINARY)[1]
    return cv2.dilate(thresh, None, iterations=5)
