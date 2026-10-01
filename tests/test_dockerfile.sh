#!/usr/bin/env bash
# Verify that the Dockerfile's key software-stack and MT5-layer requirements
# are met. Static, no build required.
set -euo pipefail

DOCKERFILE="${DOCKERFILE:-Dockerfile}"
python3 - <<'PY'
import pathlib, re
d = pathlib.Path("Dockerfile").read_text()

# Debian stack must be bookworm, not bullseye
assert "debian:bookworm" in d, "base image must be debian:bookworm"
assert "debian:bullseye" not in d, "bullseye must be gone"

# Key stack components
for pkg in ["x2goserver", "xfce4-panel", "winehq-stable", "openssh-server"]:
    assert pkg in d, f"missing {pkg}"

# Wine must be installed
assert "dl.winehq.org" in d, "WineHQ repo missing"
assert "wine --version" in d, "wine version check missing"

# MT5 layering contract
last_layer_marker = re.search(r"#\s*\d+\.\s+.*LAST LAYER", d)
assert last_layer_marker, "MT5 last layer marker missing"
mt5_layer = d[last_layer_marker.start():]
for tok in ["mt5-install.sh", "--prefetch", "mt5-launch", "mt5-autoupdate"]:
    assert tok in mt5_layer, f"MT5 layer missing {tok}"

# MT5 cron + desktop entry must exist
assert "/etc/cron.d/mt5-autoupdate" in d, "cron entry missing"
assert "metatrader5.desktop" in d, "desktop entry missing"

print("[test_dockerfile] OK - software stack and MT5 last layer verified")
PY
