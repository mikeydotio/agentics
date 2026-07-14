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
  #
  # Opt-in virtual input box ($STATE_DIR/box_mode, issue #86) — additive, and
  # untouched by every test above that never creates the file. Modeled on
  # plugins/issue/tests/fakes/tmux: a paste (`send-keys -l <text>` or a bare
  # `send-keys <text>` with no Enter) APPENDS to $STATE_DIR/box; `send-keys
  # Enter` SUBMITS (clears the box) unless $STATE_DIR/enter_absorb holds a
  # positive count, in which case the next that-many Enters are ABSORBED
  # (decrement, do NOT clear) — the exact #82 swallowed-submit race. In
  # box_mode, capture-pane renders the box AS the last non-blank line ("> <box>"
  # when non-empty) so pane_text_still_pending reacts: still-pending while the
  # box holds text, confirmed once it clears. This is a deliberately NON-vacuous
  # fixture (production's real TUI footer-below-the-box makes the last-line
  # check vacuous) — here we are driving the resend MECHANICS, so the box must
  # be observable. It lets a test assert the text is pasted EXACTLY once even
  # across an absorbed-Enter resend (the #86 no-re-paste guarantee).
  cat > "$SHIM_DIR/tmux" <<'SHIM'
#!/usr/bin/env bash
echo "$*" >> "$TMUX_CALL_LOG"
case "$1" in
  capture-pane)
    [ -f "$STATE_DIR/capture_fail" ] && exit 1
    if [ -f "$STATE_DIR/box_mode" ]; then
      box="$(cat "$STATE_DIR/box" 2>/dev/null || printf '')"
      printf 'some prior output\n'
      [ -n "$box" ] && printf '> %s\n' "$box"
      exit 0
    fi
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
    # box_mode: mutate the virtual input box so absorbed-Enter / no-re-paste
    # behavior is observable (a failed send above never reaches here, matching
    # real tmux — a rejected send-keys delivers nothing).
    if [ -f "$STATE_DIR/box_mode" ]; then
      shift || true                       # drop the leading "send-keys"
      has_l=false; ltext=""; is_enter=false; bare=""
      while [ "$#" -gt 0 ]; do
        case "$1" in
          -t) shift || true ;;            # drop the pane target (next arg)
          -l) has_l=true; shift || true; ltext="${1-}" ;;
          Enter) is_enter=true ;;
          *) bare="$1" ;;
        esac
        shift || true
      done
      if [ "$has_l" = true ]; then
        printf '%s' "$ltext" >> "$STATE_DIR/box" 2>/dev/null || true
      elif [ "$is_enter" = true ]; then
        absorb="$(cat "$STATE_DIR/enter_absorb" 2>/dev/null || printf '0')"
        if [ "${absorb:-0}" -gt 0 ] 2>/dev/null; then
          printf '%s' "$((absorb - 1))" > "$STATE_DIR/enter_absorb" 2>/dev/null || true
        else
          : > "$STATE_DIR/box" 2>/dev/null || true
        fi
      elif [ -n "$bare" ]; then
        printf '%s' "$bare" >> "$STATE_DIR/box" 2>/dev/null || true
      fi
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

  # Keep tests fast — a handful of near-zero-delay polls/retries, and no real
  # settle sleep between a paste and its Enter.
  export PANE_CONFIRM_ATTEMPTS=3
  export PANE_CONFIRM_DELAY=0.01
  export PANE_SEND_RETRIES=2
  export PANE_PASTE_SETTLE_DELAY=0

  # shellcheck source=plugins/freshen/lib/pane-confirm.sh
  . "$LIB"
}

teardown() {
  rm -rf "$TEST_DIR"
}

send_count() {
  grep -c '^send-keys' "$TMUX_CALL_LOG" || true
}

# Count logged send-keys lines containing a fixed substring — used by the
# box_mode (#86) tests to count PASTES vs ENTERS separately off the call log
# (a paste line carries the text, e.g. "-l /forge resume" or "%1 /clear"; a
# submit line ends in "Enter").
log_count() {
  grep -c -F -- "$1" "$TMUX_CALL_LOG" || true
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
  # Keys mode now delivers the text and Enter as SEPARATE send-keys calls (so
  # the Enter can be resent alone on a swallowed submit, #86): 1 paste + 1
  # Enter = 2.
  [ "$(send_count)" = "2" ]
}

@test "pane_send_and_confirm (keys): resends the PASTE when the first send-keys call errors outright" {
  echo 1 > "$STATE_DIR/send_fail_on_call"
  : > "$STATE_DIR/pane_content"
  run pane_send_and_confirm "%1" keys "/clear"
  [ "$status" -eq 0 ]
  # First paste failed (nothing landed -> safe to repeat): paste, paste, Enter.
  [ "$(send_count)" = "3" ]
}

@test "pane_send_and_confirm (keys): gives up after exhausting all Enter resends against a permanently stuck pane" {
  echo "/clear" > "$STATE_DIR/pane_content"
  run pane_send_and_confirm "%1" keys "/clear"
  [ "$status" -eq 1 ]
  # The paste lands ONCE; only the Enter is retried. 1 paste + (original Enter +
  # PANE_SEND_RETRIES(2) Enter resends) = 1 + 3 = 4 send-keys calls total. The
  # text is never re-pasted (the #86 guarantee), even under total submit failure.
  [ "$(send_count)" = "4" ]
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

# --- issue #86: a swallowed Enter must re-send ENTER ALONE, never re-paste ---
# These use the opt-in virtual input box (box_mode) so an absorbed Enter and the
# resulting resend are observable. enter_absorb=1 swallows the first prompt
# Enter (the exact #82 race); the fix must recover by pressing Enter again
# WITHOUT re-pasting the text.

@test "pane_send_and_confirm (literal): recovers a swallowed Enter by re-sending ENTER ALONE — never re-pastes (#86)" {
  touch "$STATE_DIR/box_mode"
  : > "$STATE_DIR/box"
  echo 1 > "$STATE_DIR/enter_absorb"
  run pane_send_and_confirm "%1" literal "/forge resume"
  [ "$status" -eq 0 ]
  # THE point of #86: the text is pasted EXACTLY once even though the first
  # Enter was absorbed and a second was needed. The old re-paste-on-retry code
  # pastes it twice here (RED).
  [ "$(log_count '-l /forge resume')" = "1" ]
  # Two Enters: the absorbed one + the recovering one.
  [ "$(log_count '%1 Enter')" = "2" ]
  # Box cleared -> submission confirmed.
  [ ! -s "$STATE_DIR/box" ]
}

@test "pane_send_and_confirm (keys): recovers a swallowed Enter for /clear, /clear typed exactly once (#86)" {
  touch "$STATE_DIR/box_mode"
  : > "$STATE_DIR/box"
  echo 1 > "$STATE_DIR/enter_absorb"
  run pane_send_and_confirm "%1" keys "/clear"
  [ "$status" -eq 0 ]
  # /clear appears on exactly one paste line (never on an Enter line).
  [ "$(log_count '%1 /clear')" = "1" ]
  [ "$(log_count '%1 Enter')" = "2" ]
  [ ! -s "$STATE_DIR/box" ]
}

@test "pane_send_and_confirm (literal): a submit that never lands gives up after re-sending ENTER only — prompt still pasted once (#86)" {
  touch "$STATE_DIR/box_mode"
  : > "$STATE_DIR/box"
  # Absorb far more Enters than we will ever send -> submission never lands.
  echo 99 > "$STATE_DIR/enter_absorb"
  run pane_send_and_confirm "%1" literal "/forge resume"
  [ "$status" -eq 1 ]
  # Paste-once holds even under total submit failure.
  [ "$(log_count '-l /forge resume')" = "1" ]
  # Original Enter + PANE_SEND_RETRIES(2) resends = 3 Enter attempts.
  [ "$(log_count '%1 Enter')" = "3" ]
  # The command is still sitting unsubmitted in the box.
  [ -s "$STATE_DIR/box" ]
}
