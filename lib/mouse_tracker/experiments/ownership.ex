defmodule MouseTracker.Experiments.Ownership do
  @moduledoc """
  Guard for "does this resource belong to the scope's user" — shared by every
  `update_*`/`delete_*` function across `Experiments` and its per-resource
  submodules (`Calibrations`/`Rois`/`Subjects`), instead of each repeating
  `when user_id == user.id` inline. A plain private function wouldn't work in
  a guard position, so this uses `defguard` (guard-safe: just an equality
  check); a mismatch falls through to no matching function clause, i.e. a
  `FunctionClauseError`.
  """

  defguard is_owner(resource_user_id, scope_user_id) when resource_user_id == scope_user_id
end
