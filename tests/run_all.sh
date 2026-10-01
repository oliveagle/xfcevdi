#!/usr/bin/env bash
# Orchestrate: lint -> static checks -> build -> smoke -> toolchain -> MT5
# Behaves like the CI pipeline: fails fast at the first failing stage.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== 1/8 lint ==="
bash "${SCRIPT_DIR}/test_lint.sh"

echo "=== 2/8 dockerfile checks ==="
bash "${SCRIPT_DIR}/test_dockerfile.sh"
bash "${SCRIPT_DIR}/test_mt5_layer.sh"

echo "=== 3/8 CI config ==="
bash "${SCRIPT_DIR}/test_ci.sh"

echo "=== 4/8 build ==="
bash "${SCRIPT_DIR}/test_build.sh"

echo "=== 5/8 runtime smoke ==="
bash "${SCRIPT_DIR}/test_smoke.sh"

echo "=== 6/8 compile & test toolchain ==="
bash "${SCRIPT_DIR}/test_toolchain.sh"

echo "=== 7/8 first-boot setup (user + MT5 cron) ==="
bash "${SCRIPT_DIR}/test_setup_cron.sh"

echo "=== 8/8 MT5 auto-upgrade logic ==="
CONTAINER="${CONTAINER:-docker}"; export CONTAINER
IMAGE="${IMAGE:-xfcevdi}"; export IMAGE
TAG="${TAG:-dev}"; export TAG
docker run --rm -v "${SCRIPT_DIR}:/tests:ro" --entrypoint /bin/bash "${IMAGE}:${TAG}" \
  -c 'bash /tests/test_mt5_install.sh'

echo "=== all tests passed ==="
