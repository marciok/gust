#!/usr/bin/env bash
# Generates a fresh app with setup_gust_app.sh against the gust/gust_web Hex
# tarballs about to be published, then checks it resolves, compiles and boots.
#
# Usage: install_smoke_test.sh <release_version> <dir with gust.tar and gust_web.tar>

set -euo pipefail

release_version="$1"
tarballs_dir="$(cd "$2" && pwd)"
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
work_dir="$(mktemp -d)"
app="gust_smoke_app"
port="${PORT:-4000}"

# gust_web depends on gust via `in_umbrella: true` (i.e. `path: "../gust"`)
# when PUBLISH_DEP is unset, so unpacking both side by side wires them up.
for pkg in gust gust_web; do
  mkdir -p "${work_dir}/pkgs/${pkg}" "${work_dir}/tar/${pkg}"
  tar -xf "${tarballs_dir}/${pkg}.tar" -C "${work_dir}/tar/${pkg}"
  tar -xzf "${work_dir}/tar/${pkg}/contents.tar.gz" -C "${work_dir}/pkgs/${pkg}"
done

cd "${work_dir}"
GUST_WEB_VERSION="path:${work_dir}/pkgs/gust_web" \
  sh "${repo_root}/setup_gust_app.sh" "${app}" </dev/null

cd "${app}"

for pkg in gust gust_web; do
  resolved="$(mix run --no-start -e "Application.load(:${pkg}); IO.puts(Application.spec(:${pkg}, :vsn))" | tail -n 1)"

  if [[ "${resolved}" != "${release_version}" ]]; then
    echo "Generated app resolved ${pkg} ${resolved}, expected ${release_version}" >&2
    exit 1
  fi
done

mix compile --warnings-as-errors
mix ecto.create
mix ecto.migrate

PORT="${port}" mix phx.server >"${work_dir}/server.log" 2>&1 &
server_pid=$!
trap 'kill "${server_pid}" 2>/dev/null || true' EXIT

for _ in $(seq 1 60); do
  if curl -fsS -o /dev/null "http://localhost:${port}/gust/dags"; then
    echo "Generated app serves /gust/dags with gust_web ${release_version}"
    exit 0
  fi

  sleep 2
done

cat "${work_dir}/server.log" >&2
echo "Generated app did not serve /gust/dags" >&2
exit 1
