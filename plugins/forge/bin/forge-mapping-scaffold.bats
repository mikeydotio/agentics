#!/usr/bin/env bats
# Tests for forge-mapping-scaffold.sh — mechanical plan-mapping.json skeleton
# assembly (F035). Drives the real `story` CLI (never mocked — see
# CLAUDE.md); requires `story` on PATH.

SCRIPT="$BATS_TEST_DIRNAME/forge-mapping-scaffold.sh"

setup() {
  TEST_DIR="$(mktemp -d)"
  export TEST_DIR
  git -C "$TEST_DIR" init -q
}

teardown() {
  if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
    rm -rf "$TEST_DIR"
  fi
}

write_plan() {
  mkdir -p "$TEST_DIR/.forge"
  cat > "$TEST_DIR/.forge/PLAN.md" <<'EOF'
# Implementation Plan

## Task Breakdown

### Wave 1
- [ ] Task 1.1: Create config module
  - Acceptance: loads YAML and returns typed object
  - Files: src/config.ts

### Wave 2
- [ ] Task 2.1: Create logger module
  - Acceptance: structured JSON to stdout
  - Files: src/logger.ts
EOF
}

@test "mapping-scaffold: reports plan_not_found when PLAN.md is missing" {
  cd "$TEST_DIR"
  run bash "$SCRIPT" --plan .forge/PLAN.md
  [ "$status" -eq 0 ]
  local ok err
  ok="$(echo "$output" | jq -r '.ok')"
  err="$(echo "$output" | jq -r '.error')"
  [ "$ok" = "false" ]
  [ "$err" = "plan_not_found" ]
}

@test "mapping-scaffold: computes a stable md5 plan_hash" {
  cd "$TEST_DIR"
  write_plan
  run bash "$SCRIPT" --plan .forge/PLAN.md
  [ "$status" -eq 0 ]
  local hash expected
  hash="$(echo "$output" | jq -r '.plan_hash')"
  expected="$(python3 -c 'import hashlib; print(hashlib.md5(open(".forge/PLAN.md","rb").read()).hexdigest())')"
  [ "$hash" = "$expected" ]
  [[ "$hash" =~ ^[0-9a-f]{32}$ ]]
}

@test "mapping-scaffold: without story CLI on PATH still returns plan_hash with empty stories" {
  cd "$TEST_DIR"
  write_plan
  PATH="/usr/bin:/bin" run bash "$SCRIPT" --plan .forge/PLAN.md
  [ "$status" -eq 0 ]
  local ok stories
  ok="$(echo "$output" | jq -r '.ok')"
  stories="$(echo "$output" | jq '.stories | length')"
  [ "$ok" = "true" ]
  [ "$stories" -eq 0 ]
}

@test "mapping-scaffold: identifies project_story and per-story skeletons from a real decompose" {
  cd "$TEST_DIR"
  write_plan
  story project new --prefix MS >/dev/null
  awk '/^## Task Breakdown/{flag=1} /^## / && !/^## Task Breakdown/{if(flag)exit} flag' .forge/PLAN.md > /tmp/ms-tasks-$$.md
  story decompose /tmp/ms-tasks-$$.md --json >/dev/null
  rm -f /tmp/ms-tasks-$$.md

  run bash "$SCRIPT" --plan .forge/PLAN.md
  [ "$status" -eq 0 ]
  local ok project_story story_count
  ok="$(echo "$output" | jq -r '.ok')"
  project_story="$(echo "$output" | jq -r '.project_story')"
  story_count="$(echo "$output" | jq '.stories | length')"
  [ "$ok" = "true" ]
  [ -n "$project_story" ]
  [ "$story_count" -eq 2 ]

  # project_story itself must not appear as a key in stories{}
  run bash -c "echo '$output' | jq -e --arg ps \"$project_story\" '.stories | has(\$ps) | not'"
  [ "$status" -eq 0 ]
}

@test "mapping-scaffold: per-story skeleton has title filled and judgment fields null/empty" {
  cd "$TEST_DIR"
  write_plan
  story project new --prefix MS >/dev/null
  awk '/^## Task Breakdown/{flag=1} /^## / && !/^## Task Breakdown/{if(flag)exit} flag' .forge/PLAN.md > /tmp/ms-tasks2-$$.md
  story decompose /tmp/ms-tasks2-$$.md --json >/dev/null
  rm -f /tmp/ms-tasks2-$$.md

  run bash "$SCRIPT" --plan .forge/PLAN.md
  [ "$status" -eq 0 ]
  local first_id
  first_id="$(echo "$output" | jq -r '.stories | keys[0]')"
  local title task_ref files_expected
  title="$(echo "$output" | jq -r --arg id "$first_id" '.stories[$id].title')"
  task_ref="$(echo "$output" | jq -r --arg id "$first_id" '.stories[$id].task_ref')"
  files_expected="$(echo "$output" | jq -r --arg id "$first_id" '.stories[$id].files_expected | length')"
  [ -n "$title" ]
  [ "$task_ref" = "null" ]
  [ "$files_expected" -eq 0 ]
}

@test "mapping-scaffold: output is valid JSON" {
  cd "$TEST_DIR"
  write_plan
  run bash "$SCRIPT" --plan .forge/PLAN.md
  echo "$output" | jq . >/dev/null
}
