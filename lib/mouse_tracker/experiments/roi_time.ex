defmodule MouseTracker.Experiments.RoiTime do
  use Ecto.Schema
  import Ecto.Changeset

  alias MouseTracker.Experiments.{Roi, TrackingResult}

  schema "roi_times" do
    field :frame_count, :integer
    field :seconds, :float

    belongs_to :roi, Roi
    belongs_to :tracking_result, TrackingResult

    timestamps(type: :utc_datetime)
  end

  def changeset(roi_time, attrs) do
    roi_time
    |> cast(attrs, [:frame_count, :seconds, :roi_id, :tracking_result_id])
    |> validate_required([:frame_count, :seconds, :roi_id, :tracking_result_id])
    |> validate_number(:frame_count, greater_than_or_equal_to: 0)
    |> validate_number(:seconds, greater_than_or_equal_to: 0.0)
    |> foreign_key_constraint(:roi_id)
    |> foreign_key_constraint(:tracking_result_id)
    |> unique_constraint([:roi_id, :tracking_result_id])
  end
end
