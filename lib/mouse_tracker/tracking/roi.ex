defmodule MouseTracker.Experiments.Roi do
  use Ecto.Schema
  import Ecto.Changeset

  alias MouseTracker.Accounts.User
  alias MouseTracker.Experiments.{Video, RoiTime}

  @valid_shapes ~w[rectangle circle polygon]

  # A polygon ROI stores its 4 free-form vertices as (x1,y1)..(x4,y4). `x`/`y`
  # are kept (set to the first vertex) so the shared required fields and any
  # code reading a ROI's origin keep working across all shapes.
  @polygon_fields ~w[x1 y1 x2 y2 x3 y3 x4 y4]a

  schema "rois" do
    field :name, :string
    field :shape, :string, default: "rectangle"
    field :x, :integer
    field :y, :integer
    field :w, :integer
    field :h, :integer
    field :radius, :integer
    field :x1, :integer
    field :y1, :integer
    field :x2, :integer
    field :y2, :integer
    field :x3, :integer
    field :y3, :integer
    field :x4, :integer
    field :y4, :integer

    belongs_to :user, User
    many_to_many :videos, Video, join_through: "videos_rois"
    has_many :roi_times, RoiTime

    timestamps(type: :utc_datetime)
  end

  def changeset(roi, attrs) do
    roi
    |> cast(attrs, [:name, :shape, :x, :y, :w, :h, :radius, :user_id | @polygon_fields])
    |> validate_required([:name, :x, :y, :user_id])
    |> validate_inclusion(:shape, @valid_shapes)
    |> validate_shape_fields()
    |> foreign_key_constraint(:user_id)
  end

  defp validate_shape_fields(changeset) do
    case get_field(changeset, :shape) do
      "rectangle" ->
        changeset
        |> validate_required([:w, :h])
        |> validate_number(:w, greater_than: 0)
        |> validate_number(:h, greater_than: 0)

      "circle" ->
        changeset
        |> validate_required([:radius])
        |> validate_number(:radius, greater_than: 0)

      "polygon" ->
        validate_required(changeset, @polygon_fields)

      _ ->
        changeset
    end
  end
end
