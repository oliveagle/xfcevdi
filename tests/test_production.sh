#!/usr/bin/env bash
# Production readiness test for xfcevdi_mt5 container.
# Strictly host-side: docker inspect/ps, host /proc, mounted volume files,
# port probes. NEVER uses docker exec or docker run.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Default: volume lives in the parent quant_mt5 repo at runtime/home_storage
QUANT_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

CONTAINER="${CONTAINER_NAME:-xfcevdi_mt5}"
SSH_PORT="${SSH_PORT:-27182}"
# Resolve the host-side path to the mounted volume. SUBMODULE_DIR lets the
# harness override when called from outside the submodule.
HEALTH_DIR="${SUBMODULE_DIR:-${QUANT_DIR}/runtime}/home_storage/trader/.mt5/control"
LOG_DIR="${SUBMODULE_DIR:-${QUANT_DIR}/runtime}/home_storage/trader/.mt5/logs"
HEALTH_FILE="${HEALTH_DIR}/health.json"
SWITCH_JSON="${HEALTH_DIR}/switch.json"
AUTOTRADING="${HEALTH_DIR}/autotrading"
TRADES="${LOG_DIR}/trades.csv"

PASS=0
FAIL=0

pass() { echo "  [PASS] $*"; PASS=$((PASS+1)); }
fail() { echo "  [FAIL] $*"; FAIL=$((FAIL+1)); }

require_container() {
  if ! docker ps --format '{{.Names}}' | grep -qx "${CONTAINER}"; then
    echo "FATAL: container ${CONTAINER} is not running"; exit 2
  fi
}

require_files() {
  for f in "$HEALTH_FILE" "$SWITCH_JSON" "$AUTOTRADING" "$TRADES"; do
    [ -f "$f" ] || { echo "FATAL: missing $f"; exit 2; }
  done
}

wait_health_ok() {
  local timeout_s="${1:-90}" i
  for i in $(seq 1 "$timeout_s"); do
    if [ -f "$HEALTH_FILE" ] && \
       python3 -c "import json,sys; d=json.load(open('$HEALTH_FILE')); sys.exit(0 if d.get('ok') else 1)" 2>/dev/null; then
      return 0
    fi
    sleep 1
  done
  return 1
}

wait_state() {
  local target="$1" timeout_s="${2:-30}" i cur
  for i in $(seq 1 "$timeout_s"); do
    cur=$(python3 -c "import json; print(json.load(open('$SWITCH_JSON'))['autotrading'])" 2>/dev/null)
    [ "$cur" = "$target" ] && return 0
    sleep 1
  done
  return 1
}

wait_health_changes() {
  local baseline="$1" timeout_s="${2:-30}" i now
  for i in $(seq 1 "$timeout_s"); do
    if [ -f "$HEALTH_FILE" ]; then
      now=$(python3 -c "import json; print(json.load(open('$HEALTH_FILE'))['ts'])" 2>/dev/null)
      [ -n "$now" ] && [ "$now" != "$baseline" ] && return 0
    fi
    sleep 1
  done
  return 1
}

# --- TESTS ---------------------------------------------------------------

echo "=== test 1: container running + healthy (docker inspect, no exec) ==="
require_container
state=$(docker inspect --format '{{.State.Status}}' "${CONTAINER}")
health=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "${CONTAINER}")
[ "$state" = "running" ] && pass "container state=running" || fail "container state=${state}"
[ "$health" = "healthy" ] && pass "docker healthcheck=healthy" || fail "docker healthcheck=${health}"

echo "=== test 2: PID1 is supervisord (host /proc, no exec) ==="
pid1=$(docker inspect --format '{{.State.Pid}}' "${CONTAINER}")
if [ -n "$pid1" ] && [ "$pid1" != "0" ]; then
  comm=$(cat "/proc/$pid1/comm" 2>/dev/null)
  [ "$comm" = "supervisord" ] && pass "PID1 comm=supervisord (pid=$pid1)" || fail "PID1 comm=$comm"
else
  fail "could not resolve PID1 (got $pid1)"
fi

echo "=== test 3: image Cmd is prod-entry.sh (image contract) ==="
icmd=$(docker inspect --format '{{json .Config.Cmd}}' "${CONTAINER}")
echo "    cmd=$icmd"
echo "$icmd" | grep -q "prod-entry.sh" && pass "CMD=prod-entry.sh" || fail "CMD does not reference prod-entry.sh"

echo "=== test 4: port ${SSH_PORT} listening (ss, no exec) ==="
if ss -tln "( sport = :${SSH_PORT} )" 2>/dev/null | grep -q ":${SSH_PORT}"; then
  pass "ss shows :${SSH_PORT} LISTEN"
else
  fail "port ${SSH_PORT} not listening"
fi

echo "=== test 5: SSH banner reachable (nc, no exec) ==="
banner=$(timeout 5 bash -c "exec 3<>/dev/tcp/127.0.0.1/${SSH_PORT}; head -1 <&3" 2>/dev/null)
if echo "$banner" | grep -qE "^SSH-"; then
  pass "SSH banner: ${banner}"
else
  fail "no SSH banner (got: '${banner}')"
fi

echo "=== test 6: health.json on mounted volume, valid JSON, ok=true ==="
require_files
if wait_health_ok 90; then
  pass "health.json ok=true within timeout"
else
  fail "health.json did not reach ok=true within 90s"
  cat "$HEALTH_FILE" 2>/dev/null
fi
python3 -c "import json; d=json.load(open('$HEALTH_FILE')); assert {'mt5_pid','xvfb_pid','ts'} <= set(d)" \
  && pass "health.json has expected keys" || fail "health.json shape wrong"
mt5_pid=$(python3 -c "import json; print(json.load(open('$HEALTH_FILE'))['mt5_pid'])")
xvfb_pid=$(python3 -c "import json; print(json.load(open('$HEALTH_FILE'))['xvfb_pid'])")
[ "$mt5_pid" -gt 0 ] && pass "mt5_pid>0 (${mt5_pid})" || fail "mt5_pid not >0"
[ "$xvfb_pid" -gt 0 ] && pass "xvfb_pid>0 (${xvfb_pid})" || fail "xvfb_pid not >0"

echo "=== test 7: switch.json shape + on/off flips append to trades.csv ==="
python3 -c "import json; d=json.load(open('$SWITCH_JSON')); assert {'autotrading','enabled','since_ts','since','mt5_pid'} <= set(d)" \
  && pass "switch.json has expected keys" || fail "switch.json shape wrong"

# Force a known starting state ('off') before testing on-toggle, so the first
# state change is always meaningful.
echo "off" > "$AUTOTRADING"
wait_state "off" 30 || fail "could not reset switch.json to off"
rows_before=$(wc -l < "$TRADES")
echo "on" > "$AUTOTRADING"
if wait_state "on" 30; then
  pass "switch.json flipped to on"
else
  fail "switch.json did not flip to on within 30s"
fi
sleep 1
rows_after=$(wc -l < "$TRADES")
[ "$rows_after" -ge "$((rows_before+1))" ] && pass "trades.csv grew (${rows_before} -> ${rows_after})" \
  || fail "trades.csv did not grow (${rows_before} -> ${rows_after})"
tail -5 "$TRADES" | grep -q ",on,switch_change," && pass "trades.csv has switch_change state=on row" \
  || fail "no on-switch_change row in tail"

# Toggle OFF
rows_before=$(wc -l < "$TRADES")
echo "off" > "$AUTOTRADING"
if wait_state "off" 30; then
  pass "switch.json flipped to off"
else
  fail "switch.json did not flip to off within 30s"
fi
sleep 1
rows_after=$(wc -l < "$TRADES")
[ "$rows_after" -ge "$((rows_before+1))" ] && pass "trades.csv grew on off-toggle (${rows_before} -> ${rows_after})" \
  || fail "trades.csv did not grow on off-toggle"

echo "=== test 8: trades.csv has header + heartbeats ==="
head -1 "$TRADES" | grep -q "^ts_iso,state,event,mt5_pid,xvfb_pid,note" \
  && pass "CSV header correct" || fail "CSV header wrong"
hb_count=$(grep -c ",heartbeat," "$TRADES" || true)
[ "$hb_count" -ge 1 ] && pass "at least 1 heartbeat row (${hb_count})" || fail "no heartbeat rows"

echo "=== test 9: container restart preserves trades.csv + switch.json ==="
restart_rows=$(wc -l < "$TRADES")
restart_state=$(python3 -c "import json; print(json.load(open('$SWITCH_JSON'))['autotrading'])")
docker restart "${CONTAINER}" >/dev/null
ok_wait=0
for i in $(seq 1 90); do
  if [ "$(docker inspect --format '{{.State.Health.Status}}' "${CONTAINER}")" = "healthy" ]; then
    ok_wait=1; break
  fi
  sleep 1
done
[ "$ok_wait" = "1" ] && pass "container recovered to healthy after restart" \
  || fail "container did not recover within 90s"
rows_after_restart=$(wc -l < "$TRADES")
[ "$rows_after_restart" -ge "$restart_rows" ] && pass "trades.csv survived restart (${restart_rows} -> ${rows_after_restart})" \
  || fail "trades.csv lost rows (${restart_rows} -> ${rows_after_restart})"
new_state=$(python3 -c "import json; print(json.load(open('$SWITCH_JSON'))['autotrading'])" 2>/dev/null)
[ "$new_state" = "$restart_state" ] && pass "switch.json preserved (${new_state})" \
  || fail "switch.json drift: ${restart_state} -> ${new_state}"
sleep 1
grep -q ",guard_start," "$TRADES" && pass "guard_start row recorded after restart" \
  || fail "no guard_start after restart"

echo "=== test 10: autorestart on guard kill (host /proc, no exec) ==="
pid1=$(docker inspect --format '{{.State.Pid}}' "${CONTAINER}")
guard_pid=""
for cand in /proc/[0-9]*; do
  pp=$(awk '{print $4}' "$cand/stat" 2>/dev/null)
  cmd=$(tr '\0' ' ' < "$cand/cmdline" 2>/dev/null)
  if [ "$pp" = "$pid1" ] && echo "$cmd" | grep -q "mt5_guard"; then
    guard_pid=$(basename "$cand"); break
  fi
done
if [ -z "$guard_pid" ]; then
  fail "could not locate guard pid from host"
else
  health_before=$(python3 -c "import json; print(json.load(open('$HEALTH_FILE'))['ts'])")
  kill -9 "$guard_pid" 2>/dev/null && pass "killed guard pid=${guard_pid}" || fail "kill failed"
  if wait_health_changes "$health_before" 30; then
    pass "guard respawned and health.json timestamp advanced"
  else
    fail "guard did not recover within 30s"
  fi
fi

echo
echo "=== summary ==="
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = "0" ]
