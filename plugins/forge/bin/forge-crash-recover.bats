#!/usr/bin/env bats
# Tests for forge-crash-recover.sh — reset in-progress/verifying stories back
# to todo and clean the working tree in one call (F038), using the real
# verb-first `story move` CLI.
#
# Mock-free: drives the real `story` CLI in a throwaway /tmp repo (CLAUDE.md).

SCRIPT="$BATS_TEST_DIRNAME/forge-crash-recover.sh"

setup() {
  TEST_DIR="$(mktemp -d)"
  ( cd "$TEST_DIR" && git init -q . && git config user.email t@t.com && git config user.name t \
      && story project new --prefix ST >/dev/null )
}

teardown() {
  rm -rf "$TEST_DIR"
}

run_recover() {
  run bash "$SCRIPT" "$TEST_DIR"
}

jq_field() {
  echo "$output" | jq -r "$1"
}

story_state() {
  ( cd "$TEST_DIR" && story list --all --json | jq -r --arg id "$1" '.stories[] | select(.story.id == $id) | .story.state' )
}

# --- story CLI unavailable ---

@test "story CLI missing: ok=false, does not touch the tree" {
  echo "dirty" > "$TEST_DIR/dirty.txt"
  PATH="/usr/bin:/bin" run bash "$SCRIPT" "$TEST_DIR"
  [ "$status" -eq 0 ]
  [ "$(jq_field '.ok')" = "false" ]
  [ "$(jq_field '.error')" = "story_cli_missing" ]
  [ "$(jq_field '.reset_stories | length')" = "0" ]
  [ -f "$TEST_DIR/dirty.txt" ]
}

# --- Nothing to recover ---

@test "no stuck stories: ok=true, empty reset_stories, tree_clean=true" {
  ( cd "$TEST_DIR" && story new "Task" >/dev/null )
  run_recover
  [ "$status" -eq 0 ]
  [ "$(jq_field '.ok')" = "true" ]
  [ "$(jq_field '.reset_stories | length')" = "0" ]
  [ "$(jq_field '.tree_clean')" = "true" ]
}

@test "a todo-only backlog is left completely untouched" {
  ( cd "$TEST_DIR" && story new "Task" >/dev/null )
  run_recover
  [ "$(story_state ST-1)" = "todo" ]
}

# --- in-progress reset ---

@test "resets a single in-progress story back to todo" {
  ( cd "$TEST_DIR" && story new "Task" >/dev/null && story move ST-1 in-progress >/dev/null )
  [ "$(story_state ST-1)" = "in-progress" ]
  run_recover
  [ "$(jq_field '.ok')" = "true" ]
  [ "$(jq_field '.reset_stories | length')" = "1" ]
  [ "$(jq_field '.reset_stories[0]')" = "ST-1" ]
  [ "$(story_state ST-1)" = "todo" ]
}

# --- verifying reset ---

@test "resets a single verifying story back to todo" {
  # A real blocked queue item stays verifying without a fabricated PR or lease.
  ( cd "$TEST_DIR" && story new "Task" >/dev/null && story move ST-1 in-progress >/dev/null && \
    story block ST-1 "fixture: queued verification is parked" >/dev/null && story move ST-1 verifying >/dev/null )
  [ "$(story_state ST-1)" = "verifying" ]
  run_recover
  [ "$(jq_field '.reset_stories[0]')" = "ST-1" ]
  [ "$(story_state ST-1)" = "todo" ]
}

# --- Multiple stuck stories, mixed states ---

@test "resets every in-progress/verifying story, leaves done/todo alone" {
  ( cd "$TEST_DIR" && \
    story new "A" >/dev/null && story new "B" >/dev/null && \
    story new "C" >/dev/null && story new "D" >/dev/null && \
    story move ST-1 in-progress >/dev/null && \
    story move ST-2 in-progress >/dev/null && \
    story block ST-2 "fixture: queued verification is parked" >/dev/null && story move ST-2 verifying >/dev/null && \
    story move ST-3 done >/dev/null )
  # ST-4 stays todo
  run_recover
  [ "$(jq_field '.reset_stories | length')" = "2" ]
  echo "$output" | jq -e '.reset_stories | index("ST-1") != null' >/dev/null
  echo "$output" | jq -e '.reset_stories | index("ST-2") != null' >/dev/null
  [ "$(story_state ST-1)" = "todo" ]
  [ "$(story_state ST-2)" = "todo" ]
  [ "$(story_state ST-3)" = "done" ]
  [ "$(story_state ST-4)" = "todo" ]
}

# --- Working tree cleanup ---

@test "reverts uncommitted tracked-file changes via git checkout ." {
  ( cd "$TEST_DIR" && git add -A && git commit -q -m init )
  echo "clean baseline" > "$TEST_DIR/tracked.txt"
  ( cd "$TEST_DIR" && git add tracked.txt && git commit -q -m "add tracked.txt" )
  echo "crashed mid-edit" > "$TEST_DIR/tracked.txt"
  run_recover
  [ "$(jq_field '.tree_clean')" = "true" ]
  [ "$(cat "$TEST_DIR/tracked.txt")" = "clean baseline" ]
}

@test "cleans the tree even when there is nothing to reset" {
  ( cd "$TEST_DIR" && story new "Task" >/dev/null )
  echo "clean baseline" > "$TEST_DIR/tracked.txt"
  ( cd "$TEST_DIR" && git add -A && git commit -q -m init )
  echo "crashed mid-edit" > "$TEST_DIR/tracked.txt"
  run_recover
  [ "$(jq_field '.ok')" = "true" ]
  [ "$(jq_field '.reset_stories | length')" = "0" ]
  [ "$(jq_field '.tree_clean')" = "true" ]
  [ "$(cat "$TEST_DIR/tracked.txt")" = "clean baseline" ]
}

# --- story list failure ---

@test "story list --json failure is reported, not crashed on" {
  # storyhook 1.0.0 keeps project data in a single global store; a repo
  # carries only `.storyhook.toml`, so a per-repo `.storyhook/` directory no
  # longer means anything to storyhook. A directory that was never `story
  # init`ed is the portable way to make `story list --json` exit non-zero —
  # the same mechanism forge-dag-validate.bats uses for its
  # uninitialized-project case.
  UNINIT_DIR="$(mktemp -d)"
  echo "dirty" > "$UNINIT_DIR/dirty.txt"
  run bash "$SCRIPT" "$UNINIT_DIR"
  [ "$status" -eq 0 ]
  [ "$(jq_field '.ok')" = "false" ]
  [ "$(jq_field '.error')" = "story_list_failed" ]
  [ "$(jq_field '.reset_stories | length')" = "0" ]
  [ "$(jq_field '.tree_clean')" = "false" ]
  [ -f "$UNINIT_DIR/dirty.txt" ]
  rm -rf "$UNINIT_DIR"
}

@test "output is always valid JSON" {
  ( cd "$TEST_DIR" && story new "Task" >/dev/null && story move ST-1 in-progress >/dev/null )
  run_recover
  echo "$output" | jq . >/dev/null
}
