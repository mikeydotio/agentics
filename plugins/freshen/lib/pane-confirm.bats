#!/usr/bin/env bats
# Tests for lib/pane-confirm.sh — the capture-pane confirm/retry helpers
# behind F045 (verified /clear + re-invoke), F041 (signal not deleted until
# truly accepted), and F056 (bounded retry instead of blind fire-and-forget).
#
# tmux itself is shimmed (a fake executable on PATH, state-driven via plain
# files) rather than requiring a live tmux session — consistent with this
# repo's existing convention for these exact hooks (see
# plugins/forge/hooks/session-stop.bats's header comment). The shim is
# state-driven rather than a fixed canned response so tests can simulate a
# pane that never reacts, one that reacts after N polls, and one whose
# send-keys itself fails outright — the three failure classes F045/F056 care
# about.

LIB="$BATS_TEST_DIRNAME/pane-confirm.sh"

setup() {
  TEST_DIR="$(mktemp -d)"
  export TEST_DIR
  SHIM_DIR="$TEST_DIR/shim"
  mkdir -p "$SHIM_DIR"
  export STATE_DIR="$TEST_DIR/state"
  mkdir -p "$STATE_DIR"
  TMUX_CALL_LOG="$TEST_DIR/tmux-calls.log"
  export TMUX_CALL_LOG
  touch "$TMUX_CALL_LOG"

  # Default shim: capture-pane returns whatever is in $STATE_DIR/pane_content
  # (empty/blank if absent — i.e. "confirmed" by default) unless
  # $STATE_DIR/capture_fail exists (capture-pane always errors) or
  # $STATE_DIR/polls_until_clear holds a positive count (capture-pane
  # returns $STATE_DIR/pane_content_pending and decrements the counter for
  # that many calls, then switches to the settled pane_content). send-keys
  # logs and exits 0 unless $STATE_DIR/send_fail exists (always fails) or
  # $STATE_DIR/send_fail_on_call names a 1-indexed call number to fail.
  cat > "$SHIM_DIR/tmux" <<'SHIM'
#!/usr/bin/env bash
echo "$*" >> "$TMUX_CALL_LOG"
case "$1" in
  capture-pane)
    [ -f "$STATE_DIR/capture_fail" ] && exit 1
    if [ -f "$STATE_DIR/polls_until_clear" ]; then
      n="$(cat "$STATE_DIR/polls_until_clear")"
      if [ "$n" -gt 0 ]; then
        echo "$((n - 1))" > "$STATE_DIR/polls_until_clear"
        cat "$STATE_DIR/pane_content_pending" 2>/dev/null
        exit 0
      fi
    fi
    cat "$STATE_DIR/pane_content" 2>/dev/null
    exit 0
    ;;
  send-keys)
    COUNT_FILE="$STATE_DIR/send_call_count"
    n=0
    [ -f "$COUNT_FILE" ] && n="$(cat "$COUNT_FILE")"
    n=$((n + 1))
    echo "$n" > "$COUNT_FILE"
    [ -f "$STATE_DIR/send_fail" ] && exit 1
    if [ -f "$STATE_DIR/send_fail_on_call" ] && [ "$n" -eq "$(cat "$STATE_DIR/send_fail_on_call")" ]; then
      exit 1
    fi
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

  # Keep tests fast — a handful of near-zero-delay polls/retries.
  export PANE_CONFIRM_ATTEMPTS=3
  export PANE_CONFIRM_DELAY=0.01
  export PANE_SEND_RETRIES=2

  # shellcheck source=plugins/freshen/lib/pane-confirm.sh
  . "$LIB"
}

teardown() {
  rm -rf "$TEST_DIR"
}

send_count() {
  grep -c '^send-keys' "$TMUX_CALL_LOG" || true
}

# --- pane_text_still_pending ---

@test "pane_text_still_pending: true when the text sits unsubmitted on the last line" {
  printf 'some prior output\n/clear' > "$STATE_DIR/pane_content"
  run pane_text_still_pending "%1" "/clear"
  [ "$status" -eq 0 ]
}

@test "pane_text_still_pending: false when the text is gone from the last line" {
  printf 'some prior output\n> \n' > "$STATE_DIR/pane_content"
  run pane_text_still_pending "%1" "/clear"
  [ "$status" -eq 1 ]
}

@test "pane_text_still_pending: false (confirmed) when the pane is entirely blank" {
  : > "$STATE_DIR/pane_content"
  run pane_text_still_pending "%1" "/clear"
  [ "$status" -eq 1 ]
}

@test "pane_text_still_pending: true (cannot confirm) when capture-pane itself fails" {
  touch "$STATE_DIR/capture_fail"
  run pane_text_still_pending "%1" "/clear"
  [ "$status" -eq 0 ]
}

# --- pane_wait_confirmed ---

@test "pane_wait_confirmed: returns immediately when already not pending" {
  : > "$STATE_DIR/pane_content"
  run pane_wait_confirmed "%1" "/clear"
  [ "$status" -eq 0 ]
  # Exactly one capture-pane call -- no unnecessary polling once confirmed.
  [ "$(grep -c '^capture-pane' "$TMUX_CALL_LOG")" = "1" ]
}

@test "pane_wait_confirmed: converges once the pane clears after a couple of polls" {
  echo "/clear" > "$STATE_DIR/pane_content_pending"
  : > "$STATE_DIR/pane_content"
  echo 2 > "$STATE_DIR/polls_until_clear"
  run pane_wait_confirmed "%1" "/clear"
  [ "$status" -eq 0 ]
  # Two pending polls, then the third call sees it cleared.
  [ "$(grep -c '^capture-pane' "$TMUX_CALL_LOG")" = "3" ]
}

@test "pane_wait_confirmed: gives up after PANE_CONFIRM_ATTEMPTS if never confirmed" {
  echo "/clear" > "$STATE_DIR/pane_content"
  run pane_wait_confirmed "%1" "/clear"
  [ "$status" -eq 1 ]
  [ "$(grep -c '^capture-pane' "$TMUX_CALL_LOG")" = "3" ]
}

# --- pane_send_and_confirm ---

@test "pane_send_and_confirm (keys): confirms on the first attempt, no resend" {
  : > "$STATE_DIR/pane_content"
  run pane_send_and_confirm "%1" keys "/clear"
  [ "$status" -eq 0 ]
  [ "$(send_count)" = "1" ]
}

@test "pane_send_and_confirm (keys): resends when the first send-keys call errors outright" {
  echo 1 > "$STATE_DIR/send_fail_on_call"
  : > "$STATE_DIR/pane_content"
  run pane_send_and_confirm "%1" keys "/clear"
  [ "$status" -eq 0 ]
  # First send-keys call failed (never counted as "sent" -> no poll for it);
  # the resend on the second call succeeds and confirms immediately.
  [ "$(send_count)" = "2" ]
}

@test "pane_send_and_confirm (keys): gives up after exhausting all resends against a permanently stuck pane" {
  echo "/clear" > "$STATE_DIR/pane_content"
  run pane_send_and_confirm "%1" keys "/clear"
  [ "$status" -eq 1 ]
  # Original send + PANE_SEND_RETRIES(2) resends = 3 send-keys calls total.
  [ "$(send_count)" = "3" ]
}

@test "pane_send_and_confirm (literal): requires BOTH the literal send AND Enter to succeed (F041)" {
  # The literal-text send always succeeds; the follow-up Enter always fails.
  # This must NOT be treated as sent -- reproduces F041's exact scenario
  # (the old on-clear.sh gated its `rm "$SIGNAL"` only on the first call).
  # A single attempt (no resend) isolates the gate itself from the retry
  # loop's own behavior, tested separately below.
  export PANE_SEND_RETRIES=0
  touch "$STATE_DIR/send_fail_enter"
  echo "/forge resume" > "$STATE_DIR/pane_content"
  run pane_send_and_confirm "%1" literal "/forge resume"
  [ "$status" -eq 1 ]
  [ "$(send_count)" = "2" ]
}

@test "pane_send_and_confirm (literal): a failing literal-text send also prevents Enter from being reached, and a later resend recovers" {
  # Attempt 1's literal-text call (the very first send-keys call) fails
  # outright -- the follow-up Enter must never even be attempted for that
  # attempt (short-circuit). Attempt 2's literal+Enter both succeed against
  # an already-clear pane.
  echo 1 > "$STATE_DIR/send_fail_on_call"
  : > "$STATE_DIR/pane_content"
  run pane_send_and_confirm "%1" literal "/forge resume"
  [ "$status" -eq 0 ]
  [ "$(send_count)" = "3" ]
}

@test "pane_send_and_confirm (literal): confirms once both sends succeed and the pane clears" {
  : > "$STATE_DIR/pane_content"
  run pane_send_and_confirm "%1" literal "/forge resume"
  [ "$status" -eq 0 ]
  [ "$(send_count)" = "2" ]
}
