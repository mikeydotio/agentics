#!/usr/bin/env bats
# Tests for freshen's on-stop.sh Stop hook, focused on the F045/F041
# capture-pane confirm/retry behavior added on top of the existing signal +
# .clear-pending dedup logic.
#
# tmux is shimmed (state-driven fake executable on PATH), consistent with
# this repo's existing convention for these hooks (see
# plugins/forge/hooks/session-stop.bats's header comment) -- everything else
# (.freshen/ signal files, .clear-pending) is the real thing.

HOOK="$BATS_TEST_DIRNAME/on-stop.sh"
FRESHEN_ROOT="$BATS_TEST_DIRNAME/.."

setup() {
  ORIGINAL_PATH="$PATH"
  TEST_DIR="$(mktemp -d)"
  export TEST_DIR
  mkdir -p "$TEST_DIR/.freshen"

  SHIM_DIR="$TEST_DIR/shim"
  mkdir -p "$SHIM_DIR"
  export STATE_DIR="$TEST_DIR/state"
  mkdir -p "$STATE_DIR"
  TMUX_CALL_LOG="$TEST_DIR/tmux-calls.log"
  export TMUX_CALL_LOG
  touch "$TMUX_CALL_LOG"

  # Same state-driven shim as lib/pane-confirm.bats: capture-pane reflects
  # $STATE_DIR/pane_content (blank/confirmed by default), send-keys logs and
  # succeeds unless $STATE_DIR/send_fail exists.
  cat > "$SHIM_DIR/tmux" <<'SHIM'
#!/usr/bin/env bash
echo "$*" >> "$TMUX_CALL_LOG"
case "$1" in
  capture-pane)
    cat "$STATE_DIR/pane_content" 2>/dev/null
    exit 0
    ;;
  send-keys)
    [ -f "$STATE_DIR/send_fail" ] && exit 1
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
SHIM
  chmod +x "$SHIM_DIR/tmux"
  export PATH="$SHIM_DIR:$PATH"
  : > "$STATE_DIR/pane_content"

  # Fast, tiny bounds for tests.
  export PANE_CONFIRM_ATTEMPTS=2
  export PANE_CONFIRM_DELAY=0.01
  export PANE_SEND_RETRIES=1
  export PANE_PASTE_SETTLE_DELAY=0
}

teardown() {
  # Fault shims must not leak into fixture removal or Bats' own cleanup.
  export PATH="$ORIGINAL_PATH"
  rm -rf "$TEST_DIR"
}

send_count() {
  grep -c '^send-keys' "$TMUX_CALL_LOG" || true
}

run_on_stop() {
  ( cd "$TEST_DIR" && \
    CLAUDE_PLUGIN_ROOT="$FRESHEN_ROOT" TMUX=1 TMUX_PANE="%1" \
    PANE_CONFIRM_ATTEMPTS="$PANE_CONFIRM_ATTEMPTS" PANE_CONFIRM_DELAY="$PANE_CONFIRM_DELAY" PANE_SEND_RETRIES="$PANE_SEND_RETRIES" PANE_PASTE_SETTLE_DELAY="$PANE_PASTE_SETTLE_DELAY" \
    STATE_DIR="$STATE_DIR" TMUX_CALL_LOG="$TMUX_CALL_LOG" \
    bash "$HOOK" < /dev/null )
}

@test "no signal file: exits cleanly, sends nothing" {
  run run_on_stop
  [ "$status" -eq 0 ]
  [ ! -s "$TMUX_CALL_LOG" ]
  [ ! -f "$TEST_DIR/.freshen/.clear-pending" ]
}

@test ".clear-pending already set: does not send a second /clear" {
  touch "$TEST_DIR/.freshen/forge.signal"
  touch "$TEST_DIR/.freshen/.clear-pending"
  run run_on_stop
  [ "$status" -eq 0 ]
  [ ! -s "$TMUX_CALL_LOG" ]
}

@test "disabled: skips entirely even with a pending signal" {
  touch "$TEST_DIR/.freshen/forge.signal"
  touch "$TEST_DIR/.freshen/.disabled"
  run run_on_stop
  [ "$status" -eq 0 ]
  [ ! -s "$TMUX_CALL_LOG" ]
  [ ! -f "$TEST_DIR/.freshen/.clear-pending" ]
}

@test "no tmux env: leaves the signal for manual handling, sends nothing" {
  echo "/forge resume" > "$TEST_DIR/.freshen/forge.signal"
  run bash -c "cd '$TEST_DIR' && env -u TMUX -u TMUX_PANE CLAUDE_PLUGIN_ROOT='$FRESHEN_ROOT' bash '$HOOK' < /dev/null"
  [ "$status" -eq 0 ]
  [ ! -s "$TMUX_CALL_LOG" ]
  [ -f "$TEST_DIR/.freshen/forge.signal" ]
  [ ! -f "$TEST_DIR/.freshen/.clear-pending" ]
}

@test "F045: confirmed /clear sets .clear-pending and logs the transition" {
  echo "/forge resume" > "$TEST_DIR/.freshen/forge.signal"
  : > "$STATE_DIR/pane_content"
  run run_on_stop
  [ "$status" -eq 0 ]
  # /clear is now delivered as a paste + a separate Enter (so the Enter can be
  # resent alone on a swallowed submit, #86): 2 send-keys calls.
  [ "$(send_count)" = "2" ]
  [ -f "$TEST_DIR/.freshen/.clear-pending" ]
  run grep -c 'sending /clear' "$TEST_DIR/.freshen/transitions.log"
  [ "$output" = "1" ]
  run grep -c 'confirmed accepted' "$TEST_DIR/.freshen/transitions.log"
  [ "$output" = "1" ]
}

@test "F045/F041: unconfirmed /clear after retries does NOT set .clear-pending, leaves the signal, and warns" {
  echo "/forge resume" > "$TEST_DIR/.freshen/forge.signal"
  # The pane never reacts -- /clear sits there forever.
  echo "/clear" > "$STATE_DIR/pane_content"
  run run_on_stop
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_DIR/.freshen/.clear-pending" ]
  [ -f "$TEST_DIR/.freshen/forge.signal" ]
  [[ "$output" == *"WARNING"*"unconfirmed"* ]]
  run grep -c 'unconfirmed after retries' "$TEST_DIR/.freshen/transitions.log"
  [ "$output" = "1" ]
}

@test "a busy pane whose send-keys errors outright is retried, not dropped" {
  echo "/forge resume" > "$TEST_DIR/.freshen/forge.signal"
  touch "$STATE_DIR/send_fail"
  run run_on_stop
  [ "$status" -eq 0 ]
  # Bounded resends still happen even though every send-keys call errors --
  # PANE_SEND_RETRIES=1 means 2 total attempts.
  [ "$(send_count)" = "2" ]
  [ ! -f "$TEST_DIR/.freshen/.clear-pending" ]
  [ -f "$TEST_DIR/.freshen/forge.signal" ]
}

@test "stale signals older than 2 hours are still deleted before dispatch" {
  echo "/forge resume" > "$TEST_DIR/.freshen/stale.signal"
  # Backdate well past the 2-hour sweep window.
  touch -t "$(date -v-3H +%Y%m%d%H%M.%S 2>/dev/null || date -d '3 hours ago' +%Y%m%d%H%M.%S)" "$TEST_DIR/.freshen/stale.signal"
  run run_on_stop
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_DIR/.freshen/stale.signal" ]
  [ ! -s "$TMUX_CALL_LOG" ]
}

# Freeze only epoch reads; timestamps in transition logs still use real date.
# Marker ages use actual filesystem metadata, not a stubbed expiry decision.
freeze_clock() {
  export FRESHEN_TEST_NOW
  FRESHEN_TEST_NOW="$(date +%s)"
  cat > "$SHIM_DIR/date" <<'SHIM'
#!/usr/bin/env bash
if [ "$*" = '+%s' ]; then
  printf '%s\n' "$FRESHEN_TEST_NOW"
else
  exec /bin/date "$@"
fi
SHIM
  chmod +x "$SHIM_DIR/date"
}

pending_age() {
  python3 - "$TEST_DIR/.freshen/.clear-pending" "$FRESHEN_TEST_NOW" "$1" <<'PY'
import os
import sys
from pathlib import Path
path, now, age = sys.argv[1:]
Path(path).touch()
timestamp = int(now) - int(age)
os.utime(path, (timestamp, timestamp))
PY
}

assert_expired() {
  local age="$1"
  [ "$status" -eq 0 ] || return 1
  [[ "$output" == *"WARNING"*"expired .clear-pending"*"${age}s"*"120s"* ]] || return 1
  [ "$(grep -c 'expired .clear-pending' "$TEST_DIR/.freshen/transitions.log")" = 1 ]
}

@test "AGE-100: ages 119 and future remain pending without changing mtime" {
  freeze_clock
  echo '/forge resume' > "$TEST_DIR/.freshen/forge.signal"
  local age
  for age in 119 -60; do
    pending_age "$age"
    run run_on_stop
    [ "$status" -eq 0 ] || return 1
    [ ! -s "$TMUX_CALL_LOG" ] || return 1
    [ -f "$TEST_DIR/.freshen/.clear-pending" ] || return 1
    [ ! -f "$TEST_DIR/.freshen/transitions.log" ] || return 1
    run python3 -c 'import os,sys; assert int(os.stat(sys.argv[1]).st_mtime) == int(sys.argv[2])-int(sys.argv[3])' \
      "$TEST_DIR/.freshen/.clear-pending" "$FRESHEN_TEST_NOW" "$age"
    [ "$status" -eq 0 ] || return 1
  done
}

@test "AGE-100: exactly 120 seconds expires before signal discovery and preserves consumed marker" {
  freeze_clock
  pending_age 120
  echo witness > "$TEST_DIR/.freshen/.clear-consumed"
  run run_on_stop
  assert_expired 120
  [ ! -f "$TEST_DIR/.freshen/.clear-pending" ]
  [ ! -s "$TMUX_CALL_LOG" ]
  [ "$(cat "$TEST_DIR/.freshen/.clear-consumed")" = witness ]
  run run_on_stop
  [ "$status" -eq 0 ]
  [ "$(grep -c 'expired .clear-pending' "$TEST_DIR/.freshen/transitions.log")" = 1 ]
}

@test "AGE-100: accepted but unexecuted clear recovers once and completes normal handoff" {
  freeze_clock
  echo '/forge resume' > "$TEST_DIR/.freshen/forge.signal"
  run run_on_stop
  [ "$status" -eq 0 ]
  [ "$(send_count)" = 2 ]
  [ -f "$TEST_DIR/.freshen/.clear-pending" ]
  pending_age 121
  run run_on_stop
  assert_expired 121
  [ "$(send_count)" = 4 ]
  [ "$(cat "$TEST_DIR/.freshen/forge.signal")" = '/forge resume' ]
  run run_on_stop
  [ "$status" -eq 0 ]
  [ "$(send_count)" = 4 ]
  [ "$(grep -c 'expired .clear-pending' "$TEST_DIR/.freshen/transitions.log")" = 1 ]

  run bash -c 'cd "$1" && CLAUDE_PLUGIN_ROOT="$2" TMUX=1 TMUX_PANE=%1 bash "$2/hooks/on-clear.sh"' \
    _ "$TEST_DIR" "$FRESHEN_ROOT"
  [ "$status" -eq 0 ]
  [ "$(send_count)" = 6 ]
  [ ! -f "$TEST_DIR/.freshen/forge.signal" ]
  [ ! -f "$TEST_DIR/.freshen/.clear-pending" ]
  [ -f "$TEST_DIR/.freshen/.clear-consumed" ]
}

@test "AGE-100: expired marker with unconfirmed retransmission preserves signal for next Stop" {
  freeze_clock
  pending_age 121
  echo '/forge resume' > "$TEST_DIR/.freshen/forge.signal"
  echo /clear > "$STATE_DIR/pane_content"
  run run_on_stop
  assert_expired 121
  [[ "$output" == *"unconfirmed"* ]]
  [ ! -f "$TEST_DIR/.freshen/.clear-pending" ]
  [ "$(cat "$TEST_DIR/.freshen/forge.signal")" = '/forge resume' ]
  [ "$(send_count)" -gt 0 ]
  : > "$STATE_DIR/pane_content"
  run run_on_stop
  [ "$status" -eq 0 ]
  [ -f "$TEST_DIR/.freshen/.clear-pending" ]
  [ "$(grep -c 'expired .clear-pending' "$TEST_DIR/.freshen/transitions.log")" = 1 ]
}

@test "AGE-100: expiry without tmux leaves queued signal for manual handling" {
  freeze_clock
  pending_age 121
  echo '/forge resume' > "$TEST_DIR/.freshen/forge.signal"
  run bash -c 'cd "$1" && env -u TMUX -u TMUX_PANE CLAUDE_PLUGIN_ROOT="$2" bash "$3" < /dev/null' \
    _ "$TEST_DIR" "$FRESHEN_ROOT" "$HOOK"
  assert_expired 121
  [ ! -f "$TEST_DIR/.freshen/.clear-pending" ]
  [ "$(cat "$TEST_DIR/.freshen/forge.signal")" = '/forge resume' ]
  [ ! -s "$TMUX_CALL_LOG" ]
}

@test "AGE-100: disabled hook preserves expired pending marker" {
  freeze_clock
  pending_age 121
  touch "$TEST_DIR/.freshen/.disabled"
  run run_on_stop
  [ "$status" -eq 0 ]
  [ -f "$TEST_DIR/.freshen/.clear-pending" ]
  [ ! -f "$TEST_DIR/.freshen/transitions.log" ]
  [ ! -s "$TMUX_CALL_LOG" ]
}

# Exercise both stat dialects and failures on one host. Successful calls still
# read the real file mtime; only the external utility's interface is adapted.
shim_stat() {
  export FRESHEN_TEST_STAT="$1"
  cat > "$SHIM_DIR/stat" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$1" >> "$STATE_DIR/stat-calls"
case "$FRESHEN_TEST_STAT" in
  fail) echo 'fixture stat failure' >&2; exit 1 ;;
  invalid) printf '%s\n' 'not-a-timestamp'; exit 0 ;;
  overflow) printf '%s\n' 999999999999999999999999; exit 0 ;;
  consumed) mv .freshen/.clear-pending .freshen/.clear-consumed 2>/dev/null; exit 1 ;;
  gnu) [ "$1" = '-c%Y' ] || exit 1 ;;
  bsd) [ "$1" = '-f%m' ] || exit 1 ;;
esac
exec python3 -c 'import os,sys; print(int(os.stat(sys.argv[1]).st_mtime))' "$2"
SHIM
  chmod +x "$SHIM_DIR/stat"
}

@test "AGE-100: GNU stat and BSD fallback both expire actual old markers" {
  freeze_clock
  local dialect
  for dialect in gnu bsd; do
    shim_stat "$dialect"
    pending_age 120
    run run_on_stop
    [ "$status" -eq 0 ] || return 1
    [ ! -f "$TEST_DIR/.freshen/.clear-pending" ] || return 1
  done
  [ "$(cat "$STATE_DIR/stat-calls")" = $'-c%Y\n-c%Y\n-f%m' ]
  [ ! -s "$TMUX_CALL_LOG" ]
}

@test "AGE-100: failed or invalid metadata warns and retains marker without dispatch" {
  freeze_clock
  echo '/forge resume' > "$TEST_DIR/.freshen/forge.signal"
  local mode
  for mode in fail invalid overflow; do
    shim_stat "$mode"
    pending_age 121
    run run_on_stop
    [ "$status" -eq 0 ] || return 1
    [[ "$output" == *"WARNING"*"cannot determine age"*".clear-pending"* ]] || return 1
    [ -f "$TEST_DIR/.freshen/.clear-pending" ] || return 1
    [ "$(cat "$TEST_DIR/.freshen/forge.signal")" = '/forge resume' ] || return 1
    [ ! -s "$TMUX_CALL_LOG" ] || return 1
  done
}

@test "AGE-100: consumption during metadata inspection is harmless" {
  freeze_clock
  shim_stat consumed
  pending_age 121
  run run_on_stop
  [ "$status" -eq 0 ]
  [[ "$output" != *"WARNING"* ]]
  [ ! -f "$TEST_DIR/.freshen/.clear-pending" ]
  [ -f "$TEST_DIR/.freshen/.clear-consumed" ]
  [ ! -s "$TMUX_CALL_LOG" ]
}

@test "AGE-100: failed deletion fails loud without retransmission or false recovery log" {
  freeze_clock
  pending_age 121
  echo '/forge resume' > "$TEST_DIR/.freshen/forge.signal"
  cat > "$SHIM_DIR/rm" <<'SHIM'
#!/usr/bin/env bash
if [ "$*" = '-f .freshen/.clear-pending' ]; then
  echo 'fixture removal failure' >&2
  exit 1
fi
exec /bin/rm "$@"
SHIM
  chmod +x "$SHIM_DIR/rm"
  run run_on_stop
  [ "$status" -ne 0 ]
  [[ "$output" == *"failed to remove"*".clear-pending"* ]]
  [ -f "$TEST_DIR/.freshen/.clear-pending" ]
  [ "$(cat "$TEST_DIR/.freshen/forge.signal")" = '/forge resume' ]
  [ ! -f "$TEST_DIR/.freshen/transitions.log" ]
  [ ! -s "$TMUX_CALL_LOG" ]
}

@test "AGE-100: circuit breaker still suppresses expiry and dispatch" {
  freeze_clock
  pending_age 121
  echo '/forge resume' > "$TEST_DIR/.freshen/forge.signal"
  export STOP_GUARD_THRESHOLD=1
  run run_on_stop
  [ "$status" -eq 0 ]
  [[ "$output" == *"circuit breaker tripped"* ]]
  [ -f "$TEST_DIR/.freshen/.clear-pending" ]
  [ "$(cat "$TEST_DIR/.freshen/forge.signal")" = '/forge resume' ]
  [ ! -f "$TEST_DIR/.freshen/transitions.log" ]
  [ ! -s "$TMUX_CALL_LOG" ]
}
