#!/usr/bin/env bash
# Static CI config check (workflow syntax / file existence)
set -euo pipefail
test -f .github/workflows/ci.yaml
python3 - <<'PY'
import yaml, pathlib
data = yaml.safe_load(pathlib.Path(".github/workflows/ci.yaml").read_text())
assert "jobs" in data
assert set(data["jobs"]) >= {"lint", "build-and-test"}
print("[test_ci] OK - CI workflow has lint and build-and-test jobs")
PY
