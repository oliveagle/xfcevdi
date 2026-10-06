#!/usr/bin/env bash
#
# mt5-install.sh - Install / update MetaTrader 5 (Linux, running under Wine)
#
# The MetaTrader 5 Windows client runs on Linux through Wine. The official
# install path is documented in:
#   * https://www.mql5.com/zh/articles/625
#   * https://www.metatrader5.com/en/terminal/help/start_advanced/install_linux
#
# This script is the single entry point used by:
#   * the final Docker layer (prefetch the installer, best effort),
#   * the first container start (install MT5 into the user's Wine prefix),
#   * a cron job (mt5-autoupdate - re-run the web-installer to pick up new
#     MT5 builds, because MetaQuotes ships frequent updates).
#
# MT5 ships as a web-installer (mt5setup.exe). "Upgrade" therefore means
# re-running the installer with the /auto switch; the installer is idempotent
# and updates the existing terminal in place.
#
# Idempotence / auto-upgrade:
#   * A stamp file (MT5_CACHE_DIR/.mt5setup.stamp) records which cached
#     installer we last applied (size + mtime).
#   * On `install`, if terminal64.exe exists AND the stamp matches the cached
#     installer, we skip (fast path, "already up to date").
#   * Otherwise we (re)download the installer (unless cached), run it, and
#     update the stamp.
#
# Usage:
#   mt5-install [--check] [--prefetch] [--force] [--no-webview2]
#
#   --check        Report state only; exit 0 if installed & up to date.
#   --prefetch     Download the latest mt5setup.exe into the cache and stop.
#                  Never fails the build: exits 0 even when offline.
#   --force        Always re-run the installer, ignoring the stamp.
#   --no-webview2  Skip the Microsoft Edge WebView2 Runtime install.
#
### every exit != 0 fails the script
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration (all overridable via environment)
# ---------------------------------------------------------------------------
# Official CDN URLs (kept in sync with metaquotes.software.corp/mt5/mt5linux.sh)
MT5_URL="${MT5_SETUP_URL:-https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe}"
# Broker-branded local installer (e.g. IC Markets SC5). When set to an existing
# file, it is staged into the cache instead of downloading the official
# MetaQuotes web-installer; the auto-update cron keeps using it too.
MT5_SETUP_LOCAL="${MT5_SETUP_LOCAL:-}"
WEBVIEW2_URL="${WEBVIEW2_SETUP_URL:-https://msedge.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/f2910a1e-e5a6-4f17-b52d-7faf525d17f8/MicrosoftEdgeWebview2Setup.exe}"
# Wine prefix that holds the "MetaTrader 5" program directory (per user)
MT5_PREFIX="${MT5_PREFIX:-$HOME/.mt5}"
# Where mt5setup.exe / webview2.exe are cached (shared, must be writable)
MT5_CACHE_DIR="${MT5_CACHE_DIR:-/var/cache/mt5}"
# Install WebView2 runtime? Recent MT5 builds require it.
MT5_INSTALL_WEBVIEW2="${MT5_INSTALL_WEBVIEW2:-yes}"
# Installer command-line switches (whitespace-separated)
MT5_SWITCHES="${MT5_SWITCHES:-/auto}"
# Path to the installed terminal binary
MT5_TERMINAL="$MT5_PREFIX/drive_c/Program Files/MetaTrader 5/terminal64.exe"
# Stamp tracking which cached installer we last applied
MT5_STAMP="$MT5_CACHE_DIR/.mt5setup.stamp"

ACTION="install"
FORCE=0

log()  { printf '[mt5] %s\n' "$*"; }
warn() { printf '[mt5] WARN: %s\n' "$*" >&2; }
die()  { printf '[mt5] ERROR: %s\n' "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [ "$#" -gt 0 ]; do
  case "$1" in
    --check)        ACTION="check" ;;
    --prefetch)     ACTION="prefetch" ;;
    --force)        FORCE=1 ;;
    --no-webview2)  MT5_INSTALL_WEBVIEW2=no ;;
    -h|--help)
      sed -n '2,45p' "$0"
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
  shift
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
is_installed() { [ -x "$MT5_TERMINAL" ]; }

cached_setup() { [ -s "$MT5_CACHE_DIR/mt5setup.exe" ]; }

setup_fingerprint() {
  # size + mtime of the cached installer -> stable-ish change detector
  if cached_setup; then
    stat -c '%s:%Y' "$MT5_CACHE_DIR/mt5setup.exe"
  fi
}

stamp_matches() {
  [ -f "$MT5_STAMP" ] && [ "$(cat "$MT5_STAMP" 2>/dev/null || true)" = "$1" ]
}

write_stamp() {
  local fp; fp="$(setup_fingerprint || true)"
  printf '%s\n' "$fp" >"$MT5_STAMP" 2>/dev/null || warn "cannot write stamp $MT5_STAMP"
}

# Download a file to cache; returns non-zero on failure.
fetch_cached() {
  local url="$1" out="$2"
  require_cmd curl
  mkdir -p "$(dirname "$out")"
  local tmp
  tmp="$(mktemp "${out}.XXXXXX")"
  if ! curl -fSL --retry 2 --connect-timeout 15 --max-time 600 -o "$tmp" "$url"; then
    rm -f "$tmp"
    return 1
  fi
  mv -f "$tmp" "$out"
  log "downloaded $url -> $out ($(stat -c%s "$out") bytes)"
  return 0
}

# Stage a broker-branded local installer into the cache when MT5_SETUP_LOCAL is
# set and readable. Returns 0 when staged (or already present), 1 to fall back
# to the CDN.
stage_local_setup() {
  [ -n "$MT5_SETUP_LOCAL" ] || return 1
  if [ ! -s "$MT5_SETUP_LOCAL" ]; then
    warn "MT5_SETUP_LOCAL is set but not a readable file: $MT5_SETUP_LOCAL"
    return 1
  fi
  mkdir -p "$MT5_CACHE_DIR"
  if [ ! -s "$MT5_CACHE_DIR/mt5setup.exe" ] || ! cmp -s "$MT5_SETUP_LOCAL" "$MT5_CACHE_DIR/mt5setup.exe"; then
    cp -f "$MT5_SETUP_LOCAL" "$MT5_CACHE_DIR/mt5setup.exe"
    log "staged local installer: $MT5_SETUP_LOCAL -> $MT5_CACHE_DIR/mt5setup.exe ($(stat -c%s "$MT5_CACHE_DIR/mt5setup.exe") bytes)"
  fi
  return 0
}

init_wine_prefix() {
  # Configure the Wine prefix once (Windows 11 mode, like the official script).
  if [ ! -f "$MT5_PREFIX/system.reg" ]; then
    require_cmd wine
    require_cmd winecfg
    WINEPREFIX="$MT5_PREFIX" wineboot -u >/dev/null 2>&1 || true
    WINEPREFIX="$MT5_PREFIX" winecfg -v=win11 >/dev/null 2>&1 || true
  fi
}

install_webview2() {
  [ "$MT5_INSTALL_WEBVIEW2" = "yes" ] || return 0
  log "installing Microsoft Edge WebView2 Runtime"
  require_cmd wine
  local exe="$MT5_CACHE_DIR/MicrosoftEdgeWebview2Setup.exe"
  if [ ! -s "$exe" ]; then
    fetch_cached "$WEBVIEW2_URL" "$exe" || {
      warn "WebView2 download failed; continuing without it (MT5 UI features may be limited)"
      return 0
    }
  fi
  WINEPREFIX="$MT5_PREFIX" wine "$exe" /silent /install >/dev/null 2>&1 || \
    warn "WebView2 install failed; continuing"
}

do_install() {
  require_cmd wine
  log "installing / updating MetaTrader 5 (WINEPREFIX=$MT5_PREFIX)"

  init_wine_prefix

  # 1) Make sure we have a usable web-installer in cache.
  local setup="$MT5_CACHE_DIR/mt5setup.exe"
  if ! stage_local_setup && [ ! -s "$setup" ]; then
    if ! fetch_cached "$MT5_URL" "$setup"; then
      if is_installed; then
        # Already installed, but we cannot fetch a newer installer right now.
        # Keep the old terminal (MT5 also self-updates at runtime) and let the
        # next cron tick retry. Not a failure.
        warn "no cached installer and CDN unreachable; keeping existing install"
        exit 0
      fi
      die "no cached installer and CDN unreachable; cannot install MT5"
    fi
  fi

  # 2) WebView2 runtime (needed by modern MT5 builds)
  install_webview2

  # 3) Run the installer in automated mode. /auto installs or updates the
  #    terminal in the prefix without any UI interaction.
  local -a switches
  read -r -a switches <<< "$MT5_SWITCHES"
  log "running installer: wine mt5setup.exe ${switches[*]}"
  WINEPREFIX="$MT5_PREFIX" wine "$setup" "${switches[@]}" || {
    warn "installer returned non-zero exit code"
    if ! is_installed; then
      die "installer failed and terminal64.exe is missing"
    fi
  }

  if is_installed; then
    write_stamp
    log "MetaTrader 5 ready: $MT5_TERMINAL"
    exit 0
  fi
  die "installation finished but terminal64.exe not found at $MT5_TERMINAL"
}

# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------
main() {
case "$ACTION" in
  check)
    if ! is_installed; then
      die "MetaTrader 5 NOT installed at $MT5_TERMINAL"
    fi
    local fp; fp="$(setup_fingerprint)"
    if [ -n "$fp" ] && ! stamp_matches "$fp"; then
      log "MetaTrader 5 installed but a newer installer is cached - upgrade pending"
      exit 0
    fi
    log "MetaTrader 5 installed and up to date: $MT5_TERMINAL"
    exit 0
    ;;

  prefetch)
    # Best-effort: never fail the image build when the CDN is unreachable.
    log "prefetching MT5 installer into $MT5_CACHE_DIR"
    mkdir -p "$MT5_CACHE_DIR"
    if ! stage_local_setup; then
      if fetch_cached "$MT5_URL" "$MT5_CACHE_DIR/mt5setup.exe"; then
        log "prefetch OK - installer cached"
      else
        warn "prefetch failed (CDN unreachable); MT5 will be downloaded at first container start"
      fi
    fi
    exit 0
    ;;

  install)
    if is_installed && [ "$FORCE" != "1" ]; then
      local fp; fp="$(setup_fingerprint)"
      if [ -n "$fp" ] && stamp_matches "$fp"; then
        log "MetaTrader 5 already installed and up to date - skipping"
        exit 0
      fi
      if [ -z "$fp" ]; then
        log "MetaTrader 5 installed; no cached installer to compare - skipping"
        exit 0
      fi
      log "MetaTrader 5 installed, newer installer detected - upgrading"
    fi
    do_install
    ;;

  *)
    die "unknown action: $ACTION"
    ;;
esac
}

main "$@"
