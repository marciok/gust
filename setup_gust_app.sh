#!/usr/bin/env sh

set -e

if ! command -v elixir >/dev/null 2>&1; then
  echo "ERROR: Elixir is not installed or not in PATH."
  echo "Please install Elixir before running this installer."
  exit 1
fi

ELIXIR_VERSION=$(elixir -v | grep "Elixir" | awk '{print $2}')

echo "Detected Elixir version: $ELIXIR_VERSION"

echo "==> Gust Project Generator"
echo

if ! mix help igniter.new >/dev/null 2>&1; then
  echo "==> Igniter is not installed. Bootstrapping Hex and Igniter..."
  mix local.hex --force
  mix archive.install hex igniter_new --force
fi

GUST_APP=${GUST_APP:-${1:-}}

if [ -z "$GUST_APP" ]; then
  printf "Enter your app name (ex: my_app): "
  read GUST_APP
fi

if [ -z "$GUST_APP" ]; then
  echo "ERROR: app name cannot be empty"
  exit 1
fi

# This script will install gust_web on a minimal Phoenix app,
# if you wish to extend, and add the missing dependencies like LiveView you can manually add later.
echo "==> Creating new minimal Igniter Phoenix app: $GUST_APP"
# Pin gust_web and bump the Phoenix-generated deps it conflicts with; otherwise
# Hex silently falls back to an older gust_web that fits phx.new's defaults.
GUST_WEB_VERSION=${GUST_WEB_VERSION:-0.1.42}

mix igniter.new "$GUST_APP" \
  --install "gust_web@${GUST_WEB_VERSION},phoenix_live_dashboard@0.9,dns_cluster@0.3" \
  --with phx.new \
  --yes \
  --with-args="--no-html --no-assets --no-gettext --no-mailer"

cd "$GUST_APP"
mix deps.get

echo "==> Fetching dependencies"

echo
echo "==> Done!"
echo "Your Gust app '$GUST_APP' is ready."
