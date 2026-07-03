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
}

teardown() {
  rm -rf "$TEST_DIR"
}

send_count() {
  grep -c '^send-keys' "$TMUX_CALL_LOG" || true
}

run_on_stop() {
  ( cd "$TEST_DIR" && \
    CLAUDE_PLUGIN_ROOT="$FRESHEN_ROOT" TMUX=1 TMUX_PANE="%1" \
    PANE_CONFIRM_ATTEMPTS="$PANE_CONFIRM_ATTEMPTS" PANE_CONFIRM_DELAY="$PANE_CONFIRM_DELAY" PANE_SEND_RETRIES="$PANE_SEND_RETRIES" \
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
  [ "$(send_count)" = "1" ]
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
