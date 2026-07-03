#!/usr/bin/env bats
# Tests for freshen's on-clear.sh SessionStart(clear) hook, focused on the
# F056/F041 capture-pane confirm/retry behavior added on top of the existing
# signal-consumption and F052 .clear-pending -> .clear-consumed hand-off
# (the latter is untouched here -- see hook-guard's session-start.bats for
# its dedicated cross-plugin ordering coverage; these tests only confirm
# this script still performs the hand-off unconditionally regardless of the
# new confirm/retry outcome).
#
# tmux is shimmed (state-driven fake executable on PATH), consistent with
# this repo's existing convention for these hooks.

HOOK="$BATS_TEST_DIRNAME/on-clear.sh"
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

  # State-driven shim: capture-pane reflects $STATE_DIR/pane_content
  # (blank/confirmed by default). send-keys logs and succeeds unless
  # $STATE_DIR/send_fail_enter is set (fails only the "Enter" call -- used
  # to reproduce F041 exactly: the literal-text send succeeds, Enter fails).
  cat > "$SHIM_DIR/tmux" <<'SHIM'
#!/usr/bin/env bash
echo "$*" >> "$TMUX_CALL_LOG"
case "$1" in
  capture-pane)
    cat "$STATE_DIR/pane_content" 2>/dev/null
    exit 0
    ;;
  send-keys)
    if [ -f "$STATE_DIR/send_fail_enter" ]; then
      for a in "$@"; do
        [ "$a" = "Enter" ] && exit 1
      done
    fi
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

run_on_clear() {
  ( cd "$TEST_DIR" && \
    CLAUDE_PLUGIN_ROOT="$FRESHEN_ROOT" TMUX=1 TMUX_PANE="%1" \
    PANE_CONFIRM_ATTEMPTS="$PANE_CONFIRM_ATTEMPTS" PANE_CONFIRM_DELAY="$PANE_CONFIRM_DELAY" PANE_SEND_RETRIES="$PANE_SEND_RETRIES" \
    STATE_DIR="$STATE_DIR" TMUX_CALL_LOG="$TMUX_CALL_LOG" \
    bash "$HOOK" < /dev/null )
}

@test "no .clear-pending (user-initiated /clear): does not process any signal" {
  echo "/forge resume" > "$TEST_DIR/.freshen/forge.signal"
  run run_on_clear
  [ "$status" -eq 0 ]
  [ ! -s "$TMUX_CALL_LOG" ]
  [ -f "$TEST_DIR/.freshen/forge.signal" ]
}

@test ".clear-pending but no signal file: hands off to .clear-consumed and exits" {
  touch "$TEST_DIR/.freshen/.clear-pending"
  run run_on_clear
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_DIR/.freshen/.clear-pending" ]
  [ -f "$TEST_DIR/.freshen/.clear-consumed" ]
  [ ! -s "$TMUX_CALL_LOG" ]
}

@test "F056: confirmed re-invoke deletes the signal, hands off clear-pending, and logs the transition" {
  touch "$TEST_DIR/.freshen/.clear-pending"
  echo "/forge resume" > "$TEST_DIR/.freshen/forge.signal"
  : > "$STATE_DIR/pane_content"
  run run_on_clear
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_DIR/.freshen/forge.signal" ]
  [ ! -f "$TEST_DIR/.freshen/.clear-pending" ]
  [ -f "$TEST_DIR/.freshen/.clear-consumed" ]
  [ "$(send_count)" = "2" ]
  run grep -c "sending re-invoke '/forge resume'" "$TEST_DIR/.freshen/transitions.log"
  [ "$output" = "1" ]
  run grep -c 'signal consumed' "$TEST_DIR/.freshen/transitions.log"
  [ "$output" = "1" ]
}

@test "F041: a failing Enter send does NOT delete the signal, even though the literal-text send succeeded" {
  # Reproduces F041's exact original scenario: the first send-keys call
  # (the literal command text) succeeds; the follow-up Enter fails. The old
  # code gated `rm "$SIGNAL"` only on the first call succeeding and deleted
  # it anyway -- stranding the pipeline with the command typed but never
  # submitted and no signal left to retry from.
  touch "$TEST_DIR/.freshen/.clear-pending"
  echo "/forge resume" > "$TEST_DIR/.freshen/forge.signal"
  touch "$STATE_DIR/send_fail_enter"
  echo "/forge resume" > "$STATE_DIR/pane_content"
  run run_on_clear
  [ "$status" -eq 0 ]
  [ -f "$TEST_DIR/.freshen/forge.signal" ]
  # F052's hand-off must still fire regardless of the re-invoke outcome.
  [ ! -f "$TEST_DIR/.freshen/.clear-pending" ]
  [ -f "$TEST_DIR/.freshen/.clear-consumed" ]
  [[ "$output" == *"WARNING"*"unconfirmed"* ]]
}

@test "F056: unconfirmed after retries (busy pane) leaves the signal in place and hands off clear-pending" {
  touch "$TEST_DIR/.freshen/.clear-pending"
  echo "/forge resume" > "$TEST_DIR/.freshen/forge.signal"
  echo "/forge resume" > "$STATE_DIR/pane_content"
  run run_on_clear
  [ "$status" -eq 0 ]
  [ -f "$TEST_DIR/.freshen/forge.signal" ]
  [ -f "$TEST_DIR/.freshen/.clear-consumed" ]
  run grep -c 'unconfirmed after retries' "$TEST_DIR/.freshen/transitions.log"
  [ "$output" = "1" ]
}

@test "no tmux env: hands off clear-pending, leaves the signal untouched" {
  touch "$TEST_DIR/.freshen/.clear-pending"
  echo "/forge resume" > "$TEST_DIR/.freshen/forge.signal"
  run bash -c "cd '$TEST_DIR' && env -u TMUX -u TMUX_PANE CLAUDE_PLUGIN_ROOT='$FRESHEN_ROOT' bash '$HOOK' < /dev/null"
  [ "$status" -eq 0 ]
  [ ! -s "$TMUX_CALL_LOG" ]
  [ -f "$TEST_DIR/.freshen/forge.signal" ]
  [ ! -f "$TEST_DIR/.freshen/.clear-pending" ]
  [ -f "$TEST_DIR/.freshen/.clear-consumed" ]
}

@test "the oldest of multiple pending signals is processed first" {
  touch "$TEST_DIR/.freshen/.clear-pending"
  echo "/other resume" > "$TEST_DIR/.freshen/other.signal"
  echo "/forge resume" > "$TEST_DIR/.freshen/forge.signal"
  # Backdate forge.signal so it's unambiguously older than other.signal
  # without sleeping in the test.
  past="$(date -v-1M +%Y%m%d%H%M.%S 2>/dev/null || date -d '1 minute ago' +%Y%m%d%H%M.%S)"
  touch -t "$past" "$TEST_DIR/.freshen/forge.signal"
  : > "$STATE_DIR/pane_content"
  run run_on_clear
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_DIR/.freshen/forge.signal" ]
  [ -f "$TEST_DIR/.freshen/other.signal" ]
}
