#!/usr/bin/env bats
# Tests for forge-handoff-scaffold.sh — mechanical handoff field pre-fill (F039)

SCRIPT="$BATS_TEST_DIRNAME/forge-handoff-scaffold.sh"

setup() {
  TEST_DIR="$(mktemp -d)"
  export TEST_DIR

  git -C "$TEST_DIR" init -q
  git -C "$TEST_DIR" config user.email "test@test.com"
  git -C "$TEST_DIR" config user.name "Test"
  printf '.forge/state.json\n.forge/lock.json\n.forge/verdicts.jsonl\n' > "$TEST_DIR/.gitignore"
  touch "$TEST_DIR/.gitkeep"
  git -C "$TEST_DIR" add .gitkeep .gitignore
  git -C "$TEST_DIR" commit -q -m "init"

  mkdir -p "$TEST_DIR/.forge"
}

teardown() {
  if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
    rm -rf "$TEST_DIR"
  fi
}

@test "handoff-scaffold: fails without --step" {
  cd "$TEST_DIR"
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
}

@test "handoff-scaffold: output is valid JSON with ok true" {
  cd "$TEST_DIR"
  run bash "$SCRIPT" --step research
  [ "$status" -eq 0 ]
  echo "$output" | jq . >/dev/null
  local ok
  ok="$(echo "$output" | jq -r '.ok')"
  [ "$ok" = "true" ]
}

@test "handoff-scaffold: timestamp is ISO-8601 UTC" {
  cd "$TEST_DIR"
  run bash "$SCRIPT" --step research
  local ts
  ts="$(echo "$output" | jq -r '.timestamp')"
  [[ "$ts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

@test "handoff-scaffold: artifacts_produced is empty when nothing changed under .forge" {
  cd "$TEST_DIR"
  run bash "$SCRIPT" --step research
  local count
  count="$(echo "$output" | jq '.artifacts_produced | length')"
  [ "$count" -eq 0 ]
}

@test "handoff-scaffold: artifacts_produced lists an untracked new file under .forge" {
  cd "$TEST_DIR"
  echo "# Research" > "$TEST_DIR/.forge/SUMMARY.md"
  run bash "$SCRIPT" --step research
  local list
  list="$(echo "$output" | jq -r '.artifacts_produced[]')"
  [[ "$list" == *".forge/SUMMARY.md"* ]]
}

@test "handoff-scaffold: artifacts_produced lists a modified tracked file under .forge" {
  cd "$TEST_DIR"
  echo "# Design v1" > "$TEST_DIR/.forge/DESIGN.md"
  git -C "$TEST_DIR" add .forge/DESIGN.md
  git -C "$TEST_DIR" commit -q -m "seed design"
  echo "# Design v2" > "$TEST_DIR/.forge/DESIGN.md"

  run bash "$SCRIPT" --step design
  local list
  list="$(echo "$output" | jq -r '.artifacts_produced[]')"
  [[ "$list" == *".forge/DESIGN.md"* ]]
}

@test "handoff-scaffold: artifacts_produced does not include files outside forge-dir" {
  cd "$TEST_DIR"
  echo "src change" > "$TEST_DIR/app.ts"
  run bash "$SCRIPT" --step execute
  local count
  count="$(echo "$output" | jq '.artifacts_produced | length')"
  [ "$count" -eq 0 ]
}

@test "handoff-scaffold: pipeline_state defaults when config.json absent" {
  cd "$TEST_DIR"
  run bash "$SCRIPT" --step research
  local fix_cycle max_cycles yolo
  fix_cycle="$(echo "$output" | jq -r '.pipeline_state.fix_cycle')"
  max_cycles="$(echo "$output" | jq -r '.pipeline_state.max_fix_cycles')"
  yolo="$(echo "$output" | jq -r '.pipeline_state.yolo')"
  [ "$fix_cycle" = "0" ]
  [ "$max_cycles" = "3" ]
  [ "$yolo" = "false" ]
}

@test "handoff-scaffold: pipeline_state reads yolo and max_fix_cycles from config.json" {
  cd "$TEST_DIR"
  echo '{"yolo": true, "max_fix_cycles": 3, "max_fix_cycles_yolo": 10}' > "$TEST_DIR/.forge/config.json"
  run bash "$SCRIPT" --step plan
  local yolo max_cycles
  yolo="$(echo "$output" | jq -r '.pipeline_state.yolo')"
  max_cycles="$(echo "$output" | jq -r '.pipeline_state.max_fix_cycles')"
  [ "$yolo" = "true" ]
  [ "$max_cycles" = "10" ]
}

@test "handoff-scaffold: pipeline_state counts existing fix cycles" {
  cd "$TEST_DIR"
  mkdir -p "$TEST_DIR/.forge/fix-cycles/cycle-0" "$TEST_DIR/.forge/fix-cycles/cycle-1"
  run bash "$SCRIPT" --step plan
  local fix_cycle
  fix_cycle="$(echo "$output" | jq -r '.pipeline_state.fix_cycle')"
  [ "$fix_cycle" = "2" ]
}

@test "handoff-scaffold: step field echoes the requested step" {
  cd "$TEST_DIR"
  run bash "$SCRIPT" --step triage
  local step_field
  step_field="$(echo "$output" | jq -r '.step')"
  [ "$step_field" = "triage" ]
}

@test "handoff-scaffold: display mentions the step name" {
  cd "$TEST_DIR"
  run bash "$SCRIPT" --step document
  [[ "$output" == *"document"* ]]
}
