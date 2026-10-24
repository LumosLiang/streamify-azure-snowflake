#!/usr/bin/env bash
set -euo pipefail

if [[ $# -gt 1 ]]; then
  echo "Usage: bash $0 [build|init|start]" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$REPO_ROOT/airflow"
case "${1:-start}" in
  build) docker compose build ;;
  init) docker compose run --rm airflow-init ;;
  start) docker compose up -d ;;
  *)
    echo "Usage: bash $0 [build|init|start]" >&2
    exit 2
    ;;
esac
