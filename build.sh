#!/usr/bin/env bash
# Build the container image. Override CONTAINER to podman or docker.
set -euo pipefail
CONTAINER="${CONTAINER:-docker}"
"$CONTAINER" build -t xfcevdi:dev .
