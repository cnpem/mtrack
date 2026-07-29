defmodule MouseTracker.Experiments.Calibrations do
  @moduledoc """
  CRUD + ownership for `Calibration` — a reusable, user-owned resource shared
  across N videos (see `MouseTracker.Experiments.Calibration` for the
  two-scale-segment derivation of `px_per_10cm`).
  """

  import Ecto.Query
  import MouseTracker.Experiments.Ownership

  alias MouseTracker.Repo
  alias MouseTracker.Accounts.Scope
  alias MouseTracker.Experiments.{Calibration, Video}

  def list_calibrations(%Scope{user: user}) do
    Repo.all(from c in Calibration, where: c.user_id == ^user.id)
  end

  def get_calibration!(%Scope{user: user}, id) do
    Repo.get_by!(Calibration, id: id, user_id: user.id)
  end

  def create_calibration(%Scope{user: user}, attrs) do
    %Calibration{user_id: user.id}
    |> Calibration.changeset(attrs)
    |> Repo.insert()
  end

  def update_calibration(%Scope{user: user}, %Calibration{user_id: owner_id} = calibration, attrs)
      when is_owner(owner_id, user.id) do
    calibration
    |> Calibration.changeset(attrs)
    |> Repo.update()
  end

  def delete_calibration(%Scope{user: user}, %Calibration{user_id: owner_id} = calibration)
      when is_owner(owner_id, user.id) do
    Repo.delete(calibration)
  end

  def change_calibration(%Calibration{} = calibration, attrs \\ %{}) do
    Calibration.changeset(calibration, attrs)
  end

  @doc "Number of videos currently pointing at this calibration."
  def count_videos_using_calibration(%Calibration{} = calibration) do
    Repo.aggregate(from(v in Video, where: v.calibration_id == ^calibration.id), :count)
  end
end
