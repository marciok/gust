# Build this Dockerfile from the umbrella root:
#   docker build -f apps/gust_web/Dockerfile -t gust_web:0.1.29 .

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

ARG BUILDER_IMAGE="docker.io/hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="docker.io/debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential git \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV MIX_ENV="prod"

RUN mix local.hex --force \
  && mix local.rebar --force

# Copy the umbrella manifests and compile-time config first for better layer caching.
COPY mix.exs mix.lock ./
COPY config config
COPY apps/gust/mix.exs apps/gust/mix.exs
COPY apps/gust_web/mix.exs apps/gust_web/mix.exs

RUN mix deps.get --only ${MIX_ENV}
RUN mix deps.compile

# Copy the umbrella applications and runtime assets.
COPY apps/gust/lib apps/gust/lib
COPY apps/gust/priv apps/gust/priv
COPY apps/gust_web/lib apps/gust_web/lib
COPY apps/gust_web/priv apps/gust_web/priv
COPY apps/gust_web/assets apps/gust_web/assets
COPY apps/gust_web/rel apps/gust_web/rel


RUN mix compile

WORKDIR /app/apps/gust_web
RUN mix assets.setup
RUN mix assets.deploy
RUN mix release

FROM ${RUNNER_IMAGE} AS final

RUN apt-get update \
  && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 locales ca-certificates \
  && rm -rf /var/lib/apt/lists/*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
  && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8
ENV MIX_ENV="prod"

WORKDIR /app
RUN chown nobody /app

COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/gust_web ./

USER nobody

EXPOSE 4000

CMD ["/app/bin/server"]
