defmodule MouseTracker.Workers.OrphanUploadCleanupWorkerTest do
  use MouseTracker.DataCase, async: true

  import MouseTracker.AccountsFixtures
  import MouseTracker.ExperimentsFixtures

  alias MouseTracker.Workers.OrphanUploadCleanupWorker

  setup do
    base =
      Path.join(System.tmp_dir!(), "orphan_cleanup_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(base)
    on_exit(fn -> File.rm_rf!(base) end)
    %{base: base}
  end

  defp write_token_dir(base, subpath, token, files, mtime) do
    dir = Path.join([base, subpath, token])
    File.mkdir_p!(dir)
    Enum.each(files, &File.write!(Path.join(dir, &1), "x"))
    if mtime, do: File.touch!(dir, mtime)
    dir
  end

  defp hours_ago(hours) do
    NaiveDateTime.utc_now()
    |> NaiveDateTime.add(-trunc(hours * 3600), :second)
    |> NaiveDateTime.to_erl()
  end

  defp perform(base, extra_args \\ %{}) do
    args = Map.merge(%{"uploads_base_dir" => base, "max_age_hours" => 24}, extra_args)
    OrphanUploadCleanupWorker.perform(%Oban.Job{args: args})
  end

  test "deletes an orphaned old token (both video and frame dirs)", %{base: base} do
    token = Ecto.UUID.generate()
    video_dir = write_token_dir(base, "videos", token, ["a.mp4"], hours_ago(48))
    frame_dir = write_token_dir(base, "frames", token, ["a.png"], hours_ago(48))

    assert perform(base) == :ok

    refute File.exists?(video_dir)
    refute File.exists?(frame_dir)
  end

  test "preserves a fresh/in-progress token", %{base: base} do
    token = Ecto.UUID.generate()
    video_dir = write_token_dir(base, "videos", token, ["a.mp4"], hours_ago(1))
    frame_dir = write_token_dir(base, "frames", token, ["a.png"], hours_ago(1))

    assert perform(base) == :ok

    assert File.exists?(video_dir)
    assert File.exists?(frame_dir)
  end

  test "claimed token: deletes frames but preserves video files regardless of age", %{base: base} do
    token = Ecto.UUID.generate()
    video_dir = write_token_dir(base, "videos", token, ["clip.mp4"], hours_ago(48))
    frame_dir = write_token_dir(base, "frames", token, ["clip.png"], hours_ago(48))

    user = user_fixture()
    experiment = experiment_fixture(user)
    video_fixture(experiment, nil, %{filepath: Path.join(video_dir, "clip.mp4")})

    assert perform(base) == :ok

    assert File.exists?(video_dir)
    refute File.exists?(frame_dir)
  end

  test "claimed token, both dirs fresh: nothing deleted, no crash", %{base: base} do
    token = Ecto.UUID.generate()
    video_dir = write_token_dir(base, "videos", token, ["clip.mp4"], hours_ago(1))
    frame_dir = write_token_dir(base, "frames", token, ["clip.png"], hours_ago(1))

    user = user_fixture()
    experiment = experiment_fixture(user)
    video_fixture(experiment, nil, %{filepath: Path.join(video_dir, "clip.mp4")})

    assert perform(base) == :ok

    assert File.exists?(video_dir)
    assert File.exists?(frame_dir)
  end

  test "missing base/videos/frames directories does not raise", %{base: base} do
    missing_base = Path.join(base, "does_not_exist")

    assert perform(missing_base) == :ok
  end

  test "token present only under frames/ is deleted without error", %{base: base} do
    token = Ecto.UUID.generate()
    frame_dir = write_token_dir(base, "frames", token, ["a.png"], hours_ago(48))

    assert perform(base) == :ok

    refute File.exists?(frame_dir)
  end

  test "max_age_hours job-arg override is respected", %{base: base} do
    token = Ecto.UUID.generate()
    video_dir = write_token_dir(base, "videos", token, ["a.mp4"], hours_ago(2))

    assert perform(base, %{"max_age_hours" => 1}) == :ok
    refute File.exists?(video_dir)

    token2 = Ecto.UUID.generate()
    video_dir2 = write_token_dir(base, "videos", token2, ["a.mp4"], hours_ago(2))

    assert perform(base, %{"max_age_hours" => 24}) == :ok
    assert File.exists?(video_dir2)
  end

  test "processes multiple unrelated tokens independently in one run", %{base: base} do
    orphan_old_token = Ecto.UUID.generate()
    orphan_old_dir = write_token_dir(base, "videos", orphan_old_token, ["a.mp4"], hours_ago(48))

    fresh_token = Ecto.UUID.generate()
    fresh_dir = write_token_dir(base, "videos", fresh_token, ["a.mp4"], hours_ago(1))

    claimed_token = Ecto.UUID.generate()
    claimed_dir = write_token_dir(base, "videos", claimed_token, ["clip.mp4"], hours_ago(48))

    user = user_fixture()
    experiment = experiment_fixture(user)
    video_fixture(experiment, nil, %{filepath: Path.join(claimed_dir, "clip.mp4")})

    assert perform(base) == :ok

    refute File.exists?(orphan_old_dir)
    assert File.exists?(fresh_dir)
    assert File.exists?(claimed_dir)
  end
end
