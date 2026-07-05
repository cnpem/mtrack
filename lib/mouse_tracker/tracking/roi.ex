defmodule MouseTracker.Experiments.Roi do
  use Ecto.Schema
  import Ecto.Changeset

  alias MouseTracker.Accounts.User
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

    belongs_to :user, User
    many_to_many :videos, Video, join_through: "videos_rois"
    has_many :roi_times, RoiTime

    timestamps(type: :utc_datetime)
  end

  def changeset(roi, attrs) do
    roi
    |> cast(attrs, [:name, :shape, :x, :y, :w, :h, :radius, :user_id])
    |> validate_required([:name, :x, :y, :user_id])
    |> validate_inclusion(:shape, @valid_shapes)
    |> validate_shape_fields()
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(:name, name: :rois_user_id_name_index)
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

      _ ->
        changeset
    end
  end
end
