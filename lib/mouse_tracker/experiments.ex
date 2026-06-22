defmodule MouseTracker.Experiments do
  import Ecto.Query
  alias MouseTracker.Repo
  alias MouseTracker.Accounts.Scope

  alias MouseTracker.Experiments.{
    Experiment,
    Video,
    Calibration,
    Roi,
    TrackingResult
  }

  # --- Experiments ---

  def list_experiments(%Scope{user: user}) do
    Repo.all(from e in Experiment, where: e.user_id == ^user.id, order_by: [desc: e.inserted_at])
  end

  def get_experiment!(%Scope{user: user}, id) do
    Repo.get_by!(Experiment, id: id, user_id: user.id)
  end

  def create_experiment(%Scope{user: user}, attrs) do
    %Experiment{user_id: user.id}
    |> Experiment.changeset(attrs)
    |> Repo.insert()
  end

  def update_experiment(%Scope{}, %Experiment{} = experiment, attrs) do
    experiment
    |> Experiment.changeset(attrs)
    |> Repo.update()
  end

  def delete_experiment(%Scope{}, %Experiment{} = experiment) do
    Repo.delete(experiment)
  end

  def change_experiment(%Experiment{} = experiment, attrs \\ %{}) do
    Experiment.changeset(experiment, attrs)
  end

  # --- Videos ---

  def list_videos(%Experiment{} = experiment) do
    Repo.all(from v in Video, where: v.experiment_id == ^experiment.id)
  end

  def get_video!(id), do: Repo.get!(Video, id)

  def create_video(%Experiment{} = experiment, attrs) do
    %Video{experiment_id: experiment.id}
    |> Video.changeset(attrs)
    |> Repo.insert()
  end

  def update_video(%Video{} = video, attrs) do
    video
    |> Video.changeset(attrs)
    |> Repo.update()
  end

  def change_video(%Video{} = video, attrs \\ %{}) do
    Video.changeset(video, attrs)
  end

  # --- Calibrations ---

  def list_calibrations(%Scope{user: user}) do
    Repo.all(from c in Calibration, where: c.user_id == ^user.id)
  end

  def get_calibration!(%Scope{user: user}, id) do
    Repo.get_by!(Calibration, id: id, user_id: user.id)
  end

  def create_calibration(%Scope{user: user}, attrs) do
    %Calibration{user_id: user.id}
    |> Calibration.changeset(attrs)
    |> Repo.insert()
  end

  def change_calibration(%Calibration{} = calibration, attrs \\ %{}) do
    Calibration.changeset(calibration, attrs)
  end

  # --- ROIs ---

  def list_rois(%Video{} = video) do
    Repo.all(from r in Roi, where: r.video_id == ^video.id)
  end

  def create_roi(%Video{} = video, attrs) do
    %Roi{video_id: video.id}
    |> Roi.changeset(attrs)
    |> Repo.insert()
  end

  def change_roi(%Roi{} = roi, attrs \\ %{}) do
    Roi.changeset(roi, attrs)
  end

  # --- Tracking Results ---

  def get_tracking_result_for_video(%Video{} = video) do
    Repo.get_by(TrackingResult, video_id: video.id)
  end

  def create_tracking_result(%Video{} = video, attrs) do
    %TrackingResult{video_id: video.id}
    |> TrackingResult.changeset(attrs)
    |> Repo.insert()
  end
end
