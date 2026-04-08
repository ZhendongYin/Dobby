#!/bin/sh
set -e
cd /app

echo "Waiting for PostgreSQL..."
until pg_isready -h db -U postgres -d dobby_dev; do
  sleep 2
done

echo "Fetching Elixir deps..."
mix deps.get

if [ -f assets/package.json ]; then
  echo "Installing npm deps (assets)..."
  (cd assets && npm install)
fi

echo "Running migrations..."
mix ecto.migrate

if [ "${RUN_SEED_ON_START:-true}" = "true" ]; then
  echo "Running seeds (idempotent)..."
  mix run priv/repo/seeds.exs || echo "Note: seeds exited non-zero (often OK if data already exists)."
fi

echo "Starting Phoenix dev server..."
exec mix phx.server
