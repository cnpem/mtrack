defmodule MouseTracker.Repo.Migrations.AddGroupToSubjects do
  use Ecto.Migration

  def change do
    alter table(:subjects) do
      add :group, :string
    end
  end
end
