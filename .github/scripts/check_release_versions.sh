#!/usr/bin/env bash
# Checks that every place pinning the release version agrees with it, so a
# missed bump fails before anything is published.
#
# Usage: check_release_versions.sh [release_version]
# Defaults to gust_web's @version, which checks the pins agree with each other.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "${repo_root}"

attr() { sed -n "s/^[[:space:]]*@$1 \"\([^\"]*\)\".*/\1/p" "$2"; }

release_version="${1:-$(attr version apps/gust_web/mix.exs)}"

if [[ ! "${release_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]]; then
  echo "Invalid release version: ${release_version}" >&2
  exit 1
fi

pins=(
  "gust @version|$(attr version apps/gust/mix.exs)"
  "gust_web @version|$(attr version apps/gust_web/mix.exs)"
  "gust_web.install @gust_web_version|$(attr gust_web_version apps/gust_web/lib/gust_web/mix/tasks/gust_web.install.ex)"
  "setup_gust_app.sh GUST_WEB_VERSION|$(sed -n 's/^GUST_WEB_VERSION=\${GUST_WEB_VERSION:-\([^}]*\)}.*/\1/p' setup_gust_app.sh)"
)

mismatches=0

for pin in "${pins[@]}"; do
  name="${pin%%|*}"
  version="${pin#*|}"

  if [[ "${version}" != "${release_version}" ]]; then
    echo "${name} is ${version:-missing}, expected ${release_version}" >&2
    mismatches=$((mismatches + 1))
  fi
done

if [[ ${mismatches} -gt 0 ]]; then
  exit 1
fi

echo "Release ${release_version}: gust=$(attr version apps/gust/mix.exs)" \
  "gust_web=$(attr version apps/gust_web/mix.exs)" \
  "gust_py=$(attr version apps/gust_py/mix.exs) (gust $(attr gust_version apps/gust_py/mix.exs))" \
  "gust_shell=$(attr version apps/gust_shell/mix.exs)"
