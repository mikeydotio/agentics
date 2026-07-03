#!/usr/bin/env bats
# Tests for forge-close-project-story.sh — explicit hygiene close of the
# decompose-created "project story" once every real task story is done.
#
# Drives the real `story` CLI against throwaway git+storyhook projects in
# /tmp (never mocked — see CLAUDE.md). Requires `story` on PATH; install via
# the storyhook-install skill if these are skipped/fail with "command not
# found".

SCRIPT="$BATS_TEST_DIRNAME/forge-close-project-story.sh"

setup() {
  TEST_DIR="$(mktemp -d)"
  export TEST_DIR
  ( cd "$TEST_DIR" && git init -q . && story init --prefix CP >/dev/null 2>&1 )
  mkdir -p "$TEST_DIR/.forge"
}

teardown() {
  if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
    rm -rf "$TEST_DIR"
  fi
}

jq_field() {
  echo "$output" | jq -r "$1"
}

write_mapping() {
  jq -n --arg ps "$1" '{plan_hash: "x", project_story: $ps, stories: {}}' \
    > "$TEST_DIR/.forge/plan-mapping.json"
}

# --- No plan-mapping.json at all ---

@test "close-project-story: no-op when plan-mapping.json is absent" {
  run bash "$SCRIPT" "$TEST_DIR"
  [ "$status" -eq 0 ]
  [ "$(jq_field '.ok')" = "true" ]
  [ "$(jq_field '.closed')" = "false" ]
  [ "$(jq_field '.reason')" = "no_plan_mapping" ]
}

@test "close-project-story: no-op when plan-mapping.json is malformed JSON" {
  echo 'not valid json' > "$TEST_DIR/.forge/plan-mapping.json"
  run bash "$SCRIPT" "$TEST_DIR"
  [ "$status" -eq 0 ]
  [ "$(jq_field '.ok')" = "true" ]
  [ "$(jq_field '.closed')" = "false" ]
  [ "$(jq_field '.reason')" = "no_plan_mapping" ]
}

# --- plan-mapping.json without a project_story field ---

@test "close-project-story: no-op when plan-mapping.json has no project_story" {
  echo '{}' > "$TEST_DIR/.forge/plan-mapping.json"
  run bash "$SCRIPT" "$TEST_DIR"
  [ "$status" -eq 0 ]
  [ "$(jq_field '.ok')" = "true" ]
  [ "$(jq_field '.closed')" = "false" ]
  [ "$(jq_field '.reason')" = "no_project_story_recorded" ]
}

# --- story CLI unavailable ---

@test "close-project-story: ok is false when story CLI is not on PATH" {
  write_mapping "CP-1"
  PATH="/usr/bin:/bin" run bash "$SCRIPT" "$TEST_DIR"
  [ "$status" -eq 0 ]
  [ "$(jq_field '.ok')" = "false" ]
  [ "$(jq_field '.reason')" = "story_cli_missing" ]
}

# --- Recorded project_story that doesn't exist in the story list ---

@test "close-project-story: no-op when the recorded project_story ID is not found" {
  write_mapping "CP-999"
  run bash "$SCRIPT" "$TEST_DIR"
  [ "$status" -eq 0 ]
  [ "$(jq_field '.ok')" = "true" ]
  [ "$(jq_field '.closed')" = "false" ]
  [ "$(jq_field '.reason')" = "project_story_not_found" ]
}

# --- The exact repro: decompose-created parent, one real task, task done ---

@test "close-project-story: closes the parent once the only real task story is done" {
  ( cd "$TEST_DIR" && \
    printf '## Task Breakdown\n\n### Wave 1\n\n- [ ] [HIGH] Only task\n' \
      | story decompose --stdin --json >/dev/null && \
    story move CP-2 in-progress >/dev/null && \
    story move CP-2 done >/dev/null )
  write_mapping "CP-1"
  run bash "$SCRIPT" "$TEST_DIR"
  [ "$status" -eq 0 ]
  [ "$(jq_field '.ok')" = "true" ]
  [ "$(jq_field '.closed')" = "true" ]
  [ "$(jq_field '.project_story')" = "CP-1" ]
  [ "$(jq_field '.reason')" = "closed" ]

  # Confirm the underlying story state actually changed.
  run bash -c "cd '$TEST_DIR' && story list --json | jq -r '.stories[] | select(.story.id==\"CP-1\") | .story.state'"
  [ "$output" = "done" ]
}

@test "close-project-story: no-op while a real task story is still not done" {
  ( cd "$TEST_DIR" && \
    printf '## Task Breakdown\n\n### Wave 1\n\n- [ ] [HIGH] Task one\n- [ ] [HIGH] Task two\n' \
      | story decompose --stdin --json >/dev/null && \
    story move CP-2 in-progress >/dev/null && \
    story move CP-2 done >/dev/null )
  # CP-3 (the second task) is still todo.
  write_mapping "CP-1"
  run bash "$SCRIPT" "$TEST_DIR"
  [ "$status" -eq 0 ]
  [ "$(jq_field '.ok')" = "true" ]
  [ "$(jq_field '.closed')" = "false" ]
  [ "$(jq_field '.reason')" = "tasks_incomplete" ]

  run bash -c "cd '$TEST_DIR' && story list --json | jq -r '.stories[] | select(.story.id==\"CP-1\") | .story.state'"
  [ "$output" = "todo" ]
}

@test "close-project-story: is idempotent once already closed" {
  ( cd "$TEST_DIR" && \
    printf '## Task Breakdown\n\n### Wave 1\n\n- [ ] [HIGH] Only task\n' \
      | story decompose --stdin --json >/dev/null && \
    story move CP-2 in-progress >/dev/null && \
    story move CP-2 done >/dev/null )
  write_mapping "CP-1"
  run bash "$SCRIPT" "$TEST_DIR"
  [ "$(jq_field '.reason')" = "closed" ]

  run bash "$SCRIPT" "$TEST_DIR"
  [ "$status" -eq 0 ]
  [ "$(jq_field '.ok')" = "true" ]
  [ "$(jq_field '.closed')" = "false" ]
  [ "$(jq_field '.reason')" = "already_done" ]
}

# --- Output structure ---

@test "close-project-story: output is valid JSON" {
  run bash "$SCRIPT" "$TEST_DIR"
  echo "$output" | jq . >/dev/null
}

@test "close-project-story: has a display field" {
  run bash "$SCRIPT" "$TEST_DIR"
  echo "$output" | jq -e '.display' >/dev/null
}

# --- Defaults to cwd when no project dir is given ---

@test "close-project-story: defaults to the current directory when no argument is given" {
  ( cd "$TEST_DIR" && \
    output="$(bash "$SCRIPT")" && \
    echo "$output" | jq -e '.ok == true' >/dev/null && \
    echo "$output" | jq -e '.reason == "no_plan_mapping"' >/dev/null )
}
