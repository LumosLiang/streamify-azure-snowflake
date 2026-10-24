#!/usr/bin/env bash
set -euo pipefail

if [[ $# -gt 1 ]]; then
  echo "Usage: bash $0 [build|start]" >&2
  exit 2
fi

# Resolve from this script so the repository can live in any directory.
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir/../eventsim"

case "${1:-start}" in
  build)
    docker build -t events:1.0 .
    exit 0
    ;;
  start) ;;
  *)
    echo "Usage: bash $0 [build|start]" >&2
    exit 2
    ;;
esac

if [[ -f .env ]]; then
  source .env
fi

if [[ "$(docker ps -aq --filter 'name=^/million_events$')" != "" ]]; then
  echo 'million_events already exists. Use docker start million_events to reuse it.' >&2
  echo 'To change its parameters, stop and remove that container before creating it again.' >&2
  exit 1
fi

echo "Running Eventsim in detached mode..."
docker run -itd \
  --network host \
  --name million_events \
  --mount "type=bind,src=${PWD}/examples,dst=/opt/eventsim/examples,readonly" \
  --log-driver local \
  --log-opt max-size=100m \
  --log-opt max-file=3 \
  --memory="5.5g" \
  --memory-swap="7g" \
  --oom-kill-disable \
  events:1.0 \
    -c "${EVENTSIM_CONFIG:-examples/example-config.json}" \
    --start-time "`date +"%Y-%m-%dT%H:%M:%S"`" \
    --end-time "$(date -d "+${EVENTSIM_DURATION_DAYS:-1} days" +"%Y-%m-%dT%H:%M:%S")" \
    --nusers "${EVENTSIM_USERS:-1000000}" \
    --growth-rate "${EVENTSIM_GROWTH_RATE:-10}" \
    --userid "${EVENTSIM_USER_ID:-1}" \
    --kafkaBrokerList "${EVENTSIM_KAFKA_BOOTSTRAP_SERVERS:-localhost:9092}" \
    --randomseed "${EVENTSIM_RANDOM_SEED:-1}" \
    --continuous

echo "Started streaming events for ${EVENTSIM_USERS:-1000000} users..."
echo "Eventsim is running in detached mode. "
echo "Run 'docker logs --follow million_events' to see the logs."
