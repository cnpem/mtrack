ExUnit.start()

# Requires a real sample video in data/ (gitignored, not present in CI) --
# see test/mouse_tracker/tracking/python_port_test.exs.
# Run explicitly with: mix test --include integration
ExUnit.configure(exclude: [:integration])

Ecto.Adapters.SQL.Sandbox.mode(MouseTracker.Repo, :manual)
