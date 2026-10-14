#!/usr/bin/env bash
# Pull the Dockerfile base images with retries — this machine's network has
# intermittently reset connections to Docker Hub.
set -u
cd "$(dirname "$0")/.."

for img in rust:1-slim debian:bookworm-slim; do
  ok=0
  for attempt in 1 2 3 4 5 6; do
    echo "== pulling $img (attempt $attempt) =="
    if docker pull "$img"; then
      ok=1
      break
    fi
    sleep 5
  done
  if [ "$ok" -ne 1 ]; then
    echo "FAILED to pull $img"
    exit 1
  fi
done
echo "ALL_BASE_IMAGES_OK"
