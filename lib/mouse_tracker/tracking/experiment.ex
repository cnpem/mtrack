defmodule MouseTracker.Experiments.Experiment do
  use Ecto.Schema
  import Ecto.Changeset

  alias MouseTracker.Accounts.User
  alias MouseTracker.Experiments.{Video, Subject}

  schema "experiments" do
    field :name, :string
    field :description, :string

    belongs_to :user, User
    has_many :videos, Video
    has_many :subjects, Subject

    timestamps(type: :utc_datetime)
  end

  def changeset(experiment, attrs) do
    experiment
    |> cast(attrs, [:name, :description])
    |> validate_required([:name])
    |> validate_length(:name, max: 255)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(:name, name: :experiments_user_id_name_index)
  end
end
