defmodule MouseTracker.Repo.Migrations.CreateSubjects do
  use Ecto.Migration

  def change do
    create table(:subjects) do
      add :name, :string, null: false
      add :sex, :string
      add :age_days, :integer
      add :weight_g, :float
      add :genotype, :string
      add :notes, :text
      add :experiment_id, references(:experiments, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:subjects, [:experiment_id])
  end
end
