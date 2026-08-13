defmodule MouseTracker.ExperimentsWizardTest do
  use MouseTracker.DataCase

  alias MouseTracker.Experiments
  alias MouseTracker.Experiments.{Rois, Subjects}
  alias MouseTracker.Accounts.Scope

  import MouseTracker.AccountsFixtures

  setup do
    user = user_fixture()
    %{user: user, scope: Scope.for_user(user)}
  end

  defp cal_params do
    %{
      "cage_side_cm" => "30",
      "scale_cm_2" => "30",
      "px_per_10cm" => "50",
      "threshold" => "80",
      "min_area" => "250",
      "peripheral_pct" => "20",
      "immobility_threshold_cm" => "2",
      "valid_region_x" => "0",
      "valid_region_y" => "0",
      "valid_region_w" => "100",
      "valid_region_h" => "100",
      "coordinate_x1" => "0",
      "coordinate_y1" => "0",
      "coordinate_x2" => "50",
      "coordinate_y2" => "0",
      "coordinate_x3" => "0",
      "coordinate_y3" => "10",
      "coordinate_x4" => "50",
      "coordinate_y4" => "10"
    }
  end

  defp roi_params(name) do
    %{"name" => name, "shape" => "rectangle", "x" => "10", "y" => "10", "w" => "20", "h" => "20"}
  end

  describe "create_experiment_with_videos/2" do
    test "creates experiment, subjects, shared calibration/ROIs and videos", %{scope: scope} do
      payload = %{
        name: "Batch A",
        calibrations: %{"r1" => cal_params()},
        rois: %{"r1" => [roi_params("Center")]},
        videos: [
          %{
            filename: "a.mp4",
            filepath: "/tmp/a.mp4",
            subject_ref: {:new, "M-01", "Control"},
            cal_ref: "r1",
            roi_ref: "r1"
          },
          %{
            filename: "b.mp4",
            filepath: "/tmp/b.mp4",
            subject_ref: {:new, "M-02", nil},
            cal_ref: "r1",
            roi_ref: "r1"
          }
        ]
      }

      assert {:ok, {experiment, [v1, v2]}} =
               Experiments.create_experiment_with_videos(scope, payload)

      assert experiment.name == "Batch A"

      # Both videos share the single reference calibration.
      assert v1.calibration_id == v2.calibration_id
      refute is_nil(v1.calibration_id)

      # ROI is attached to both videos and its name is prefixed with the experiment.
      assert [%{name: "Batch A · Center"}] = Rois.list_rois_for_video(v1)
      assert [%{name: "Batch A · Center"}] = Rois.list_rois_for_video(v2)

      # One subject per distinct name.
      assert length(Subjects.list_subjects(scope)) == 2

      subjects = Subjects.list_subjects(scope)
      assert Enum.find(subjects, &(&1.name == "M-01")).group == "Control"
      assert Enum.find(subjects, &(&1.name == "M-02")).group == nil
    end

    test "persists the chosen background_frame per video, defaulting to 0", %{scope: scope} do
      payload = %{
        name: "BG batch",
        calibrations: %{"r1" => cal_params()},
        rois: %{},
        videos: [
          %{
            filename: "hand.mp4",
            filepath: "/tmp/hand.mp4",
            subject_ref: nil,
            cal_ref: "r1",
            roi_ref: nil,
            background_frame: 45
          },
          %{
            filename: "clean.mp4",
            filepath: "/tmp/clean.mp4",
            subject_ref: nil,
            cal_ref: "r1",
            roi_ref: nil
          }
        ]
      }

      assert {:ok, {_experiment, [v1, v2]}} =
               Experiments.create_experiment_with_videos(scope, payload)

      assert v1.background_frame == 45
      assert v2.background_frame == 0
    end

    test "persists the per-video analysis window, defaulting to the whole video",
         %{scope: scope} do
      payload = %{
        name: "Trim batch",
        calibrations: %{"r1" => cal_params()},
        rois: %{},
        videos: [
          %{
            filename: "trimmed.mp4",
            filepath: "/tmp/trimmed.mp4",
            subject_ref: nil,
            cal_ref: "r1",
            roi_ref: nil,
            start_time_seconds: 12.0,
            end_time_seconds: 105.0
          },
          %{
            filename: "full.mp4",
            filepath: "/tmp/full.mp4",
            subject_ref: nil,
            cal_ref: "r1",
            roi_ref: nil
          }
        ]
      }

      assert {:ok, {_experiment, [v1, v2]}} =
               Experiments.create_experiment_with_videos(scope, payload)

      assert v1.start_time_seconds == 12.0
      assert v1.end_time_seconds == 105.0
      assert v2.start_time_seconds == 0.0
      assert v2.end_time_seconds == nil
    end

    test "stores a polygon ROI with its four vertices", %{scope: scope} do
      poly = %{
        "name" => "Quad",
        "shape" => "polygon",
        "x" => "5",
        "y" => "6",
        "x1" => "5",
        "y1" => "6",
        "x2" => "40",
        "y2" => "6",
        "x3" => "40",
        "y3" => "30",
        "x4" => "5",
        "y4" => "30"
      }

      payload = %{
        name: "Poly batch",
        calibrations: %{"r1" => cal_params()},
        rois: %{"r1" => [poly]},
        videos: [
          %{
            filename: "a.mp4",
            filepath: "/tmp/a.mp4",
            subject_ref: nil,
            cal_ref: "r1",
            roi_ref: "r1"
          }
        ]
      }

      assert {:ok, {_experiment, [video]}} =
               Experiments.create_experiment_with_videos(scope, payload)

      assert [roi] = Rois.list_rois_for_video(video)
      assert roi.shape == "polygon"
      assert {roi.x1, roi.y1, roi.x4, roi.y4} == {5, 6, 5, 30}
    end

    test "a video with no ROI reference gets no zones", %{scope: scope} do
      payload = %{
        name: "Batch B",
        calibrations: %{"r1" => cal_params()},
        rois: %{},
        videos: [
          %{
            filename: "a.mp4",
            filepath: "/tmp/a.mp4",
            subject_ref: nil,
            cal_ref: "r1",
            roi_ref: nil
          }
        ]
      }

      assert {:ok, {_experiment, [video]}} =
               Experiments.create_experiment_with_videos(scope, payload)

      assert Rois.list_rois_for_video(video) == []
      assert is_nil(video.subject_id)
    end

    test "persists the second scale segment's raw coordinates and cm", %{scope: scope} do
      payload = %{
        name: "Batch C",
        calibrations: %{"r1" => cal_params()},
        rois: %{},
        videos: [
          %{
            filename: "a.mp4",
            filepath: "/tmp/a.mp4",
            subject_ref: nil,
            cal_ref: "r1",
            roi_ref: nil
          }
        ]
      }

      assert {:ok, {_experiment, [video]}} =
               Experiments.create_experiment_with_videos(scope, payload)

      calibration =
        MouseTracker.Repo.get!(MouseTracker.Experiments.Calibration, video.calibration_id)

      assert calibration.scale_cm_2 == 30.0
      assert {calibration.coordinate_x3, calibration.coordinate_y3} == {0, 10}
      assert {calibration.coordinate_x4, calibration.coordinate_y4} == {50, 10}
    end

    test "reuses an existing subject across separate experiments", %{scope: scope} do
      payload_a = %{
        name: "Batch D",
        calibrations: %{"r1" => cal_params()},
        rois: %{},
        videos: [
          %{
            filename: "a.mp4",
            filepath: "/tmp/a.mp4",
            subject_ref: {:new, "M-01", nil},
            cal_ref: "r1",
            roi_ref: nil
          }
        ]
      }

      assert {:ok, {_experiment_a, [video_a]}} =
               Experiments.create_experiment_with_videos(scope, payload_a)

      assert length(Subjects.list_subjects(scope)) == 1

      payload_b = %{
        name: "Batch E",
        calibrations: %{"r1" => cal_params()},
        rois: %{},
        videos: [
          %{
            filename: "b.mp4",
            filepath: "/tmp/b.mp4",
            subject_ref: {:existing, video_a.subject_id},
            cal_ref: "r1",
            roi_ref: nil
          }
        ]
      }

      assert {:ok, {_experiment_b, [video_b]}} =
               Experiments.create_experiment_with_videos(scope, payload_b)

      assert video_b.subject_id == video_a.subject_id
      assert length(Subjects.list_subjects(scope)) == 1
    end

    test "rolls back entirely on an invalid calibration", %{scope: scope} do
      payload = %{
        name: "Bad",
        calibrations: %{"r1" => %{"cage_side_cm" => "30"}},
        rois: %{},
        videos: [
          %{
            filename: "a.mp4",
            filepath: "/tmp/a.mp4",
            subject_ref: nil,
            cal_ref: "r1",
            roi_ref: nil
          }
        ]
      }

      assert {:error, _changeset} =
               Experiments.create_experiment_with_videos(scope, payload)

      assert Experiments.list_experiments(scope) == []
    end
  end
end
