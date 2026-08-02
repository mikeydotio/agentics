#!/usr/bin/env bats
# Executes the storyhook state/type setup documented in
# skills/decompose/SKILL.md's "State and Type Setup" step against a real
# storyhook project, instead of only checking that the verbs it uses are
# spelled correctly.
#
# forge-contract-check.bats already validates verb and relationship names,
# and would NOT have caught AGE-2: `--role active` is a perfectly legal
# flag, so a verb/relation checker passes it without complaint. Only
# executing the documented commands proves they still work — this is the
# regression guard that kills that class of drift, not just this instance
# of it.
#
# Mock-free: drives the real `story` CLI in a throwaway /tmp repo (CLAUDE.md).

SKILL_MD="$BATS_TEST_DIRNAME/../skills/decompose/SKILL.md"
REFERENCE_MD="$BATS_TEST_DIRNAME/../references/story-decomposition.md"

setup() {
  TEST_DIR="$(mktemp -d)"
  ( cd "$TEST_DIR" && git init -q . && story project init --prefix SC >/dev/null 2>&1 )
}

teardown() {
  rm -rf "$TEST_DIR"
}

# The documented `story state add`/`story type add` lines, in file order.
setup_lines() {
  grep -E '^story (state|type) add ' "$SKILL_MD"
}

run_setup_lines() {
  local line
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    ( cd "$TEST_DIR" && eval "$line" >/dev/null )
  done <<< "$(setup_lines)"
}

@test "every documented state/type add line exits 0 against a fresh project" {
  local line
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    run bash -c "cd '$TEST_DIR' && $line"
    [ "$status" -eq 0 ]
  done <<< "$(setup_lines)"
}

@test "verifying and blocked both accept a story move after setup" {
  run_setup_lines
  ( cd "$TEST_DIR" && story new "Task" >/dev/null )
  run bash -c "cd '$TEST_DIR' && story move SC-1 verifying"
  [ "$status" -eq 0 ]
  run bash -c "cd '$TEST_DIR' && story move SC-1 blocked 'exhausted retries'"
  [ "$status" -eq 0 ]
}

@test "exactly one state carries the active role after setup" {
  run_setup_lines
  run bash -c "cd '$TEST_DIR' && story state list"
  [ "$status" -eq 0 ]
  active_count="$(echo "$output" | grep -c ', active)')"
  [ "$active_count" -eq 1 ]
  echo "$output" | grep -q '^in-progress (OPEN, active)$'
}

@test "story-decomposition.md documents the identical state/type add lines" {
  diff <(setup_lines) <(grep -E '^story (state|type) add ' "$REFERENCE_MD")
}
