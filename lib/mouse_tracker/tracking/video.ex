defmodule MouseTracker.Experiments.Video do
  use Ecto.Schema
  import Ecto.Changeset

  alias MouseTracker.Experiments.{Experiment, Calibration, Roi, TrackingResult, Subject}

  @valid_statuses ~w[pending processing done error]

  schema "videos" do
    field :filename, :string
    field :filepath, :string
    field :format, :string
    field :fps, :integer
    field :duration_seconds, :float
    field :frame_count, :integer
    field :width, :integer
    field :height, :integer
    field :file_size_bytes, :integer
    field :background_frame, :integer, default: 0
    field :start_time_seconds, :float, default: 0.0
    field :end_time_seconds, :float
    field :status, :string, default: "pending"

    belongs_to :experiment, Experiment
    belongs_to :calibration, Calibration
    belongs_to :subject, Subject
    many_to_many :rois, Roi, join_through: "videos_rois"
    has_one :tracking_result, TrackingResult

    timestamps(type: :utc_datetime)
  end

  def changeset(video, attrs) do
    video
    |> cast(attrs, [
      :filename,
      :filepath,
      :format,
      :fps,
      :duration_seconds,
      :frame_count,
      :width,
      :height,
      :file_size_bytes,
      :background_frame,
      :start_time_seconds,
      :end_time_seconds,
      :status,
      :experiment_id,
      :calibration_id,
      :subject_id
    ])
    |> validate_required([:filename, :filepath, :experiment_id])
    |> validate_inclusion(:status, @valid_statuses)
    |> foreign_key_constraint(:experiment_id)
    |> foreign_key_constraint(:calibration_id)
    |> foreign_key_constraint(:subject_id)
    |> unique_constraint(:filepath)
    |> check_constraint(:status, name: :valid_status)
  end
end
