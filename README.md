# Mouse Tracker

Automated mouse locomotor activity tracking from video. Computes distance traveled, speed profile, speed distribution, and an occupancy heatmap. Designed for biological experiments using open-field or home-cage recordings.

## Requirements

- Python 3.6+
- OpenCV (`cv2`)
- numpy
- matplotlib
- seaborn

## Installation

```bash
git clone <repo-url> && cd mouse-tracker
pip install opencv-python imutils numpy matplotlib seaborn
```

## Usage

```bash
python3 mouse_tracker.py -v <video> -c <cage_side_cm> [options]
```

### Arguments

| Argument | Description |
|----------|-------------|
| `-v`, `--video` | Path to the video file (required) |
| `-c`, `--calibrate` | Cage side length in cm. Enables interactive pixel-to-cm calibration (required for real-world units) |
| `-st`, `--start-time` | Start time in seconds (default: 0) |
| `-et`, `--end-time` | End time in seconds (default: end of video) |
| `-th`, `--threshold` | Motion detection threshold (default: 80). Lower = more sensitive |
| `-a`, `--min-area` | Minimum contour area in pixels to consider as mouse (default: 250) |
| `-roi`, `--roi` | Enable region-of-interest (ROI) selection for zone analysis |
| `-sp`, `--speed-profile` | Output file path for the speed profile plot |
| `-sd`, `--speed-distribution` | Output file path for the speed distribution histogram |
| `-hm`, `--heatmap` | Output file path for the occupancy heatmap |

### Calibration

When `-c` is provided, a calibration window opens on the first frame:

1. Click the **4 corners of the cage in clockwise order**
2. Red numbered dots and blue side lines appear with pixel distances
3. Press **SPACE** to confirm or **ESC** to reset
4. The script computes `px_per_10cm = (average side in px / cage side in cm) × 10`

If `-c` is omitted, all values remain in pixels.

### ROI mode

With `-roi`, you can select one or more rectangular zones of interest. The script reports the time (in seconds) the mouse spent inside each ROI.

After calibration, you will be prompted to:

1. **Select a valid region** — draw a rectangle around the cage area to exclude outside movement
2. **Select ROI(s)** — draw one or more rectangles for zone-specific analysis (press ENTER after each, ESC or right-click when done)

### Example

```bash
python3 mouse_tracker.py -v experiment.avi -c 40 -st 10 -et 300 -th 100 -a 200 \
  -sp speed_profile.png -sd speed_distribution.png -hm heatmap.png
```

## Output

### Console

- Total distance traveled (px and cm)
- Mean speed (px/s and cm/s)
- Median speed (px/s and cm/s)
- Time spent in each ROI (seconds)

### Plots

- **Speed Profile** — instantaneous speed over time with mean and median lines
- **Speed Distribution** — histogram of speed values
- **Occupancy Heatmap** — spatial distribution of time spent, overlaid on the background
