defmodule MouseTracker.Repo do
  use Ecto.Repo,
    otp_app: :mouse_tracker,
    adapter: Ecto.Adapters.Postgres
end
