defmodule MouseTracker.Repo.Migrations.AddSubjectIdToVideos do
  use Ecto.Migration

  def change do
    alter table(:videos) do
      add :subject_id, references(:subjects, on_delete: :nilify_all)
    end

    create index(:videos, [:subject_id])
  end
end
