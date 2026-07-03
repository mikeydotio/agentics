#!/usr/bin/env bats
# Tests for forge-loop-state.sh — the deterministic .forge/state.json
# bookkeeping script that replaces execution-loop.md's per-iteration prose
# arithmetic (F003, F031, F037, F093, F097, F098).

SCRIPT="$BATS_TEST_DIRNAME/forge-loop-state.sh"

setup() {
  TEST_DIR="$(mktemp -d)"
  FORGE_DIR="$TEST_DIR/.forge"
  mkdir -p "$FORGE_DIR"
}

teardown() {
  rm -rf "$TEST_DIR"
}

jq_field() {
  echo "$output" | jq -r "$1"
}

# --- attempt ---

@test "attempt: increments stories_attempted from zero" {
  run bash "$SCRIPT" attempt --forge-dir "$FORGE_DIR"
  [ "$status" -eq 0 ]
  [ "$(jq_field '.ok')" = "true" ]
  [ "$(jq_field '.stories_attempted')" = "1" ]
  [ "$(jq -r '.stories_attempted' "$FORGE_DIR/state.json")" = "1" ]
  [ "$(jq -r '.updated_at' "$FORGE_DIR/state.json")" != "null" ]
}

@test "attempt: accumulates across repeated calls" {
  bash "$SCRIPT" attempt --forge-dir "$FORGE_DIR" >/dev/null
  bash "$SCRIPT" attempt --forge-dir "$FORGE_DIR" >/dev/null
  run bash "$SCRIPT" attempt --forge-dir "$FORGE_DIR"
  [ "$(jq_field '.stories_attempted')" = "3" ]
}

@test "attempt: preserves other state.json fields already on disk" {
  echo '{"sessions_completed": 5}' > "$FORGE_DIR/state.json"
  run bash "$SCRIPT" attempt --forge-dir "$FORGE_DIR"
  [ "$(jq -r '.sessions_completed' "$FORGE_DIR/state.json")" = "5" ]
  [ "$(jq -r '.stories_attempted' "$FORGE_DIR/state.json")" = "1" ]
}

@test "attempt: malformed state.json is treated as empty, not a crash" {
  echo 'not json' > "$FORGE_DIR/state.json"
  run bash "$SCRIPT" attempt --forge-dir "$FORGE_DIR"
  [ "$status" -eq 0 ]
  [ "$(jq_field '.stories_attempted')" = "1" ]
}

# --- done ---

@test "done: reports session_limit_hit false under default max_stories_per_session=1 before completion" {
  echo '{"stories_this_session": 0}' > "$FORGE_DIR/state.json"
  # default max_stories_per_session is 1, so a single 'done' call already hits it
  run bash "$SCRIPT" done --forge-dir "$FORGE_DIR"
  [ "$(jq_field '.stories_this_session')" = "1" ]
  [ "$(jq_field '.session_limit_hit')" = "true" ]
}

@test "done: session_limit_hit is false while under a higher configured max" {
  echo '{"max_stories_per_session": 3}' > "$FORGE_DIR/config.json"
  run bash "$SCRIPT" done --forge-dir "$FORGE_DIR"
  [ "$(jq_field '.stories_this_session')" = "1" ]
  [ "$(jq_field '.max_stories_per_session')" = "3" ]
  [ "$(jq_field '.session_limit_hit')" = "false" ]
}

@test "done: session_limit_hit flips true once the configured max is reached" {
  echo '{"max_stories_per_session": 2}' > "$FORGE_DIR/config.json"
  bash "$SCRIPT" done --forge-dir "$FORGE_DIR" >/dev/null
  run bash "$SCRIPT" done --forge-dir "$FORGE_DIR"
  [ "$(jq_field '.stories_this_session')" = "2" ]
  [ "$(jq_field '.session_limit_hit')" = "true" ]
}

# --- retry ---

@test "retry: requires --story-id" {
  run bash "$SCRIPT" retry --forge-dir "$FORGE_DIR"
  [ "$status" -ne 0 ]
}

@test "retry: first failure returns action=retry and increments both counters" {
  run bash "$SCRIPT" retry --story-id ST-1 --forge-dir "$FORGE_DIR"
  [ "$(jq_field '.action')" = "retry" ]
  [ "$(jq_field '.retry_count')" = "1" ]
  [ "$(jq_field '.total_retries')" = "1" ]
  [ "$(jq -r '.retry_counts["ST-1"]' "$FORGE_DIR/state.json")" = "1" ]
}

@test "retry: tracks independent counters per story-id" {
  bash "$SCRIPT" retry --story-id ST-1 --forge-dir "$FORGE_DIR" >/dev/null
  bash "$SCRIPT" retry --story-id ST-1 --forge-dir "$FORGE_DIR" >/dev/null
  run bash "$SCRIPT" retry --story-id ST-2 --forge-dir "$FORGE_DIR"
  [ "$(jq_field '.retry_count')" = "1" ]
  [ "$(jq_field '.total_retries')" = "3" ]
  [ "$(jq -r '.retry_counts["ST-1"]' "$FORGE_DIR/state.json")" = "2" ]
  [ "$(jq -r '.retry_counts["ST-2"]' "$FORGE_DIR/state.json")" = "1" ]
}

@test "retry: action flips to block once retry_count reaches configured max_retries" {
  echo '{"max_retries": 2}' > "$FORGE_DIR/config.json"
  bash "$SCRIPT" retry --story-id ST-1 --forge-dir "$FORGE_DIR" >/dev/null
  run bash "$SCRIPT" retry --story-id ST-1 --forge-dir "$FORGE_DIR"
  [ "$(jq_field '.retry_count')" = "2" ]
  [ "$(jq_field '.max_retries')" = "2" ]
  [ "$(jq_field '.action')" = "block" ]
}

@test "retry: default max_retries is 4 when config.json is absent" {
  run bash "$SCRIPT" retry --story-id ST-1 --forge-dir "$FORGE_DIR"
  [ "$(jq_field '.max_retries')" = "4" ]
}

# --- runaway-check ---

@test "runaway-check: halt false on a fresh state.json" {
  run bash "$SCRIPT" runaway-check --forge-dir "$FORGE_DIR"
  [ "$(jq_field '.halt')" = "false" ]
  [ "$(jq_field '.reason')" = "" ]
}

@test "runaway-check: halts once sessions_completed reaches max_sessions" {
  echo '{"max_sessions": 3}' > "$FORGE_DIR/config.json"
  echo '{"sessions_completed": 3}' > "$FORGE_DIR/state.json"
  run bash "$SCRIPT" runaway-check --forge-dir "$FORGE_DIR"
  [ "$(jq_field '.halt')" = "true" ]
  [[ "$(jq_field '.reason')" == *"max_sessions"* ]]
}

@test "runaway-check: halts once total_retries reaches max_total_retries" {
  echo '{"max_total_retries": 10}' > "$FORGE_DIR/config.json"
  echo '{"total_retries": 10}' > "$FORGE_DIR/state.json"
  run bash "$SCRIPT" runaway-check --forge-dir "$FORGE_DIR"
  [ "$(jq_field '.halt')" = "true" ]
  [[ "$(jq_field '.reason')" == *"max_total_retries"* ]]
}

@test "runaway-check: default max_total_retries is 100, not 20" {
  # F097 — the un-reconciled default (20) trips on any plan with more than a
  # handful of story-level retries; 100 gives realistic multi-wave plans
  # headroom to complete. See skills/forge/SKILL.md's Settings section.
  run bash "$SCRIPT" runaway-check --forge-dir "$FORGE_DIR"
  [ "$(jq_field '.max_total_retries')" = "100" ]
}

@test "runaway-check: halts on 3 persisted consecutive storyhook failures" {
  echo '{"storyhook_consecutive_failures": 3}' > "$FORGE_DIR/state.json"
  run bash "$SCRIPT" runaway-check --forge-dir "$FORGE_DIR"
  [ "$(jq_field '.halt')" = "true" ]
  [[ "$(jq_field '.reason')" == *"storyhook"* ]]
}

@test "runaway-check: does not mutate state.json (read-only)" {
  echo '{"total_retries": 1}' > "$FORGE_DIR/state.json"
  bash "$SCRIPT" runaway-check --forge-dir "$FORGE_DIR" >/dev/null
  [ "$(jq -r '.total_retries' "$FORGE_DIR/state.json")" = "1" ]
}

# --- storyhook-failure (F093: persisted consecutive-failure counter) ---

@test "storyhook-failure: requires --result to be ok or fail" {
  run bash "$SCRIPT" storyhook-failure --result bogus --forge-dir "$FORGE_DIR"
  [ "$status" -ne 0 ]
}

@test "storyhook-failure: fail increments the persisted counter" {
  run bash "$SCRIPT" storyhook-failure --result fail --forge-dir "$FORGE_DIR"
  [ "$(jq_field '.storyhook_consecutive_failures')" = "1" ]
  [ "$(jq -r '.storyhook_consecutive_failures' "$FORGE_DIR/state.json")" = "1" ]
}

@test "storyhook-failure: ok resets the counter to zero" {
  echo '{"storyhook_consecutive_failures": 2}' > "$FORGE_DIR/state.json"
  run bash "$SCRIPT" storyhook-failure --result ok --forge-dir "$FORGE_DIR"
  [ "$(jq_field '.storyhook_consecutive_failures')" = "0" ]
}

@test "storyhook-failure: halt becomes true at 3 consecutive failures, survives a fresh process" {
  bash "$SCRIPT" storyhook-failure --result fail --forge-dir "$FORGE_DIR" >/dev/null
  bash "$SCRIPT" storyhook-failure --result fail --forge-dir "$FORGE_DIR" >/dev/null
  # Third call is a brand-new process -- this is the whole point of F093:
  # the counter must survive a fresh re-read, not just live in one process.
  run bash "$SCRIPT" storyhook-failure --result fail --forge-dir "$FORGE_DIR"
  [ "$(jq_field '.storyhook_consecutive_failures')" = "3" ]
  [ "$(jq_field '.halt')" = "true" ]
}

# --- architect-check (F098: persisted drift-review counter) ---

@test "architect-check: requires --wave-boundary to be true or false" {
  run bash "$SCRIPT" architect-check --wave-boundary maybe --forge-dir "$FORGE_DIR"
  [ "$status" -ne 0 ]
}

@test "architect-check: does not trigger before 3 stories and no wave boundary" {
  run bash "$SCRIPT" architect-check --wave-boundary false --forge-dir "$FORGE_DIR"
  [ "$(jq_field '.trigger')" = "false" ]
  [ "$(jq_field '.stories_since_last_architect_review')" = "1" ]
}

@test "architect-check: triggers and resets at the 3rd persisted call, across fresh processes" {
  bash "$SCRIPT" architect-check --wave-boundary false --forge-dir "$FORGE_DIR" >/dev/null
  bash "$SCRIPT" architect-check --wave-boundary false --forge-dir "$FORGE_DIR" >/dev/null
  # A fresh process each time -- the persisted counter (not conversation
  # memory) is what makes this reachable under max_stories_per_session=1.
  run bash "$SCRIPT" architect-check --wave-boundary false --forge-dir "$FORGE_DIR"
  [ "$(jq_field '.trigger')" = "true" ]
  [ "$(jq_field '.stories_since_last_architect_review')" = "0" ]
}

@test "architect-check: a wave boundary triggers immediately regardless of the counter" {
  run bash "$SCRIPT" architect-check --wave-boundary true --forge-dir "$FORGE_DIR"
  [ "$(jq_field '.trigger')" = "true" ]
  [ "$(jq_field '.stories_since_last_architect_review')" = "0" ]
}

@test "architect-check: counter resumes correctly after a prior trigger" {
  bash "$SCRIPT" architect-check --wave-boundary true --forge-dir "$FORGE_DIR" >/dev/null
  run bash "$SCRIPT" architect-check --wave-boundary false --forge-dir "$FORGE_DIR"
  [ "$(jq_field '.stories_since_last_architect_review')" = "1" ]
  [ "$(jq_field '.trigger')" = "false" ]
}

# --- Unknown subcommand ---

@test "unknown subcommand returns ok:false and a nonzero exit" {
  run bash "$SCRIPT" bogus --forge-dir "$FORGE_DIR"
  [ "$status" -ne 0 ]
  [ "$(jq_field '.ok')" = "false" ]
}

# --- Output is always valid JSON ---

@test "every subcommand's output is valid JSON" {
  for args in "attempt" "done" "retry --story-id ST-1" "runaway-check" "storyhook-failure --result ok" "architect-check --wave-boundary false"; do
    run bash "$SCRIPT" $args --forge-dir "$FORGE_DIR"
    echo "$output" | jq . >/dev/null 2>&1
  done
}
