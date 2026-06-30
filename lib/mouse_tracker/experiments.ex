defmodule MouseTracker.Experiments do
  import Ecto.Query
  alias MouseTracker.Repo
  alias MouseTracker.Accounts.Scope

  alias MouseTracker.Experiments.{
    Experiment,
    Video,
    Calibration,
    Roi,
    RoiTime,
    TrackingResult,
    Subject
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

  def delete_video(%Video{} = video), do: Repo.delete(video)

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

  def update_calibration(%Calibration{} = calibration, attrs) do
    calibration
    |> Calibration.changeset(attrs)
    |> Repo.update()
  end

  def delete_calibration(%Calibration{} = calibration), do: Repo.delete(calibration)

  def change_calibration(%Calibration{} = calibration, attrs \\ %{}) do
    Calibration.changeset(calibration, attrs)
  end

  # --- ROIs ---

  def list_rois(%Video{} = video) do
    Repo.all(from r in Roi, where: r.video_id == ^video.id)
  end

  def get_roi!(%Video{} = video, id) do
    Repo.get_by!(Roi, id: id, video_id: video.id)
  end

  def create_roi(%Video{} = video, attrs) do
    %Roi{video_id: video.id}
    |> Roi.changeset(attrs)
    |> Repo.insert()
  end

  def update_roi(%Roi{} = roi, attrs) do
    roi
    |> Roi.changeset(attrs)
    |> Repo.update()
  end

  def delete_roi(%Roi{} = roi), do: Repo.delete(roi)

  def change_roi(%Roi{} = roi, attrs \\ %{}) do
    Roi.changeset(roi, attrs)
  end

  # --- RoiTimes ---

  def list_roi_times(%Roi{} = roi) do
    Repo.all(from rt in RoiTime, where: rt.roi_id == ^roi.id)
  end

  def get_roi_time!(id), do: Repo.get!(RoiTime, id)

  def create_roi_time(%Roi{} = roi, %TrackingResult{} = result, attrs) do
    %RoiTime{roi_id: roi.id, tracking_result_id: result.id}
    |> RoiTime.changeset(attrs)
    |> Repo.insert()
  end

  def change_roi_time(%RoiTime{} = roi_time, attrs \\ %{}) do
    RoiTime.changeset(roi_time, attrs)
  end

  # --- Subjects ---

  def list_subjects(%Experiment{} = experiment) do
    Repo.all(from s in Subject, where: s.experiment_id == ^experiment.id, order_by: s.name)
  end

  def get_subject!(id), do: Repo.get!(Subject, id)

  def create_subject(%Experiment{} = experiment, attrs) do
    %Subject{experiment_id: experiment.id}
    |> Subject.changeset(attrs)
    |> Repo.insert()
  end

  def update_subject(%Subject{} = subject, attrs) do
    subject
    |> Subject.changeset(attrs)
    |> Repo.update()
  end

  def delete_subject(%Subject{} = subject), do: Repo.delete(subject)

  def change_subject(%Subject{} = subject, attrs \\ %{}) do
    Subject.changeset(subject, attrs)
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
