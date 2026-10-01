#!/usr/bin/env bash
# Static check: verify that all MT5-related COPY/RUN instructions appear in the
# LAST section of the Dockerfile (after the Wine install).
set -euo pipefail

DOCKERFILE="${DOCKERFILE:-Dockerfile}"
python3 - <<'PY'
import pathlib, re
dockerfile = pathlib.Path("Dockerfile").read_text().splitlines()
last_layer_idx = max(i for i, l in enumerate(dockerfile)
                     if re.match(r'\s*#\s*\d+\.\s+.*LAST LAYER', l))
mt5_layer = "\n".join(dockerfile[last_layer_idx:])
required = [
    "COPY ./scripts/mt5-install.sh",
    "/usr/local/bin/mt5-install --prefetch",
    "command -v mt5-install",
    "command -v mt5-launch",
    "command -v mt5-autoupdate",
]
for r in required:
    assert r in mt5_layer, f"missing in last MT5 layer: {r}"
print("[test_mt5_layer] OK - MT5 instructions are all in the last layer")
PY
