#!/usr/bin/env bash
# Functional test of mt5-install idempotence + graceful offline handling.
# Runs INSIDE the built image (wine present, MetaQuotes CDN may be blocked).
set -euo pipefail

TEST_PREFIX="/tmp/mt5-test-prefix"
TEST_CACHE="/tmp/mt5-test-cache"
TERMINAL="$TEST_PREFIX/drive_c/Program Files/MetaTrader 5/terminal64.exe"

export MT5_PREFIX="$TEST_PREFIX"
export MT5_CACHE_DIR="$TEST_CACHE"
export MT5_INSTALL_WEBVIEW2=no

cleanup() { rm -rf "$TEST_PREFIX" "$TEST_CACHE"; }
trap cleanup EXIT

echo "[test_mt5_install] 1) --prefetch never fails, even offline"
set +e
/usr/local/bin/mt5-install --prefetch
rc=$?
set -e
[ "$rc" = "0" ] || { echo "FAIL: prefetch rc=$rc"; exit 1; }

echo "[test_mt5_install] 2) --check fails when terminal is missing"
set +e
/usr/local/bin/mt5-install --check >/dev/null 2>&1
rc=$?
set -e
[ "$rc" = "1" ] || { echo "FAIL: check rc=$rc (expected 1)"; exit 1; }

echo "[test_mt5_install] 3) fast-path: installed + matching stamp -> skip, exit 0"
mkdir -p "$(dirname "$TERMINAL")"
printf '#!/bin/sh\nexit 0\n' >"$TERMINAL"
chmod +x "$TERMINAL"
mkdir -p "$TEST_CACHE"
dd if=/dev/zero of="$TEST_CACHE/mt5setup.exe" bs=1024 count=1 2>/dev/null
# stamp must match the fingerprint (size:mtime) of the cached installer
fp="$(stat -c '%s:%Y' "$TEST_CACHE/mt5setup.exe")"
echo "$fp" >"$TEST_CACHE/.mt5setup.stamp"

/usr/local/bin/mt5-install >/dev/null
echo "[test_mt5_install] 3 OK (skipped, up to date)"

echo "[test_mt5_install] 4) stale stamp -> installer is really re-run and stamp refreshed"
echo "0:0" >"$TEST_CACHE/.mt5setup.stamp"
/usr/local/bin/mt5-install >/dev/null 2>&1 || true
new_stamp="$(cat "$TEST_CACHE/.mt5setup.stamp")"
[ "$new_stamp" != "0:0" ] || { echo "FAIL: stamp was not refreshed by upgrade run"; exit 1; }
[ "$new_stamp" = "$fp" ] || { echo "FAIL: stamp '$new_stamp' != expected '$fp'"; exit 1; }

echo "[test_mt5_install] 5) running again with matching stamp is a no-op"
/usr/local/bin/mt5-install >/dev/null
[ "$(cat "$TEST_CACHE/.mt5setup.stamp")" = "$fp" ] || { echo "FAIL: stamp changed on no-op run"; exit 1; }

echo "[test_mt5_install] OK"
