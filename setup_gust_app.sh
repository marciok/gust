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

echo "==> Creating new Igniter Phoenix app: $GUST_APP"
mix igniter.new "$GUST_APP" --install gust_web --with phx.new

cd "$GUST_APP"

echo
echo "==> Done!"
echo "Your Gust app '$GUST_APP' is ready."
