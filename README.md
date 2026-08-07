# MTrack

**MTrack** is a web application for **automated mouse locomotor-activity tracking
from video**. It wraps an OpenCV tracking engine in a [Phoenix
LiveView](https://www.phoenixframework.org/) interface so researchers can upload
open-field / home-cage recordings, calibrate and mark zones visually, process
videos in the background, and read the results — distance travelled, speed
(mean / median / max), thigmotaxis, immobility, path tortuosity, per-ROI dwell
time and an occupancy heatmap — without touching the command line.

> **TODO:** add a screenshot / GIF of the Experiments and Results screens here.

## Architecture at a glance

```
Browser ──WebSocket──▶ Phoenix LiveView ──▶ PostgreSQL (Ecto)
                              │
                              ▼ enqueue
                        Oban worker ──Port.open──▶ Python subprocess (OpenCV)
                              ▲                          │
                              └──── stdout JSON ─────────┘
                        {"type":"progress"} / {"type":"result"}
                              │
                              ▼ Phoenix PubSub  "video:<id>"
                        LiveView re-render (live progress + results)
```

A video is uploaded through a 3-step wizard, saved to disk and registered in
Postgres. An [Oban](https://hexdocs.pm/oban) background job runs the Python
tracker as a subprocess, streaming progress and the final metrics back as
line-delimited JSON. The worker persists the results and broadcasts over Phoenix
PubSub, so the LiveView screens update in real time. See
[`docs/architecture.md`](docs/architecture.md) for the full lifecycle.

## Tech stack

| Layer | Technology |
|-------|-----------|
| Web / real-time | Elixir, Phoenix `~> 1.8`, Phoenix LiveView `~> 1.2` |
| Database | PostgreSQL via Ecto |
| Background jobs | Oban (Postgres-backed queues) |
| Frontend | Tailwind CSS v4 (no DaisyUI), esbuild, a small `RoiCanvas` JS hook |
| Tracking engine | Python 3.8+, OpenCV, NumPy, Matplotlib, Seaborn |
| Python tooling | [`uv`](https://docs.astral.sh/uv/) |

## Quick start

**Prerequisites:** Elixir/Erlang, PostgreSQL, Python 3.8+ and `uv`.

```bash
# 1. Elixir side: install deps, create + migrate the DB, build assets
mix setup

# 2. Python side: install the tracking engine's dependencies
uv sync

# 3. Run the dev server
mix phx.server
```

Open <http://localhost:4000>. Register an account (in dev, magic-link emails show
up in the Swoosh mailbox at <http://localhost:4000/dev/mailbox>), or load the demo
data — see [`docs/setup.md`](docs/setup.md) for details, seeds and common tasks.

## Documentation

| Doc | What's inside |
|-----|---------------|
| [docs/setup.md](docs/setup.md) | Full install / run, dev routes, seeds, `mix` commands, maintenance tasks |
| [docs/user-guide.md](docs/user-guide.md) | End-user walkthrough: wizard, processing, results, analytics, export |
| [docs/architecture.md](docs/architecture.md) | Video lifecycle, module map, web layer, Oban, real-time |
| [docs/data-model.md](docs/data-model.md) | Ecto schemas and the reusable-resource model |
| [docs/python-engine.md](docs/python-engine.md) | `priv/python/` reference: CLI modes, JSON contract, metrics |

## Project layout

```
lib/
  mouse_tracker/          # domain: contexts, schemas, workers, Python port
  mouse_tracker_web/      # web: router, LiveViews, components, controllers
priv/
  python/                 # OpenCV tracking engine (run/analyzer/detector/metrics/render)
  repo/                   # migrations + seeds
  static/uploads/         # uploaded videos, extracted frames, result images
assets/                   # JS entry point + Tailwind CSS + JS hooks
test/                     # ExUnit tests
```

> Note: `priv/mouse_tracker.py` is the original standalone script and is
> **deprecated** — the maintained engine is the module under `priv/python/`.
