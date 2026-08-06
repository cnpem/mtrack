defmodule MouseTracker.Experiments.Calibration do
  use Ecto.Schema
  import Ecto.Changeset

  alias MouseTracker.Accounts.User
  alias MouseTracker.Experiments.Video

  schema "calibrations" do
    field :name, :string
    field :coordinate_x1, :integer
    field :coordinate_y1, :integer
    field :coordinate_x2, :integer
    field :coordinate_y2, :integer
    field :coordinate_x3, :integer
    field :coordinate_y3, :integer
    field :coordinate_x4, :integer
    field :coordinate_y4, :integer
    field :cage_side_cm, :float
    field :scale_cm_2, :float
    field :px_per_10cm, :float
    field :threshold, :integer
    field :min_area, :integer
    field :peripheral_pct, :float
    field :immobility_threshold_cm, :float
    field :valid_region_x, :integer
    field :valid_region_y, :integer
    field :valid_region_w, :integer
    field :valid_region_h, :integer

    belongs_to :user, User
    has_many :videos, Video

    timestamps(type: :utc_datetime)
  end

  def changeset(calibration, attrs) do
    calibration
    |> cast(attrs, [
      :name,
      :coordinate_x1,
      :coordinate_y1,
      :coordinate_x2,
      :coordinate_y2,
      :coordinate_x3,
      :coordinate_y3,
      :coordinate_x4,
      :coordinate_y4,
      :cage_side_cm,
      :scale_cm_2,
      :px_per_10cm,
      :threshold,
      :min_area,
      :peripheral_pct,
      :immobility_threshold_cm,
      :valid_region_x,
      :valid_region_y,
      :valid_region_w,
      :valid_region_h
    ])
    |> validate_required([
      :cage_side_cm,
      :px_per_10cm,
      :threshold,
      :min_area,
      :peripheral_pct,
      :immobility_threshold_cm
    ])
    |> validate_number(:cage_side_cm, greater_than: 0)
    |> validate_number(:scale_cm_2, greater_than: 0)
    |> validate_number(:px_per_10cm, greater_than: 0)
    |> validate_number(:threshold, greater_than_or_equal_to: 0, less_than_or_equal_to: 255)
    |> validate_number(:min_area, greater_than: 0)
    |> validate_number(:peripheral_pct, greater_than: 0, less_than_or_equal_to: 50)
    |> validate_number(:immobility_threshold_cm, greater_than: 0)
    |> validate_coordinates_together()
    |> validate_coordinates2_together()
    |> validate_valid_region_together()
    |> foreign_key_constraint(:user_id)
  end

  defp validate_coordinates_together(changeset) do
    fields = [:coordinate_x1, :coordinate_y1, :coordinate_x2, :coordinate_y2]
    values = Enum.map(fields, &get_field(changeset, &1))

    if Enum.any?(values, &(!is_nil(&1))) and Enum.any?(values, &is_nil(&1)) do
      add_error(
        changeset,
        :coordinate_x1,
        "all cage corner coordinates must be provided together"
      )
    else
      changeset
    end
  end

  defp validate_coordinates2_together(changeset) do
    fields = [:coordinate_x3, :coordinate_y3, :coordinate_x4, :coordinate_y4]
    values = Enum.map(fields, &get_field(changeset, &1))

    if Enum.any?(values, &(!is_nil(&1))) and Enum.any?(values, &is_nil(&1)) do
      add_error(
        changeset,
        :coordinate_x3,
        "all segment-2 coordinates must be provided together"
      )
    else
      changeset
    end
  end

  defp validate_valid_region_together(changeset) do
    fields = [:valid_region_x, :valid_region_y, :valid_region_w, :valid_region_h]
    values = Enum.map(fields, &get_field(changeset, &1))

    if Enum.any?(values, &(!is_nil(&1))) and Enum.any?(values, &is_nil(&1)) do
      add_error(changeset, :valid_region_x, "all valid region fields must be provided together")
    else
      changeset
    end
  end
end
