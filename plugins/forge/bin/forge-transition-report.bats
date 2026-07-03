#!/usr/bin/env bats
# Tests for forge-transition-report.sh (agentics#33) — a read-only
# correlator over .freshen/transitions.log's "predicted"/"actual" lines.

SCRIPT="$BATS_TEST_DIRNAME/forge-transition-report.sh"

setup() {
  TEST_DIR="$(mktemp -d)"
  export TEST_DIR
  LOG="$TEST_DIR/transitions.log"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Helper: append a raw line to the fixture log (already timestamped, as the
# real transitions.log lines are).
logline() {
  printf '%s\n' "$1" >> "$LOG"
}

predicted_line() {
  local ts="$1" category="$2" dispatch="$3" tid="$4"
  logline "${ts} predicted category=${category} dispatch=\"${dispatch}\" transition_id=${tid}"
}

actual_line() {
  local ts="$1" step="$2" tid="$3"
  logline "${ts} actual step=${step} transition_id=${tid}"
}

@test "missing log file returns ok=false, not a crash" {
  run bash "$SCRIPT" "$TEST_DIR/does-not-exist.log"
  [ "$status" -eq 0 ]
  local ok
  ok="$(echo "$output" | jq -r '.ok')"
  [ "$ok" = "false" ]
}

@test "empty log returns zero counts across all buckets" {
  : > "$LOG"
  run bash "$SCRIPT" "$LOG"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.counts.matched')" = "0" ]
  [ "$(echo "$output" | jq -r '.counts.orphaned_predicted')" = "0" ]
  [ "$(echo "$output" | jq -r '.counts.orphaned_actual')" = "0" ]
}

@test "a clean matched pair is reported with mismatch=false" {
  predicted_line "2026-07-03T10:00:00Z" "pass_through" "research --orchestrated" "111-1"
  actual_line "2026-07-03T10:00:02Z" "research" "111-1"
  run bash "$SCRIPT" "$LOG"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.counts.matched')" = "1" ]
  [ "$(echo "$output" | jq -r '.matched[0].mismatch')" = "false" ]
  [ "$(echo "$output" | jq -r '.matched[0].category')" = "pass_through" ]
}

@test "a fix_loop match against the plan step is NOT flagged as a mismatch" {
  # fix_loop's dispatch is literally 'plan --orchestrated' (SKILL.md's Fix
  # Loop Handling dispatches to plan with FIX items) -- the actual step
  # legitimately being 'plan' here is correct, not a misroute.
  predicted_line "2026-07-03T10:00:00Z" "fix_loop" "plan --orchestrated" "222-2"
  actual_line "2026-07-03T10:00:05Z" "plan" "222-2"
  run bash "$SCRIPT" "$LOG"
  [ "$(echo "$output" | jq -r '.counts.mismatched')" = "0" ]
}

@test "a genuine mis-dispatch (actual step != dispatch's step) is flagged mismatch=true" {
  predicted_line "2026-07-03T10:00:00Z" "pass_through" "design --orchestrated" "333-3"
  actual_line "2026-07-03T10:00:02Z" "research" "333-3"
  run bash "$SCRIPT" "$LOG"
  [ "$(echo "$output" | jq -r '.counts.mismatched')" = "1" ]
  [ "$(echo "$output" | jq -r '.matched[0].mismatch')" = "true" ]
}

@test "a human-gate category (no step-shaped dispatch) is never flagged as a mismatch" {
  predicted_line "2026-07-03T10:00:00Z" "deploy_gate" "deploy_gate" "444-4"
  actual_line "2026-07-03T10:00:02Z" "document" "444-4"
  run bash "$SCRIPT" "$LOG"
  [ "$(echo "$output" | jq -r '.counts.mismatched')" = "0" ]
}

@test "a predicted line with no matching actual is orphaned_predicted (simulated crashed pane)" {
  predicted_line "2026-07-03T10:00:00Z" "pass_through" "execute --orchestrated" "555-5"
  run bash "$SCRIPT" "$LOG"
  [ "$(echo "$output" | jq -r '.counts.orphaned_predicted')" = "1" ]
  [ "$(echo "$output" | jq -r '.counts.matched')" = "0" ]
  [ "$(echo "$output" | jq -r '.orphaned_predicted[0].transition_id')" = "555-5" ]
}

@test "an actual line with transition_id=none is orphaned_actual (legacy/manual call site)" {
  actual_line "2026-07-03T10:00:02Z" "research" "none"
  run bash "$SCRIPT" "$LOG"
  [ "$(echo "$output" | jq -r '.counts.orphaned_actual')" = "1" ]
  [ "$(echo "$output" | jq -r '.counts.matched')" = "0" ]
}

@test "an actual line with a real but unmatched transition_id is orphaned_actual (aged-out predicted line)" {
  actual_line "2026-07-03T10:00:02Z" "research" "999-9"
  run bash "$SCRIPT" "$LOG"
  [ "$(echo "$output" | jq -r '.counts.orphaned_actual')" = "1" ]
  [ "$(echo "$output" | jq -r '.orphaned_actual[0].transition_id')" = "999-9" ]
}

@test "multiple transition_id=none actual lines are each counted, not collapsed into one" {
  actual_line "2026-07-03T10:00:02Z" "research" "none"
  actual_line "2026-07-03T10:00:03Z" "design" "none"
  run bash "$SCRIPT" "$LOG"
  [ "$(echo "$output" | jq -r '.counts.orphaned_actual')" = "2" ]
}

@test "correlates by transition_id despite interleaved lines from two concurrent sessions" {
  # Session A (PID 100) and session B (PID 200) each run a predicted+actual
  # pair, but their four lines land in the log interleaved rather than
  # grouped -- a positional-adjacency correlator would mis-pair these;
  # transition_id-based correlation must not.
  predicted_line "2026-07-03T10:00:00Z" "pass_through" "research --orchestrated" "100-1"
  predicted_line "2026-07-03T10:00:01Z" "pass_through" "design --orchestrated" "200-1"
  actual_line "2026-07-03T10:00:05Z" "design" "200-1"
  actual_line "2026-07-03T10:00:06Z" "research" "100-1"
  run bash "$SCRIPT" "$LOG"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.counts.matched')" = "2" ]
  [ "$(echo "$output" | jq -r '.counts.mismatched')" = "0" ]
  local a_step b_step
  a_step="$(echo "$output" | jq -r '.matched[] | select(.transition_id=="100-1") | .step')"
  b_step="$(echo "$output" | jq -r '.matched[] | select(.transition_id=="200-1") | .step')"
  [ "$a_step" = "research" ]
  [ "$b_step" = "design" ]
}

@test "unrelated log lines (existing F047 queue/cancel lines, freshen hook lines) are ignored, not misparsed" {
  logline "2026-07-03T10:00:00Z forge-step-exit: step 'research' -> queued next '/forge design --orchestrated' (queued=true)"
  logline "2026-07-03T10:00:01Z on-stop: found pending signal from 'forge' -- sending /clear"
  predicted_line "2026-07-03T10:00:02Z" "pass_through" "design --orchestrated" "1-1"
  actual_line "2026-07-03T10:00:03Z" "design" "1-1"
  run bash "$SCRIPT" "$LOG"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.counts.matched')" = "1" ]
}

@test "output is always valid JSON with a display summary" {
  predicted_line "2026-07-03T10:00:00Z" "pass_through" "research --orchestrated" "1-1"
  actual_line "2026-07-03T10:00:02Z" "research" "1-1"
  predicted_line "2026-07-03T10:00:03Z" "pass_through" "execute --orchestrated" "2-2"
  run bash "$SCRIPT" "$LOG"
  echo "$output" | jq . >/dev/null
  local display
  display="$(echo "$output" | jq -r '.display')"
  [[ "$display" == *"1 matched"* ]]
  [[ "$display" == *"1 orphaned predicted"* ]]
}

@test "defaults to .freshen/transitions.log relative to cwd when no argument is given" {
  mkdir -p "$TEST_DIR/.freshen"
  predicted_line_default() {
    printf '%s\n' "2026-07-03T10:00:00Z predicted category=pass_through dispatch=\"research --orchestrated\" transition_id=1-1" >> "$TEST_DIR/.freshen/transitions.log"
  }
  predicted_line_default
  run bash -c "cd '$TEST_DIR' && bash '$SCRIPT'"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.counts.orphaned_predicted')" = "1" ]
}
