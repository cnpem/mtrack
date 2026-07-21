# Dev-only seed for the Locomo screens. Run with:
#
#     mix run priv/repo/seeds_locomo.exs
#
# Creates (idempotently) a confirmed demo user with a password plus one fully
# populated experiment — subjects, a shared calibration, ROIs, and videos in
# every status (done/processing/pending/error), with a tracking result + per-zone
# times for the done video — so the Experiments list, Detail and Processing
# screens have real data to render. Safe to re-run: it no-ops if the demo user
# already exists.

alias MouseTracker.Accounts
alias MouseTracker.Accounts.Scope
alias MouseTracker.Experiments

demo_email = "demo@locomo.dev"
demo_password = "locomo-demo-123!"

user =
  case Accounts.get_user_by_email(demo_email) do
    nil ->
      {:ok, user} =
        Accounts.register_user(%{
          email: demo_email,
          name: "Demo User",
          institution: "Locomo Labs",
          password: demo_password
        })

      IO.puts("Created demo user #{demo_email} / #{demo_password}")
      user

    existing ->
      IO.puts("Demo user #{demo_email} already exists — skipping seed.")
      existing
  end

scope = Scope.for_user(user)

# Bail out if this user already has the demo experiment (keeps re-runs clean).
if Enum.any?(Experiments.list_experiments(scope), &(&1.name == "Open Field — pilot")) do
  IO.puts("Demo experiment already present — nothing to do.")
else
  {:ok, calibration} =
    Experiments.create_calibration(scope, %{
      name: "Open field 60cm",
      cage_side_cm: 60.0,
      px_per_10cm: 42.0,
      threshold: 80,
      min_area: 250,
      valid_region_x: 40,
      valid_region_y: 30,
      valid_region_w: 560,
      valid_region_h: 420
    })

  {:ok, roi_center} =
    Experiments.create_roi(scope, %{
      name: "Center",
      shape: "rectangle",
      x: 210,
      y: 160,
      w: 220,
      h: 180
    })

  {:ok, roi_zone} =
    Experiments.create_roi(scope, %{
      name: "Corner target",
      shape: "circle",
      x: 90,
      y: 90,
      radius: 55
    })

  {:ok, experiment} =
    Experiments.create_experiment(scope, %{
      name: "Open Field — pilot",
      description: "Locomotion pilot, 4 videos across processing states."
    })

  {:ok, subject_a} =
    Experiments.create_subject(scope, %{
      name: "M-01",
      sex: "M",
      age_days: 70,
      weight_g: 28.5,
      genotype: "WT"
    })

  {:ok, subject_b} =
    Experiments.create_subject(scope, %{
      name: "M-02",
      sex: "F",
      age_days: 72,
      weight_g: 24.1,
      genotype: "KO"
    })

  videos = [
    {"m01_openfield.mp4", "done", subject_a},
    {"m02_openfield.mp4", "processing", subject_b},
    {"m03_openfield.mp4", "pending", subject_a},
    {"m04_openfield.mp4", "error", subject_b}
  ]

  created =
    for {filename, status, subject} <- videos do
      {:ok, video} =
        Experiments.create_video(experiment, %{
          filename: filename,
          filepath: "priv/static/uploads/demo/#{filename}",
          fps: 30,
          duration_seconds: 300.0,
          subject_id: subject.id,
          calibration_id: calibration.id
        })

      :ok = Experiments.attach_roi_to_video(video, roi_center)
      :ok = Experiments.attach_roi_to_video(video, roi_zone)
      {:ok, video} = Experiments.update_video(video, %{status: status})
      video
    end

  # Give the "done" video a tracking result + per-zone times so its Results
  # button (and future Results screen) has something real to show.
  done_video = Enum.find(created, &(&1.status == "done"))

  {:ok, result} =
    Experiments.create_tracking_result(done_video, %{
      distance_px: 128_430.0,
      distance_cm: 3058.0,
      speed_mean_px: 12.4,
      speed_mean_cm: 2.95,
      speed_median_px: 9.8,
      speed_median_cm: 2.33,
      speed_max_px: 61.0,
      speed_max_cm: 14.5,
      thigmotaxis_pct: 63.2,
      immobility_seconds: 41.0,
      path_tortuosity: 3.7,
      processed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })

  {:ok, _} = Experiments.create_roi_time(roi_center, result, %{frame_count: 2100, seconds: 70.0})
  {:ok, _} = Experiments.create_roi_time(roi_zone, result, %{frame_count: 540, seconds: 18.0})

  IO.puts("Seeded experiment '#{experiment.name}' with #{length(created)} videos.")
  IO.puts("Log in at /users/log-in as #{demo_email} / #{demo_password}")
end
