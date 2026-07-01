defmodule MouseTracker.Experiments.Subject do
  use Ecto.Schema
  import Ecto.Changeset

  alias MouseTracker.Experiments.{Experiment, Video}

  schema "subjects" do
    field :name, :string
    field :sex, :string
    field :age_days, :integer
    field :weight_g, :float
    field :genotype, :string
    field :notes, :string

    belongs_to :experiment, Experiment
    has_many :videos, Video

    timestamps(type: :utc_datetime)
  end

  def changeset(subject, attrs) do
    subject
    |> cast(attrs, [:name, :sex, :age_days, :weight_g, :genotype, :notes, :experiment_id])
    |> validate_required([:name, :experiment_id])
    |> validate_length(:name, max: 255)
    |> validate_inclusion(:sex, ["M", "F"])
    |> validate_number(:age_days, greater_than: 0)
    |> validate_number(:weight_g, greater_than: 0)
    |> foreign_key_constraint(:experiment_id)
  end
end
