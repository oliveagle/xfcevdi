#!/usr/bin/env bash
# First-boot end-to-end: run setup.sh in the built image and assert it creates
# the user and writes a USER-scoped MT5 auto-update cron entry (not root).
set -euo pipefail

CONTAINER="${CONTAINER:-docker}"
IMAGE="${IMAGE:-xfcevdi}"
TAG="${TAG:-dev}"

echo "[test_setup_cron] running setup.sh as root inside ${IMAGE}:${TAG}"
out="$("${CONTAINER}" run --rm --user 0:0 --entrypoint /bin/bash "${IMAGE}:${TAG}" -c '
set -e
export USERNAME=trader USER_ID=1000 GROUP_LIST=workers
export ALLOW_APT=no ENTER_PASS=no PASS=abc MT5_INSTALL=no MT5_AUTOUPDATE=yes
groupadd -g 1002 workers 2>/dev/null || true
bash /app/setup.sh >/tmp/setup.log 2>&1 || true
echo "---CRON---"
cat /etc/cron.d/mt5-autoupdate
echo "---ID---"
id trader
')"

echo "$out"
echo "$out" | grep -q '^0 \*/6 \* \* \* trader flock -n /tmp/mt5-autoupdate.lock /usr/local/bin/mt5-autoupdate' || {
  echo "FAIL: user-scoped MT5 cron entry not written by setup.sh"; exit 1;
}
echo "$out" | grep -q '^uid=1000(trader)' || { echo "FAIL: user trader not created"; exit 1; }
echo "[test_setup_cron] OK"
