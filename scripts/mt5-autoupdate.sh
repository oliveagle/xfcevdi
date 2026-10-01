#!/usr/bin/env bash
#
# mt5-autoupdate.sh - Keep MetaTrader 5 up to date while the container runs.
#
# MetaTrader 5 upgrades very frequently. Two mechanisms cooperate:
#   1. The platform's own self-update runs whenever the terminal starts (MT5
#      auto-updates on connect to its update server) - no action needed.
#   2. This script, scheduled by cron inside the container, re-runs the
#      official web-installer (/auto) so a new build is picked up even when
#      no terminal window has been opened since the upgrade was published.
#
# Logging: /var/log/mt5-autoupdate.log
# Locking: flock on /tmp/mt5-autoupdate.lock (cron must never overlap runs)
#
### every exit != 0 fails the script
set -euo pipefail

LOG="${MT5_AUTOUPDATE_LOG:-/var/log/mt5-autoupdate.log}"
LOCK="${MT5_AUTOUPDATE_LOCK:-/tmp/mt5-autoupdate.lock}"
INSTALLER="${MT5_INSTALLER:-/usr/local/bin/mt5-install}"

ts() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
log() { printf '%s %s\n' "$(ts)" "$*" | tee -a "$LOG" >/dev/null; }

mkdir -p "$(dirname "$LOG")"
touch "$LOG" 2>/dev/null || true

# Only one run at a time; exit silently when a previous run still holds the lock.
exec 9>"$LOCK"
if ! flock -n 9; then
  log "skip: another mt5-autoupdate run holds the lock"
  exit 0
fi

# Renew the cache from the CDN (best effort - uses cached installer as fallback).
if "$INSTALLER" --prefetch; then
  log "prefetch: ok"
else
  log "prefetch: failed (will still attempt upgrade from cache)"
fi

# Re-run the installer to apply a new build if one exists.
if "$INSTALLER" --force; then
  log "update: ok"
else
  log "update: failed"
  exit 1
fi

log "done"
