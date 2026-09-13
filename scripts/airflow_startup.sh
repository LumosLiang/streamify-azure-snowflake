#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

echo "Building airflow docker images..."
cd "$REPO_ROOT/airflow"
docker compose build

echo "Running airflow-init..."
docker compose up airflow-init

echo "Starting up airflow in detached mode..."
docker compose up -d

echo "Airflow started successfully."
echo "Airflow is running in detached mode. "
echo "Run 'docker compose logs --follow' to see the logs."
