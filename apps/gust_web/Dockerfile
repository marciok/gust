# Find eligible builder and runner images on Docker Hub. We use Debian
# instead of Alpine to avoid DNS resolution issues in production.
#
# This file is based on these images:
#   - https://hub.docker.com/r/hexpm/elixir/tags - for the build image
#   - https://hub.docker.com/_/debian/tags - for the release image
#
# Example builder image:
#   docker.io/hexpm/elixir:1.18.4-erlang-27.3.2-debian-trixie-20260406-slim

ARG ELIXIR_VERSION=1.18.4
ARG OTP_VERSION=27.3.2
ARG DEBIAN_VERSION=trixie-20260406-slim
ARG UV_VERSION=0.12.10
ARG PYTHON_VERSION=3.13
ARG GUST_WITH_PYTHON=false

ARG BUILDER_IMAGE="docker.io/hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="docker.io/debian:${DEBIAN_VERSION}"

FROM docker.io/astral/uv:${UV_VERSION} AS uv

FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential git nodejs npm \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ARG GUST_WITH_PYTHON

ENV MIX_ENV="prod"
ENV GUST_WITH_PYTHON=${GUST_WITH_PYTHON}

RUN mix local.hex --force \
  && mix local.rebar --force

# Copy the umbrella manifests and compile-time config first for better layer caching.
COPY mix.exs mix.lock ./
COPY config config
COPY apps/gust/mix.exs apps/gust/mix.exs
COPY apps/gust_py/mix.exs apps/gust_py/mix.exs
COPY apps/gust_web/mix.exs apps/gust_web/mix.exs

RUN mix deps.get --only ${MIX_ENV}
RUN mix deps.compile

# Copy the umbrella applications and runtime assets.
COPY apps/gust/lib apps/gust/lib
COPY apps/gust/priv apps/gust/priv
COPY apps/gust_py/lib apps/gust_py/lib
COPY apps/gust_web/lib apps/gust_web/lib
COPY apps/gust_web/priv apps/gust_web/priv
COPY apps/gust_web/assets apps/gust_web/assets
COPY apps/gust_web/rel apps/gust_web/rel


RUN mix compile

WORKDIR /app/apps/gust_web
RUN mix assets.setup
RUN mix assets.deploy
RUN mix release

FROM ${RUNNER_IMAGE} AS runtime

RUN apt-get update \
  && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 locales ca-certificates \
  && rm -rf /var/lib/apt/lists/*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
  && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8
ENV MIX_ENV="prod"
ENV SHELL=/bin/bash

WORKDIR /app
RUN chown nobody /app

COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/gust_web ./

USER nobody

EXPOSE 4000

CMD ["/app/bin/server"]

FROM runtime AS python

USER root

ARG PYTHON_VERSION

COPY --from=uv /uv /uvx /usr/local/bin/

ENV UV_PYTHON_INSTALL_DIR="/opt/uv/python"
ENV UV_PYTHON_BIN_DIR="/usr/local/bin"
ENV UV_CACHE_DIR="/tmp/uv-cache"

RUN uv python install "${PYTHON_VERSION}" --default \
  && mkdir -p "${UV_CACHE_DIR}" \
  && chown -R nobody:nogroup "${UV_CACHE_DIR}"

USER nobody

FROM runtime AS final
