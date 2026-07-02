#!/usr/bin/env bats
# Tests for forge-fix-archive.sh

SCRIPT="$BATS_TEST_DIRNAME/forge-fix-archive.sh"

setup() {
  TEST_DIR="$(mktemp -d)"
  export TEST_DIR
  FORGE_DIR="$TEST_DIR/.forge"
  mkdir -p "$FORGE_DIR"
}

teardown() {
  if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
    rm -rf "$TEST_DIR"
  fi
}

# --- Output structure ---

@test "fix-archive: output is valid JSON when files exist" {
  echo "triage content" > "$FORGE_DIR/TRIAGE.md"
  run bash "$SCRIPT" "$FORGE_DIR"
  echo "$output" | jq . >/dev/null
}

@test "fix-archive: ok is true when files archived" {
  echo "triage" > "$FORGE_DIR/TRIAGE.md"
  run bash "$SCRIPT" "$FORGE_DIR"
  local ok
  ok="$(echo "$output" | jq -r '.ok')"
  [ "$ok" = "true" ]
}

@test "fix-archive: ok is false when no files to archive" {
  run bash "$SCRIPT" "$FORGE_DIR"
  local ok
  ok="$(echo "$output" | jq -r '.ok')"
  [ "$ok" = "false" ]
}

@test "fix-archive: error field set when nothing to archive" {
  run bash "$SCRIPT" "$FORGE_DIR"
  local err
  err="$(echo "$output" | jq -r '.error')"
  [ "$err" = "nothing_to_archive" ]
}

# --- Cycle numbering ---

@test "fix-archive: first cycle is cycle-0" {
  echo "triage" > "$FORGE_DIR/TRIAGE.md"
  run bash "$SCRIPT" "$FORGE_DIR"
  local cycle
  cycle="$(echo "$output" | jq -r '.cycle')"
  [ "$cycle" = "0" ]
  [ -d "$FORGE_DIR/fix-cycles/cycle-0" ]
}

@test "fix-archive: second cycle is cycle-1" {
  mkdir -p "$FORGE_DIR/fix-cycles/cycle-0"
  echo "triage" > "$FORGE_DIR/TRIAGE.md"
  run bash "$SCRIPT" "$FORGE_DIR"
  local cycle
  cycle="$(echo "$output" | jq -r '.cycle')"
  [ "$cycle" = "1" ]
  [ -d "$FORGE_DIR/fix-cycles/cycle-1" ]
}

@test "fix-archive: third cycle is cycle-2 with two existing" {
  mkdir -p "$FORGE_DIR/fix-cycles/cycle-0"
  mkdir -p "$FORGE_DIR/fix-cycles/cycle-1"
  echo "plan" > "$FORGE_DIR/PLAN.md"
  run bash "$SCRIPT" "$FORGE_DIR"
  local cycle
  cycle="$(echo "$output" | jq -r '.cycle')"
  [ "$cycle" = "2" ]
  [ -d "$FORGE_DIR/fix-cycles/cycle-2" ]
}

# --- File movement ---

@test "fix-archive: moves TRIAGE.md to cycle dir" {
  echo "triage content" > "$FORGE_DIR/TRIAGE.md"
  run bash "$SCRIPT" "$FORGE_DIR"
  [ ! -f "$FORGE_DIR/TRIAGE.md" ]
  [ -f "$FORGE_DIR/fix-cycles/cycle-0/TRIAGE.md" ]
}

@test "fix-archive: moves PLAN.md to cycle dir" {
  echo "plan content" > "$FORGE_DIR/PLAN.md"
  run bash "$SCRIPT" "$FORGE_DIR"
  [ ! -f "$FORGE_DIR/PLAN.md" ]
  [ -f "$FORGE_DIR/fix-cycles/cycle-0/PLAN.md" ]
}

@test "fix-archive: moves plan-mapping.json to cycle dir" {
  echo '{}' > "$FORGE_DIR/plan-mapping.json"
  run bash "$SCRIPT" "$FORGE_DIR"
  [ ! -f "$FORGE_DIR/plan-mapping.json" ]
  [ -f "$FORGE_DIR/fix-cycles/cycle-0/plan-mapping.json" ]
}

@test "fix-archive: moves all three files together" {
  echo "triage" > "$FORGE_DIR/TRIAGE.md"
  echo "plan" > "$FORGE_DIR/PLAN.md"
  echo '{}' > "$FORGE_DIR/plan-mapping.json"
  run bash "$SCRIPT" "$FORGE_DIR"
  [ -f "$FORGE_DIR/fix-cycles/cycle-0/TRIAGE.md" ]
  [ -f "$FORGE_DIR/fix-cycles/cycle-0/PLAN.md" ]
  [ -f "$FORGE_DIR/fix-cycles/cycle-0/plan-mapping.json" ]
  [ ! -f "$FORGE_DIR/TRIAGE.md" ]
  [ ! -f "$FORGE_DIR/PLAN.md" ]
  [ ! -f "$FORGE_DIR/plan-mapping.json" ]
}

@test "fix-archive: archived list contains only existing files" {
  echo "triage" > "$FORGE_DIR/TRIAGE.md"
  # PLAN.md does not exist
  echo '{}' > "$FORGE_DIR/plan-mapping.json"
  run bash "$SCRIPT" "$FORGE_DIR"
  local count
  count="$(echo "$output" | jq '.archived | length')"
  [ "$count" -eq 2 ]
  echo "$output" | jq -e '.archived | index("TRIAGE.md")' >/dev/null
  echo "$output" | jq -e '.archived | index("plan-mapping.json")' >/dev/null
}

@test "fix-archive: preserves file content after move" {
  echo "specific triage content 12345" > "$FORGE_DIR/TRIAGE.md"
  run bash "$SCRIPT" "$FORGE_DIR"
  local content
  content="$(cat "$FORGE_DIR/fix-cycles/cycle-0/TRIAGE.md")"
  [ "$content" = "specific triage content 12345" ]
}

# --- fix-cycles directory auto-creation ---

@test "fix-archive: creates fix-cycles dir if missing" {
  echo "triage" > "$FORGE_DIR/TRIAGE.md"
  [ ! -d "$FORGE_DIR/fix-cycles" ]
  run bash "$SCRIPT" "$FORGE_DIR"
  [ "$status" -eq 0 ]
  [ -d "$FORGE_DIR/fix-cycles/cycle-0" ]
}
