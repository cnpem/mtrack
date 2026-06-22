defmodule MouseTracker.Experiments.Experiment do
  use Ecto.Schema
  import Ecto.Changeset

  alias MouseTracker.Accounts.User
  alias MouseTracker.Experiments.Video

  schema "experiments" do
    field :name, :string
    field :description, :string

    belongs_to :user, User
    has_many :videos, Video

    timestamps(type: :utc_datetime)
  end

  def changeset(experiment, attrs) do
    experiment
    |> cast(attrs, [:name, :description])
    |> validate_required([:name])
    |> validate_length(:name, max: 255)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:user_id, :name])
  end
end
