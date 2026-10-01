#!/usr/bin/env bash
# Shell linting: shellcheck + bash -n
set -euo pipefail

echo "[test_lint] shellcheck"
shellcheck scripts/*.sh

echo "[test_lint] bash syntax"
for f in scripts/*.sh; do
  echo "  bash -n $f"
  bash -n "$f"
done
echo "[test_lint] OK"
