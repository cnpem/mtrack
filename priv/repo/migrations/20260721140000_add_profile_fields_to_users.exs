defmodule MouseTracker.Repo.Migrations.AddProfileFieldsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :name, :string
      add :institution, :string
    end
  end
end
