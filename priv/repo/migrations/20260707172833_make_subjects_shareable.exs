defmodule MouseTracker.Repo.Migrations.MakeSubjectsShareable do
  use Ecto.Migration

  def up do
    alter table(:subjects) do
      add :user_id, references(:users, on_delete: :delete_all)
    end

    flush()

    execute """
    UPDATE subjects s
    SET user_id = e.user_id
    FROM experiments e
    WHERE e.id = s.experiment_id
    """

    execute "ALTER TABLE subjects ALTER COLUMN user_id SET NOT NULL"

    drop index(:subjects, [:experiment_id])

    alter table(:subjects) do
      remove :experiment_id
    end

    create unique_index(:subjects, [:user_id, :name])
  end

  def down do
    alter table(:subjects) do
      add :experiment_id, references(:experiments, on_delete: :delete_all)
    end

    flush()

    execute """
    UPDATE subjects s
    SET experiment_id = v.experiment_id
    FROM (
      SELECT subject_id, MIN(experiment_id) AS experiment_id
      FROM videos
      WHERE subject_id IS NOT NULL
      GROUP BY subject_id
    ) v
    WHERE v.subject_id = s.id
    """

    execute "ALTER TABLE subjects ALTER COLUMN experiment_id SET NOT NULL"
    drop unique_index(:subjects, [:user_id, :name])

    alter table(:subjects) do
      remove :user_id
    end

    create index(:subjects, [:experiment_id])
  end
end
