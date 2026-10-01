#!/usr/bin/env bash
#
# mt5-launch.sh - Launch (or update) MetaTrader 5 in the current X session.
#
# Used by the XFCE application launcher entry (metatrader5.desktop) and by
# `mt5` on the command line. Guarantees the terminal is installed first, then
# runs it under the user's Wine prefix with the session's display/audio.
#
### every exit != 0 fails the script
set -euo pipefail

MT5_PREFIX="${MT5_PREFIX:-$HOME/.mt5}"
MT5_TERMINAL="$MT5_PREFIX/drive_c/Program Files/MetaTrader 5/terminal64.exe"

log() { printf '[mt5] %s\n' "$*"; }

# First run (or after a fresh home volume): install via the shared installer.
if [ ! -x "$MT5_TERMINAL" ]; then
  log "MetaTrader 5 not installed yet - running installer"
  /usr/local/bin/mt5-install || {
    echo "MetaTrader 5 installation failed. Check network access to MetaQuotes CDN." >&2
    echo "You can retry with: mt5-install" >&2
    exit 1
  }
fi

# Exec the terminal in the foreground so the launcher receives the PID and the
# session's DISPLAY/PULSE_SERVER are inherited verbatim.
exec env WINEPREFIX="$MT5_PREFIX" wine "$MT5_TERMINAL" "$@"
