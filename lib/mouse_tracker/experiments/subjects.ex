defmodule MouseTracker.Experiments.Subjects do
  @moduledoc """
  CRUD + ownership for `Subject` — a reusable, user-owned identity shared
  across N videos/experiments (the same physical animal tracked over time).
  """

  import Ecto.Query
  import MouseTracker.Experiments.Ownership

  alias MouseTracker.Repo
  alias MouseTracker.Accounts.Scope
  alias MouseTracker.Experiments.{Subject, Video}

  def list_subjects(%Scope{user: user}) do
    Repo.all(from s in Subject, where: s.user_id == ^user.id, order_by: s.name)
  end

  def get_subject!(%Scope{user: user}, id) do
    Repo.get_by!(Subject, id: id, user_id: user.id)
  end

  @doc """
  Distinct, non-blank `group` values already used by this user's subjects,
  alphabetically sorted — populates the group datalist/autocomplete (wizard
  new subject field, Pipeline Settings inline edit) and the group filter
  dropdowns (Datasets, Results, Analyses).
  """
  def list_subject_groups(%Scope{user: user}) do
    Repo.all(
      from s in Subject,
        where: s.user_id == ^user.id and not is_nil(s.group) and s.group != "",
        distinct: true,
        order_by: s.group,
        select: s.group
    )
  end

  def create_subject(%Scope{user: user}, attrs) do
    %Subject{user_id: user.id}
    |> Subject.changeset(attrs)
    |> Repo.insert()
  end

  def update_subject(%Scope{user: user}, %Subject{user_id: owner_id} = subject, attrs)
      when is_owner(owner_id, user.id) do
    subject
    |> Subject.changeset(attrs)
    |> Repo.update()
  end

  def delete_subject(%Scope{user: user}, %Subject{user_id: owner_id} = subject)
      when is_owner(owner_id, user.id) do
    Repo.delete(subject)
  end

  def change_subject(%Subject{} = subject, attrs \\ %{}) do
    Subject.changeset(subject, attrs)
  end

  @doc "Number of videos currently pointing at this subject."
  def count_videos_using_subject(%Subject{} = subject) do
    Repo.aggregate(from(v in Video, where: v.subject_id == ^subject.id), :count)
  end
end
