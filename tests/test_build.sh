#!/usr/bin/env bash
# Build the image. CONTAINER can be docker or podman.
set -euo pipefail

CONTAINER="${CONTAINER:-docker}"
IMAGE="${IMAGE:-xfcevdi}"
TAG="${TAG:-dev}"

echo "[test_build] ${CONTAINER} build -t ${IMAGE}:${TAG}"
"${CONTAINER}" build -t "${IMAGE}:${TAG}" .
echo "[test_build] OK"
