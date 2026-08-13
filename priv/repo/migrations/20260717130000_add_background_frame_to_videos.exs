defmodule MouseTracker.Repo.Migrations.AddBackgroundFrameToVideos do
  use Ecto.Migration

  def change do
    alter table(:videos) do
      add :background_frame, :integer, default: 0, null: false
    end
  end
end
