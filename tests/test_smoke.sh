#!/usr/bin/env bash
# Runtime smoke test: build must already exist (make build). Run inside the image.
set -euo pipefail

CONTAINER="${CONTAINER:-docker}"
IMAGE="${IMAGE:-xfcevdi}"
TAG="${TAG:-dev}"

echo "[test_smoke] verifying MT5 artefacts inside ${IMAGE}:${TAG}"
"${CONTAINER}" run --rm "${IMAGE}:${TAG}" bash -c '
set -e
command -v mt5-install >/dev/null
command -v mt5-launch >/dev/null
command -v mt5-autoupdate >/dev/null
test -f /usr/share/applications/metatrader5.desktop
test -f /etc/cron.d/mt5-autoupdate
echo "[test_smoke] OK"
'
