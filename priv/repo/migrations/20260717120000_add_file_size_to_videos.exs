defmodule MouseTracker.Repo.Migrations.AddFileSizeToVideos do
  use Ecto.Migration

  def change do
    alter table(:videos) do
      add :file_size_bytes, :bigint
    end
  end
end
