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

SKILL_MD="${FORGE_SETUP_SKILL:-$BATS_TEST_DIRNAME/../claude/skills/decompose/SKILL.md}"
REFERENCE_MD="$BATS_TEST_DIRNAME/../references/story-decomposition.md"

setup() {
  FORGE_FIXTURE_STORY="$(type -P story)" || return 1
  FORGE_FIXTURE_PYTHON="$(type -P python3)" || return 1
  FORGE_FIXTURE_HELPER="$BATS_TEST_DIRNAME/../tests/fixture_story.py"
  # This root must survive Bats and suite-store cleanup when shutdown fails.
  FORGE_FIXTURE_ROOT="$(mktemp -d /tmp/forge-storyhook-fixture.XXXXXXXX)" || return 1
  FORGE_FIXTURE_OWNER_PID="${BASHPID:-$$}"
  TEST_DIR="$FORGE_FIXTURE_ROOT/repo"
  readonly FORGE_FIXTURE_STORY FORGE_FIXTURE_PYTHON FORGE_FIXTURE_HELPER
  readonly FORGE_FIXTURE_ROOT FORGE_FIXTURE_OWNER_PID TEST_DIR
  export FORGE_FIXTURE_STORY FORGE_FIXTURE_PYTHON FORGE_FIXTURE_HELPER
  export FORGE_FIXTURE_ROOT FORGE_FIXTURE_OWNER_PID
  printf '%s\n' "$FORGE_FIXTURE_OWNER_PID" "$FORGE_FIXTURE_STORY" > "$FORGE_FIXTURE_ROOT/owner"
  mkdir -p "$TEST_DIR" "$FORGE_FIXTURE_ROOT/home" "$FORGE_FIXTURE_ROOT/templates"
  story() {
    "$FORGE_FIXTURE_PYTHON" -B "$FORGE_FIXTURE_HELPER" \
      "$FORGE_FIXTURE_ROOT" "$FORGE_FIXTURE_OWNER_PID" "$FORGE_FIXTURE_STORY" "$@"
  }
  export -f story
  (
    cd "$TEST_DIR" &&
      env -i PATH="$PATH" HOME="$HOME" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
        GIT_TEMPLATE_DIR="$FORGE_FIXTURE_ROOT/templates" git init -q . &&
      story project new --prefix SC >/dev/null
  )
}

teardown() {
  if [ -z "${FORGE_FIXTURE_ROOT:-}" ] || [ ! -d "$FORGE_FIXTURE_ROOT" ] ||
      [ -L "$FORGE_FIXTURE_ROOT" ] || [ ! -x "${FORGE_FIXTURE_PYTHON:-}" ] ||
      [ ! -f "${FORGE_FIXTURE_HELPER:-}" ]; then
    echo "StoryHook fixture identity unavailable; retained: ${FORGE_FIXTURE_ROOT:-unallocated}" >&2
    return 1
  fi
  if ! "$FORGE_FIXTURE_PYTHON" -B "$FORGE_FIXTURE_HELPER" \
      "$FORGE_FIXTURE_ROOT" "$FORGE_FIXTURE_OWNER_PID" "$FORGE_FIXTURE_STORY" daemon stop; then
    echo "StoryHook fixture shutdown failed; retained: $FORGE_FIXTURE_ROOT (see stop.log)" >&2
    return 1
  fi
  rm -rf "$FORGE_FIXTURE_ROOT"
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

@test "fresh projects already provide every required Forge workflow state" {
  run bash -c "cd '$TEST_DIR' && story state list"
  [ "$status" -eq 0 ]
  local state
  for state in todo in-progress verifying blocked; do
    [[ "$output" == *"$state (OPEN"* ]]
  done
  for state in 'done' dropped; do
    [[ "$output" == *"$state (CLOSED"* ]]
  done
}

@test "every documented state/type add line exits 0 against a fresh project" {
  local line
  [ -n "$(setup_lines)" ]
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
