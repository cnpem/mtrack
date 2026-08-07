# Setup & development

This guide covers installing MTrack for local development and the day-to-day
commands you'll use. For an end-user walkthrough of the app itself, see
[user-guide.md](user-guide.md).

## Prerequisites

| Tool | Version | Notes |
|------|---------|-------|
| Elixir | `~> 1.15` | see `mix.exs` |
| Erlang/OTP | compatible with the Elixir above | |
| Phoenix | `~> 1.8.8` | pulled in by `mix setup` |
| PostgreSQL | any recent 13+ | default dev credentials in `config/dev.exs` |
| Python | `>= 3.8` | see `.python-version` (3.8) and `pyproject.toml` |
| `uv` | latest | manages the Python engine's virtualenv & deps |

The Python engine depends on OpenCV, Matplotlib and Seaborn (NumPy comes in
transitively). These are declared in `pyproject.toml` and locked for `uv`.

## Install

```bash
# Elixir: fetch deps, create + migrate the database, install/build assets
mix setup

# Python: create the venv and install OpenCV/Matplotlib/Seaborn
uv sync
```

`mix setup` is an alias (see `mix.exs`) that runs:

- `deps.get` — fetch Hex dependencies
- `ecto.setup` — `ecto.create` + `ecto.migrate` + seed (`priv/repo/seeds.exs`)
- `assets.setup` + `assets.build` — install Tailwind/esbuild and build the bundle

## Run

```bash
mix phx.server        # http://localhost:4000
# or inside IEx:
iex -S mix phx.server
```

### Dev-only routes

Enabled when `:dev_routes` is on (default in dev):

- `/dev/dashboard` — Phoenix LiveDashboard (metrics, processes, Ecto, Oban)
- `/dev/mailbox` — Swoosh mailbox preview. **Magic-link login and confirmation
  emails are delivered here in dev**, not to a real inbox.

`/` redirects to `/experiments` when logged in, or `/users/log-in` otherwise.

## Seed / demo data

The default `mix setup` seed is minimal. A richer, idempotent demo seed is
available:

```bash
mix run priv/repo/seeds_locomo.exs
```

It creates a user **`demo@locomo.dev`** / **`locomo-demo-123!`** with one fully
populated experiment (four videos, one per status; subjects; a calibration; ROIs;
a tracking result with per-zone times on the "done" video).

## Common commands

```bash
mix test                         # run all tests (auto create/migrate test DB)
mix test test/path/to_test.exs   # run a single test file
mix precommit                    # compile (warnings-as-errors) + format + unused deps + test
mix ecto.migrate                 # run pending migrations
mix ecto.reset                   # drop + recreate + migrate
```

### Python engine directly

The engine can be invoked standalone (useful for debugging the tracker without
the web app). Both modes are documented in [python-engine.md](python-engine.md):

```bash
# Interactive (OpenCV windows for calibration / ROI selection)
uv run python -m priv.python.run -v <video> -c <cage_side_cm> [options]

# Headless (JSON in, JSON progress/result out — how Phoenix calls it)
uv run python -m priv.python.run --json '<json>'
```

## Maintenance

- **Backfill video metadata** — populates `fps` / `duration_seconds` /
  `file_size_bytes` etc. for videos uploaded before those fields were captured.
  Idempotent; run manually after deploying:

  ```bash
  mix mouse_tracker.backfill_video_metadata
  ```

- **Orphan upload cleanup** — `OrphanUploadCleanupWorker` runs daily via Oban Cron
  to delete abandoned upload/frame directories. No manual action needed; tunable
  via `:orphan_upload_max_age_hours` (default 24h). Disabled in the test env.

## Configuration knobs

- `OBAN_VIDEO_PROCESSING_CONCURRENCY` (prod, default `4`) — how many videos are
  tracked in parallel; each job spawns one Python subprocess. Read in
  `config/runtime.exs`.
- Upload base directory and result paths live under `priv/static/uploads/` and are
  served by `Plug.Static`.
