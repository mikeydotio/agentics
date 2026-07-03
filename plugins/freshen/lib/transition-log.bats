#!/usr/bin/env bats
# Tests for lib/transition-log.sh — the lightweight append-only audit log
# behind F047 (post-hoc diagnosis of a stalled auto-resume cycle).

LIB="$BATS_TEST_DIRNAME/transition-log.sh"

setup() {
  TEST_DIR="$(mktemp -d)"
  export TEST_DIR
  export FRESHEN_LOG_DIR="$TEST_DIR/.freshen"
  # shellcheck source=plugins/freshen/lib/transition-log.sh
  . "$LIB"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "appends one timestamped line per call" {
  freshen_log_transition "on-stop: sent /clear"
  freshen_log_transition "on-clear: sent re-invoke"
  [ -f "$FRESHEN_LOG_DIR/transitions.log" ]
  [ "$(wc -l < "$FRESHEN_LOG_DIR/transitions.log" | tr -d ' ')" = "2" ]
  run grep -c 'on-stop: sent /clear' "$FRESHEN_LOG_DIR/transitions.log"
  [ "$output" = "1" ]
  run grep -c 'on-clear: sent re-invoke' "$FRESHEN_LOG_DIR/transitions.log"
  [ "$output" = "1" ]
}

@test "each line is prefixed with an ISO-8601 UTC timestamp" {
  freshen_log_transition "test message"
  run head -1 "$FRESHEN_LOG_DIR/transitions.log"
  [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\ test\ message$ ]]
}

@test "creates the log directory if it does not already exist" {
  [ ! -d "$FRESHEN_LOG_DIR" ]
  freshen_log_transition "first line"
  [ -d "$FRESHEN_LOG_DIR" ]
}

@test "preserves line order (oldest first)" {
  freshen_log_transition "first"
  freshen_log_transition "second"
  freshen_log_transition "third"
  run sed -n '1p' "$FRESHEN_LOG_DIR/transitions.log"
  [[ "$output" == *"first" ]]
  run sed -n '3p' "$FRESHEN_LOG_DIR/transitions.log"
  [[ "$output" == *"third" ]]
}

@test "trims to the most recent FRESHEN_LOG_MAX_LINES lines once the cap is exceeded" {
  export FRESHEN_LOG_MAX_LINES=5
  for i in 1 2 3 4 5 6 7 8; do
    freshen_log_transition "line $i"
  done
  [ "$(wc -l < "$FRESHEN_LOG_DIR/transitions.log" | tr -d ' ')" = "5" ]
  # The oldest 3 lines (1-3) must be gone; the most recent 5 (4-8) survive.
  run grep -c 'line 1$' "$FRESHEN_LOG_DIR/transitions.log"
  [ "$output" = "0" ]
  run grep -c 'line 8$' "$FRESHEN_LOG_DIR/transitions.log"
  [ "$output" = "1" ]
}

@test "a logging failure (directory path occupied by a file) is swallowed, never fails the caller" {
  # Put a plain FILE where the log directory should be, so `mkdir -p` fails.
  rm -rf "$FRESHEN_LOG_DIR"
  : > "$FRESHEN_LOG_DIR"
  run freshen_log_transition "should not crash"
  [ "$status" -eq 0 ]
}
