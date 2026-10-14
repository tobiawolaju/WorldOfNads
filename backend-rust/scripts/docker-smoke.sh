#!/usr/bin/env bash
# Build the Docker image, run it on a test port, smoke-test it, clean up.
#
#   bash scripts/docker-smoke.sh [host-port] [container-port]
#
# The container listens on $PORT (Render's convention); defaults here pick 8090
# so the env-var path is exercised, not just the 8080 default.
set -uo pipefail
cd "$(dirname "$0")/.."

HOST_PORT="${1:-18080}"
CONTAINER_PORT="${2:-8090}"
NAME="wons-room-smoke"

docker rm -f "$NAME" >/dev/null 2>&1 || true
docker build -t wons-room-server:latest . 2>&1 | tail -n 6

CID=$(docker run -d --rm -e "PORT=${CONTAINER_PORT}" \
  -p "${HOST_PORT}:${CONTAINER_PORT}" --name "$NAME" wons-room-server:latest)
sleep 2

echo "----- container logs -----"
docker logs "$CID" 2>&1 | tail -n 10

bash scripts/smoke.sh "ws://127.0.0.1:${HOST_PORT}/?username=docker-smoke" || true

echo "----- health check -----"
curl -s -i --max-time 3 "http://127.0.0.1:${HOST_PORT}/health" | head -n 4

docker rm -f "$NAME" >/dev/null 2>&1 || true
