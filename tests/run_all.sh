#!/usr/bin/env bash
# Orchestrate: lint -> build -> test_mt5_layer -> test_smoke
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== 1/4 lint ==="
bash "${SCRIPT_DIR}/test_lint.sh"

echo "=== 2/4 mt5 layer check ==="
bash "${SCRIPT_DIR}/test_mt5_layer.sh"

echo "=== 3/4 build ==="
bash "${SCRIPT_DIR}/test_build.sh"

echo "=== 4/4 smoke ==="
bash "${SCRIPT_DIR}/test_smoke.sh"

echo "=== all tests passed ==="
