#!/usr/bin/env bash
# Build and push the image to a registry.
# Override REGISTRY / IMAGE / TAG and CONTAINER as needed.
set -euo pipefail
CONTAINER="${CONTAINER:-docker}"
REGISTRY="${REGISTRY:-docker.io}"
IMAGE="${IMAGE:-oliveagle/xfcevdi-mt5}"
TAG="${TAG:-latest}"

"$CONTAINER" build -t "${REGISTRY}/${IMAGE}:${TAG}" .
"$CONTAINER" push "${REGISTRY}/${IMAGE}:${TAG}"
