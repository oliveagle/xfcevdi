#!/usr/bin/env bash
# Production entrypoint for xfcevdi_mt5 (7x24 supervisord runtime).
# 1) First-boot: create the trader user (idempotent, via setup.sh).
# 2) Start services under supervisord as PID 1. Never drops to a login shell:
#    docker exec / docker stop behave deterministically for 24/7 operation.
set -euo pipefail

CONF="${SUPERVISOR_CONF:-/etc/supervisor/conf.d/mt5.conf}"

if [ ! -f /app/.setup_done ]; then
  echo "[entry] first boot: creating user '${USERNAME:-trader}'..."
  sudo USERNAME="${USERNAME:-trader}" USER_ID="${USER_ID:-1000}" \
       ALLOW_APT="${ALLOW_APT:-yes}" ENTER_PASS="${ENTER_PASS:-no}" \
       PASS="${PASS:-abc}" MT5_INSTALL=no MT5_AUTOUPDATE=no /app/setup.sh \
       || echo "[entry] WARN setup.sh failed"
fi

mkdir -p /run /run/sshd
# Host-visible control/logs dirs for health + autotrading switch + trade log
mkdir -p /home/trader/.mt5/control /home/trader/.mt5/logs /home/trader/.mt5/logs/supervisor
chown -R trader:trader /home/trader/.mt5/control /home/trader/.mt5/logs
# Persist supervisord logs (and child program logs) on the mounted volume so
# they survive container recreate / image update (7x24 post-mortem capability).
rm -rf /var/log/supervisor
ln -s /home/trader/.mt5/logs/supervisor /var/log/supervisor
# ---------------------------------------------------------------------------
# Strategy note: strategies (MQL5 sources) live in the parent quant_mt5 repo
# at mt5/MQL5 and are synced into this volume by scripts/mt5/sync_to_runtime.sh.
# .ex5 binaries are pre-compiled artifacts committed alongside each .mq5, so
# updating a strategy is "rsync + docker restart" — no image rebuild needed.
# ---------------------------------------------------------------------------
echo "[entry] starting supervisord (conf=$CONF)"
exec /usr/bin/supervisord -n -c "$CONF"
