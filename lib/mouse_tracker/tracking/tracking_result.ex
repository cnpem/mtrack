defmodule MouseTracker.Experiments.TrackingResult do
  use Ecto.Schema
  import Ecto.Changeset

  alias MouseTracker.Experiments.{Video, RoiTime}

  schema "tracking_results" do
    field :distance_px, :float
    field :distance_cm, :float
    field :speed_mean_px, :float
    field :speed_mean_cm, :float
    field :speed_median_px, :float
    field :speed_median_cm, :float
    field :heatmap_path, :string
    field :processed_at, :utc_datetime

    belongs_to :video, Video
    has_many :roi_times, RoiTime

    timestamps(type: :utc_datetime)
  end

  def changeset(tracking_result, attrs) do
    tracking_result
    |> cast(attrs, [
      :distance_px, :distance_cm, :speed_mean_px, :speed_mean_cm,
      :speed_median_px, :speed_median_cm, :heatmap_path, :processed_at,
      :video_id
    ])
    |> validate_required([
      :distance_px, :distance_cm,
      :speed_mean_px, :speed_mean_cm,
      :speed_median_px, :speed_median_cm,
      :video_id
    ])
    |> foreign_key_constraint(:video_id)
    |> unique_constraint(:video_id)
  end
end
