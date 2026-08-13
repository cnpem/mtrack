# Find eligible builder and runner images on Docker Hub. We use Ubuntu/Debian
# instead of Alpine to avoid DNS resolution issues in production.
#
# https://hub.docker.com/r/hexpm/elixir/tags?name=ubuntu
# https://hub.docker.com/_/ubuntu/tags
#
# This file is based on these images:
#
#   - https://hub.docker.com/r/hexpm/elixir/tags - for the build image
#   - https://hub.docker.com/_/debian/tags?name=trixie-20260610-slim - for the release image
#   - https://pkgs.org/ - resource for finding needed packages
#   - Ex: docker.io/hexpm/elixir:1.20.1-erlang-29.0.2-debian-trixie-20260610-slim
#
ARG ELIXIR_VERSION=1.20.1
ARG OTP_VERSION=29.0.2
ARG DEBIAN_VERSION=trixie-20260610-slim

ARG BUILDER_IMAGE="docker.io/hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="docker.io/debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

# install build dependencies
RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential git \
  && rm -rf /var/lib/apt/lists/*

# prepare build dir
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force \
  && mix local.rebar --force

# set build ENV
ENV MIX_ENV="prod"

# install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

RUN mix assets.setup

COPY priv priv

COPY lib lib

# Compile the release
RUN mix compile

COPY assets assets

# compile assets
RUN mix assets.deploy

# Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

COPY rel rel
RUN mix release

# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM ${RUNNER_IMAGE} AS final

# libstdc++6/openssl/libncurses6/locales/ca-certificates: standard Elixir release runtime deps.
# libgl1/libglib2.0-0/libsm6/libxext6/libxrender1: `opencv-python` (not the -headless variant)
# links these at import time even though the app only ever runs it in headless (--json) mode
# and never opens a window here. Kept the GUI-capable wheel on purpose instead of swapping to
# opencv-python-headless: `priv/python/` also backs an interactive CLI mode (see CLAUDE.md,
# `render.py`'s cv2.imshow/namedWindow calls) used for local calibration, and dev/prod share
# the same pyproject.toml/uv.lock — swapping the wheel here would silently break that CLI mode
# for anyone who later runs it inside this image.
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    libstdc++6 openssl libncurses6 locales ca-certificates curl \
    libgl1 libglib2.0-0 libsm6 libxext6 libxrender1 \
  && rm -rf /var/lib/apt/lists/*

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
  && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# uv: statically linked binary, no separate Python/pip install needed on the image — uv
# downloads and manages its own interpreter matching `.python-version` (3.8) on first sync.
COPY --from=ghcr.io/astral-sh/uv:0.11.26 /uv /usr/local/bin/uv

WORKDIR "/app"
RUN chown nobody /app

# set runner ENV
ENV MIX_ENV="prod"

# Only copy the final release from the build stage
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/mouse_tracker ./

# MouseTracker.Tracking.PythonPort/FrameExtractor resolve the Python project root at runtime
# as the parent of this app's `priv/` dir (`:code.priv_dir(:mouse_tracker) |> Path.join("..")`),
# which a Mix release places at lib/mouse_tracker-<vsn>/. `priv/python/` already landed there
# via the release copy above; pyproject.toml/uv.lock/.python-version need to join it as
# siblings, and the venv is synced (`--frozen`, no network at container start) right there too.
COPY pyproject.toml uv.lock .python-version ./
# Also symlink priv/ up to a version-independent /app/priv, so a docker-compose volume
# mount doesn't need to hardcode the release's app version (lib/mouse_tracker-<vsn>/) —
# it only ever changes if the release layout itself changes, not on every `mix.exs` bump.
RUN set -eu; \
    APP_DIR=$(find /app/lib -maxdepth 1 -type d -name "mouse_tracker-*"); \
    cp pyproject.toml uv.lock .python-version "$APP_DIR"/; \
    rm pyproject.toml uv.lock .python-version; \
    cd "$APP_DIR"; \
    UV_PYTHON_INSTALL_DIR=/app/.uv-python UV_CACHE_DIR=/app/.uv-cache uv sync --frozen --no-dev; \
    mkdir -p "$APP_DIR/priv/static/uploads"; \
    chown -R nobody:root "$APP_DIR" /app/.uv-python /app/.uv-cache; \
    ln -s "$APP_DIR/priv" /app/priv

# UV_NO_SYNC: the venv above is already fully synced against the frozen lockfile at build
# time — skip `uv run`'s normal "resync if needed" check so it never needs to write to the
# cache or reach the network at container start (PythonPort/FrameExtractor invoke plain
# `uv run python -m priv.python.run ...`, without a `--frozen` flag of their own).
# MPLCONFIGDIR: matplotlib writes a font cache on first import; /tmp is world-writable by
# default, so this avoids needing a $HOME the "nobody" user doesn't have.
ENV UV_PYTHON_INSTALL_DIR=/app/.uv-python \
    UV_CACHE_DIR=/app/.uv-cache \
    UV_NO_SYNC=1 \
    MPLCONFIGDIR=/tmp/mplconfig \
    HOME=/app

USER nobody

# If using an environment that doesn't automatically reap zombie processes, it is
# advised to add an init process such as tini via `apt-get install`
# above and adding an entrypoint. See https://github.com/krallin/tini for details
# ENTRYPOINT ["/tini", "--"]

CMD ["/app/bin/server"]
