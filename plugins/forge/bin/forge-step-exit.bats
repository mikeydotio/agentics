#!/usr/bin/env bats
# Tests for forge-step-exit.sh

SCRIPT="$BATS_TEST_DIRNAME/forge-step-exit.sh"

setup() {
  TEST_DIR="$(mktemp -d)"
  export TEST_DIR

  git -C "$TEST_DIR" init -q
  git -C "$TEST_DIR" config user.email "test@test.com"
  git -C "$TEST_DIR" config user.name "Test"
  touch "$TEST_DIR/.gitkeep"
  git -C "$TEST_DIR" add .gitkeep
  git -C "$TEST_DIR" commit -q -m "init"

  mkdir -p "$TEST_DIR/.forge/handoffs"
  echo "test artifact" > "$TEST_DIR/.forge/handoffs/handoff-research.md"

  # Unset TMUX to test freshen-unavailable path
  unset TMUX
  unset TMUX_PANE
}

teardown() {
  if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
    rm -rf "$TEST_DIR"
  fi
}

# --- Argument parsing ---

@test "step-exit: fails without required arguments" {
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
}

@test "step-exit: fails without --step" {
  run bash "$SCRIPT" --summary "test" --next "/forge continue"
  [ "$status" -ne 0 ]
}

@test "step-exit: fails without --summary" {
  run bash "$SCRIPT" --step research --next "/forge continue"
  [ "$status" -ne 0 ]
}

@test "step-exit: fails without --next" {
  run bash "$SCRIPT" --step research --summary "test"
  [ "$status" -ne 0 ]
}

# --- Git commit ---

@test "step-exit: output is valid JSON" {
  cd "$TEST_DIR"
  run bash "$SCRIPT" --step research --summary "completed research" --next "/forge design --orchestrated"
  echo "$output" >&2
  echo "$output" | jq . >/dev/null
}

@test "step-exit: commits .forge/ files" {
  cd "$TEST_DIR"
  run bash "$SCRIPT" --step research --summary "completed research" --next "/forge design --orchestrated"
  local ok
  ok="$(echo "$output" | jq -r '.ok')"
  [ "$ok" = "true" ]
  # Verify commit exists with the right message
  local msg
  msg="$(git -C "$TEST_DIR" log -1 --format=%s)"
  [ "$msg" = "forge(research): completed research" ]
}

@test "step-exit: committed field is true" {
  cd "$TEST_DIR"
  run bash "$SCRIPT" --step research --summary "done" --next "/forge design --orchestrated"
  local committed
  committed="$(echo "$output" | jq -r '.committed')"
  [ "$committed" = "true" ]
}

@test "step-exit: commit_hash is a short hash" {
  cd "$TEST_DIR"
  run bash "$SCRIPT" --step research --summary "done" --next "/forge design --orchestrated"
  local hash
  hash="$(echo "$output" | jq -r '.commit_hash')"
  [[ "$hash" =~ ^[0-9a-f]{7,}$ ]]
}

# --- Freshen fallback (no tmux) ---

@test "step-exit: freshen_queued is false without tmux" {
  cd "$TEST_DIR"
  run bash "$SCRIPT" --step research --summary "done" --next "/forge design --orchestrated"
  local queued
  queued="$(echo "$output" | jq -r '.freshen_queued')"
  [ "$queued" = "false" ]
}

@test "step-exit: fallback_message contains next command without tmux" {
  cd "$TEST_DIR"
  run bash "$SCRIPT" --step research --summary "done" --next "/forge design --orchestrated"
  local msg
  msg="$(echo "$output" | jq -r '.fallback_message')"
  [[ "$msg" == *"/forge design --orchestrated"* ]]
  [[ "$msg" == *"/clear"* ]]
}

# --- Commit message format ---

@test "step-exit: commit message uses forge(step) prefix" {
  cd "$TEST_DIR"
  run bash "$SCRIPT" --step design --summary "architecture decided" --next "/forge plan --orchestrated"
  local msg
  msg="$(git -C "$TEST_DIR" log -1 --format=%s)"
  [ "$msg" = "forge(design): architecture decided" ]
}
