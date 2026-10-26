#!/usr/bin/env bash
# Generates a fresh app with setup_gust_app.sh against the gust/gust_web Hex
# tarballs about to be published, checks it resolves and compiles, then runs
# the Playwright suite in e2e/ against it booted in dev and as a prod release.
#
# Usage: build_and_run.sh <release_version> <dir with gust.tar and gust_web.tar>
# Needs Postgres on localhost with postgres/postgres credentials, and Node.

set -euo pipefail

release_version="$1"
tarballs_dir="$(cd "$2" && pwd)"
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
work_dir="$(mktemp -d)"
app="gust_generated_app"
app_dir="${work_dir}/${app}"
e2e_dir="${work_dir}/e2e"

run_e2e() {
  (cd "${e2e_dir}" && GUST_E2E_MODE="$1" GUST_APP_DIR="${app_dir}" GUST_APP="${app}" npx playwright test)
}

# gust_web depends on gust via `in_umbrella: true` (i.e. `path: "../gust"`)
# when PUBLISH_DEP is unset, so unpacking both side by side wires them up.
for pkg in gust gust_web; do
  mkdir -p "${work_dir}/pkgs/${pkg}" "${work_dir}/tar/${pkg}"
  tar -xf "${tarballs_dir}/${pkg}.tar" -C "${work_dir}/tar/${pkg}"
  tar -xzf "${work_dir}/tar/${pkg}/contents.tar.gz" -C "${work_dir}/pkgs/${pkg}"
done

# Copied out of the repo, which may be mounted read-only.
mkdir -p "${e2e_dir}"
cp -R "${repo_root}"/e2e/{package.json,package-lock.json,playwright.config.ts,tests,fixtures} "${e2e_dir}"
(cd "${e2e_dir}" && npm ci --no-audit --no-fund && npx playwright install --with-deps chromium)

cd "${work_dir}"
GUST_WEB_VERSION="path:${work_dir}/pkgs/gust_web" \
  sh "${repo_root}/setup_gust_app.sh" "${app}" </dev/null

cd "${app_dir}"
cp "${e2e_dir}"/fixtures/dags/*.ex dags/

for pkg in gust gust_web; do
  resolved="$(mix run --no-start -e "Application.load(:${pkg}); IO.puts(Application.spec(:${pkg}, :vsn))" | tail -n 1)"

  if [[ "${resolved}" != "${release_version}" ]]; then
    echo "Generated app resolved ${pkg} ${resolved}, expected ${release_version}" >&2
    exit 1
  fi
done

echo "==> dev"
mix compile --warnings-as-errors
mix ecto.create
mix ecto.migrate
run_e2e dev

echo "==> prod release"
(
  export MIX_ENV=prod
  export DATABASE_URL="ecto://postgres:postgres@localhost/${app}_prod"
  export SECRET_KEY_BASE="$(elixir -e 'IO.puts(Base.encode64(:crypto.strong_rand_bytes(48)))')"
  export B64_SECRETS_CLOAK_KEY="$(elixir -e 'IO.puts(Base.encode64(:crypto.strong_rand_bytes(32)))')"
  export PHX_SERVER=true PHX_HOST=localhost

  mix compile --warnings-as-errors
  mix ecto.create
  mix ecto.migrate
  mix release --overwrite
  run_e2e prod
)

echo "Generated app passes the e2e suite in dev and prod with gust_web ${release_version}"
