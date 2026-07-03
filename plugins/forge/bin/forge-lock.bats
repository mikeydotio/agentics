#!/usr/bin/env bats
# Tests for forge-lock.sh — the deterministic .forge/lock.json session-locking
# protocol that replaces references/session-locking.md's prose heartbeat
# staleness math (F030).

SCRIPT="$BATS_TEST_DIRNAME/forge-lock.sh"

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

write_stale_lock() {
  # A heartbeat_at far enough in the past to be stale under any reasonable
  # window-min without depending on wall-clock timing in the test itself.
  jq -n --arg holder "$1" \
    '{holder: $holder, acquired_at: "2020-01-01T00:00:00Z", heartbeat_at: "2020-01-01T00:00:00Z"}' \
    > "$FORGE_DIR/lock.json"
}

# Schema-valid JSON that is nonetheless missing/malforming the fields
# lock_age_seconds() depends on (F096-style hand-edited or foreign-tool
# lock.json). read_lock() must treat these identically to "no lock present"
# rather than letting jq's `fromdate` throw under `set -euo pipefail`.
write_lock_missing_heartbeat() {
  jq -n --arg holder "$1" '{holder: $holder}' > "$FORGE_DIR/lock.json"
}

write_lock_unparseable_heartbeat() {
  jq -n --arg holder "$1" \
    '{holder: $holder, acquired_at: "2020-01-01T00:00:00Z", heartbeat_at: "not-a-date"}' \
    > "$FORGE_DIR/lock.json"
}

# --- acquire ---

@test "acquire: succeeds when no lock exists" {
  run bash "$SCRIPT" acquire --session-id sess-A --forge-dir "$FORGE_DIR"
  [ "$status" -eq 0 ]
  [ "$(jq_field '.ok')" = "true" ]
  [ "$(jq_field '.acquired')" = "true" ]
  [ "$(jq_field '.broke_stale')" = "false" ]
  [ "$(jq_field '.held_by')" = "sess-A" ]
  [ -f "$FORGE_DIR/lock.json" ]
  [ "$(jq -r '.holder' "$FORGE_DIR/lock.json")" = "sess-A" ]
}

@test "acquire: requires --session-id" {
  run bash "$SCRIPT" acquire --forge-dir "$FORGE_DIR"
  [ "$status" -ne 0 ]
}

@test "acquire: fails (acquired=false) when a different session holds a fresh lock" {
  bash "$SCRIPT" acquire --session-id sess-A --forge-dir "$FORGE_DIR" >/dev/null
  run bash "$SCRIPT" acquire --session-id sess-B --forge-dir "$FORGE_DIR"
  [ "$(jq_field '.acquired')" = "false" ]
  [ "$(jq_field '.held_by')" = "sess-A" ]
  # the lock file must be unchanged, still held by sess-A
  [ "$(jq -r '.holder' "$FORGE_DIR/lock.json")" = "sess-A" ]
}

@test "acquire: re-acquiring with the SAME session-id is an idempotent success" {
  bash "$SCRIPT" acquire --session-id sess-A --forge-dir "$FORGE_DIR" >/dev/null
  run bash "$SCRIPT" acquire --session-id sess-A --forge-dir "$FORGE_DIR"
  [ "$(jq_field '.acquired')" = "true" ]
  [ "$(jq_field '.broke_stale')" = "false" ]
}

@test "acquire: breaks a stale lock and reports the prior holder" {
  write_stale_lock "sess-OLD"
  run bash "$SCRIPT" acquire --session-id sess-NEW --window-min 30 --forge-dir "$FORGE_DIR"
  [ "$(jq_field '.acquired')" = "true" ]
  [ "$(jq_field '.broke_stale')" = "true" ]
  [ "$(jq_field '.prior_holder')" = "sess-OLD" ]
  [ "$(jq -r '.holder' "$FORGE_DIR/lock.json")" = "sess-NEW" ]
}

@test "acquire: window-min from config.json is honored when --window-min is not passed" {
  write_stale_lock "sess-OLD"
  echo '{"heartbeat_window_minutes": 1}' > "$FORGE_DIR/config.json"
  run bash "$SCRIPT" acquire --session-id sess-NEW --forge-dir "$FORGE_DIR"
  [ "$(jq_field '.broke_stale')" = "true" ]
}

# --- heartbeat ---

@test "heartbeat: fails cleanly when no lock exists" {
  run bash "$SCRIPT" heartbeat --session-id sess-A --forge-dir "$FORGE_DIR"
  [ "$status" -eq 0 ]
  [ "$(jq_field '.ok')" = "false" ]
  [ "$(jq_field '.updated')" = "false" ]
}

@test "heartbeat: refuses to update a lock held by a different session" {
  bash "$SCRIPT" acquire --session-id sess-A --forge-dir "$FORGE_DIR" >/dev/null
  run bash "$SCRIPT" heartbeat --session-id sess-B --forge-dir "$FORGE_DIR"
  [ "$(jq_field '.ok')" = "false" ]
  [ "$(jq_field '.updated')" = "false" ]
  [ "$(jq_field '.held_by')" = "sess-A" ]
}

@test "heartbeat: updates heartbeat_at for the holding session, preserves acquired_at" {
  bash "$SCRIPT" acquire --session-id sess-A --forge-dir "$FORGE_DIR" >/dev/null
  acquired_at_before="$(jq -r '.acquired_at' "$FORGE_DIR/lock.json")"
  run bash "$SCRIPT" heartbeat --session-id sess-A --forge-dir "$FORGE_DIR"
  [ "$(jq_field '.ok')" = "true" ]
  [ "$(jq_field '.updated')" = "true" ]
  [ "$(jq -r '.acquired_at' "$FORGE_DIR/lock.json")" = "$acquired_at_before" ]
  [ "$(jq -r '.heartbeat_at' "$FORGE_DIR/lock.json")" = "$(jq_field '.heartbeat_at')" ]
}

@test "heartbeat: a fresh heartbeat un-stales a previously-stale lock for its holder" {
  bash "$SCRIPT" acquire --session-id sess-A --forge-dir "$FORGE_DIR" >/dev/null
  # simulate staleness by rewriting heartbeat_at into the past directly
  jq '.heartbeat_at = "2020-01-01T00:00:00Z"' "$FORGE_DIR/lock.json" > "$FORGE_DIR/lock.json.tmp"
  mv "$FORGE_DIR/lock.json.tmp" "$FORGE_DIR/lock.json"
  bash "$SCRIPT" heartbeat --session-id sess-A --forge-dir "$FORGE_DIR" >/dev/null
  run bash "$SCRIPT" check --session-id sess-A --forge-dir "$FORGE_DIR"
  [ "$(jq_field '.stale')" = "false" ]
}

# --- release ---

@test "release: no-op success when no lock exists" {
  run bash "$SCRIPT" release --forge-dir "$FORGE_DIR"
  [ "$(jq_field '.ok')" = "true" ]
  [ "$(jq_field '.released')" = "false" ]
}

@test "release: without --session-id releases unconditionally" {
  bash "$SCRIPT" acquire --session-id sess-A --forge-dir "$FORGE_DIR" >/dev/null
  run bash "$SCRIPT" release --forge-dir "$FORGE_DIR"
  [ "$(jq_field '.released')" = "true" ]
  [ ! -f "$FORGE_DIR/lock.json" ]
}

@test "release: with --session-id refuses to release another session's lock" {
  bash "$SCRIPT" acquire --session-id sess-A --forge-dir "$FORGE_DIR" >/dev/null
  run bash "$SCRIPT" release --session-id sess-B --forge-dir "$FORGE_DIR"
  [ "$(jq_field '.ok')" = "false" ]
  [ "$(jq_field '.released')" = "false" ]
  [ -f "$FORGE_DIR/lock.json" ]
}

@test "release: with matching --session-id releases successfully" {
  bash "$SCRIPT" acquire --session-id sess-A --forge-dir "$FORGE_DIR" >/dev/null
  run bash "$SCRIPT" release --session-id sess-A --forge-dir "$FORGE_DIR"
  [ "$(jq_field '.released')" = "true" ]
  [ ! -f "$FORGE_DIR/lock.json" ]
}

# --- check (read-only) ---

@test "check: requires --session-id" {
  run bash "$SCRIPT" check --forge-dir "$FORGE_DIR"
  [ "$status" -ne 0 ]
}

@test "check: action=acquire when no lock present" {
  run bash "$SCRIPT" check --session-id sess-A --forge-dir "$FORGE_DIR"
  [ "$(jq_field '.held')" = "false" ]
  [ "$(jq_field '.action')" = "acquire" ]
}

@test "check: action=exit-running when held fresh by another session" {
  bash "$SCRIPT" acquire --session-id sess-A --forge-dir "$FORGE_DIR" >/dev/null
  run bash "$SCRIPT" check --session-id sess-B --window-min 30 --forge-dir "$FORGE_DIR"
  [ "$(jq_field '.held')" = "true" ]
  [ "$(jq_field '.stale')" = "false" ]
  [ "$(jq_field '.action')" = "exit-running" ]
  [ "$(jq_field '.holder')" = "sess-A" ]
}

@test "check: action=break when held but stale" {
  write_stale_lock "sess-OLD"
  run bash "$SCRIPT" check --session-id sess-NEW --window-min 30 --forge-dir "$FORGE_DIR"
  [ "$(jq_field '.held')" = "true" ]
  [ "$(jq_field '.stale')" = "true" ]
  [ "$(jq_field '.action')" = "break" ]
}

@test "check: action=acquire when checked by the current holder itself" {
  bash "$SCRIPT" acquire --session-id sess-A --forge-dir "$FORGE_DIR" >/dev/null
  run bash "$SCRIPT" check --session-id sess-A --forge-dir "$FORGE_DIR"
  [ "$(jq_field '.held')" = "true" ]
  [ "$(jq_field '.action')" = "acquire" ]
}

@test "check: does not mutate lock.json (read-only)" {
  write_stale_lock "sess-OLD"
  before="$(cat "$FORGE_DIR/lock.json")"
  bash "$SCRIPT" check --session-id sess-NEW --forge-dir "$FORGE_DIR" >/dev/null
  after="$(cat "$FORGE_DIR/lock.json")"
  [ "$before" = "$after" ]
}

# --- Schema-valid-but-field-incomplete lock.json (F096-style corruption) ---

@test "acquire: does not crash on a lock.json missing heartbeat_at, treats it as absent" {
  write_lock_missing_heartbeat "sess-OLD"
  run bash "$SCRIPT" acquire --session-id sess-NEW --forge-dir "$FORGE_DIR"
  [ "$status" -eq 0 ]
  [ "$(jq_field '.ok')" = "true" ]
  [ "$(jq_field '.acquired')" = "true" ]
  [ "$(jq -r '.holder' "$FORGE_DIR/lock.json")" = "sess-NEW" ]
}

@test "acquire: does not crash on a lock.json with an unparseable heartbeat_at, treats it as absent" {
  write_lock_unparseable_heartbeat "sess-OLD"
  run bash "$SCRIPT" acquire --session-id sess-NEW --forge-dir "$FORGE_DIR"
  [ "$status" -eq 0 ]
  [ "$(jq_field '.ok')" = "true" ]
  [ "$(jq_field '.acquired')" = "true" ]
  [ "$(jq -r '.holder' "$FORGE_DIR/lock.json")" = "sess-NEW" ]
}

@test "check: does not crash on a lock.json missing heartbeat_at, treats it as absent" {
  write_lock_missing_heartbeat "sess-OLD"
  run bash "$SCRIPT" check --session-id sess-NEW --forge-dir "$FORGE_DIR"
  [ "$status" -eq 0 ]
  [ "$(jq_field '.ok')" = "true" ]
  [ "$(jq_field '.held')" = "false" ]
  [ "$(jq_field '.action')" = "acquire" ]
}

@test "check: does not crash on a lock.json with an unparseable heartbeat_at, treats it as absent" {
  write_lock_unparseable_heartbeat "sess-OLD"
  run bash "$SCRIPT" check --session-id sess-NEW --forge-dir "$FORGE_DIR"
  [ "$status" -eq 0 ]
  [ "$(jq_field '.ok')" = "true" ]
  [ "$(jq_field '.held')" = "false" ]
  [ "$(jq_field '.action')" = "acquire" ]
}

# --- Unknown subcommand ---

@test "unknown subcommand returns ok:false and nonzero exit" {
  run bash "$SCRIPT" bogus --forge-dir "$FORGE_DIR"
  [ "$status" -ne 0 ]
  [ "$(jq_field '.ok')" = "false" ]
}

# --- Output is always valid JSON ---

@test "every subcommand's output is valid JSON" {
  run bash "$SCRIPT" acquire --session-id sess-A --forge-dir "$FORGE_DIR"
  echo "$output" | jq . >/dev/null
  run bash "$SCRIPT" heartbeat --session-id sess-A --forge-dir "$FORGE_DIR"
  echo "$output" | jq . >/dev/null
  run bash "$SCRIPT" check --session-id sess-A --forge-dir "$FORGE_DIR"
  echo "$output" | jq . >/dev/null
  run bash "$SCRIPT" release --session-id sess-A --forge-dir "$FORGE_DIR"
  echo "$output" | jq . >/dev/null
}
