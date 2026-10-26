#!/usr/bin/env bash
# Runs the publish preflight locally, so failures show up before tagging and
# without committing anything:
#
# 1. check_release_versions.sh, against gust_web's @version.
# 2. build_and_run.sh, including the e2e/ Playwright suite, in Linux containers
#    like the GitHub runner, against Hex tarballs built from the working tree.
#
# Not covered: the Docker image builds.
#
# Usage: .github/scripts/preflight_in_docker.sh (or make preflight)
# Requires Docker, and gust_web assets built (mix assets.deploy in apps/gust_web).

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
version_of() { sed -n "s/^$1 //p" "${repo_root}/.tool-versions"; }

release_version="$(sed -n 's/^[[:space:]]*@version "\([^"]*\)".*/\1/p' "${repo_root}/apps/gust_web/mix.exs")"
debian_version="$(sed -n 's/^ARG DEBIAN_VERSION=//p' "${repo_root}/apps/gust_web/Dockerfile")"
image="hexpm/elixir:$(version_of elixir)-erlang-$(version_of erlang)-debian-${debian_version}"
name="gust-preflight-$$"
# Same Node major as the publish workflow's setup-node.
node_version="24.11.0"
tarballs_dir="$(mktemp -d)"

"${repo_root}/.github/scripts/check_release_versions.sh" "${release_version}"

if [[ ! -d "${repo_root}/apps/gust_web/priv/static/assets" ]]; then
  echo "Build gust_web assets first: (cd apps/gust_web && mix assets.deploy)" >&2
  exit 1
fi

cleanup() {
  docker rm -f "${name}-pg" >/dev/null 2>&1 || true
  rm -rf "${tarballs_dir}"
}
trap cleanup EXIT

(cd "${repo_root}/apps/gust" && mix hex.build --output "${tarballs_dir}/gust.tar")
(cd "${repo_root}/apps/gust_web" && PUBLISH_DEP=true mix hex.build --output "${tarballs_dir}/gust_web.tar")

docker run -d --name "${name}-pg" \
  -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=postgres \
  postgres:14 >/dev/null

until docker exec "${name}-pg" pg_isready -U postgres >/dev/null 2>&1; do sleep 1; done

# Sharing the Postgres container's network makes it reachable on localhost,
# which is where the generated app's config expects it.
docker run --rm \
  --network "container:${name}-pg" \
  -e LANG=C.UTF-8 -e DEBIAN_FRONTEND=noninteractive \
  -v "${repo_root}:/repo:ro" \
  -v "${tarballs_dir}:/tarballs:ro" \
  "${image}" \
  bash -c "
    set -euo pipefail
    # Plain-HTTP apt can be rewritten by network proxies (seen with Meraki),
    # which shows up as hash mismatches; HTTPS avoids that. Retry for real
    # mirror syncs.
    sed -i 's|http://deb.debian.org|https://deb.debian.org|' /etc/apt/sources.list.d/debian.sources
    for attempt in 1 2 3; do
      apt-get update -qq && apt-get install -y -qq git curl ca-certificates xz-utils >/dev/null && break
      [[ \${attempt} -eq 3 ]] && exit 1
      sleep 10
    done
    # Debian's npm drags in hundreds of packages; the official build is one download.
    node_arch=\$(dpkg --print-architecture | sed 's/amd64/x64/')
    curl -fsSL https://nodejs.org/dist/v${node_version}/node-v${node_version}-linux-\${node_arch}.tar.xz |
      tar -xJ -C /usr/local --strip-components=1
    mix local.hex --force && mix local.rebar --force
    mix archive.install hex phx_new --force && mix archive.install hex igniter_new --force
    /repo/.github/scripts/build_and_run.sh '${release_version}' /tarballs
  "
