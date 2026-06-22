defmodule MouseTracker.Experiments.Roi do
  use Ecto.Schema
  import Ecto.Changeset

  alias MouseTracker.Experiments.{Video, RoiTime}

  @valid_shapes ~w[rectangle circle]

  schema "rois" do
    field :name, :string
    field :shape, :string, default: "rectangle"
    field :x, :integer
    field :y, :integer
    field :w, :integer
    field :h, :integer
    field :radius, :integer

    belongs_to :video, Video
    has_many :roi_times, RoiTime

    timestamps(type: :utc_datetime)
  end

  def changeset(roi, attrs) do
    roi
    |> cast(attrs, [:name, :shape, :x, :y, :w, :h, :radius, :video_id])
    |> validate_required([:name, :x, :y, :video_id])
    |> validate_inclusion(:shape, @valid_shapes)
    |> validate_shape_fields()
    |> foreign_key_constraint(:video_id)
  end

  defp validate_shape_fields(changeset) do
    case get_field(changeset, :shape) do
      "rectangle" -> validate_required(changeset, [:w, :h])
      "circle" -> validate_required(changeset, [:radius])
      _ -> changeset
    end
  end
end
