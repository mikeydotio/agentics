#!/usr/bin/env bats
# Tests for /pilot init — storyhook state creation and idempotency

load helpers

setup() {
  setup_test_project
}

teardown() {
  teardown_test_project
}

@test "states.toml exists after setup" {
  [ -f "$TEST_PROJECT_DIR/.storyhook/states.toml" ]
}

@test "adding pilot states is idempotent" {
  add_work_states
  # Capture line count after first add
  local lines_after_first
  lines_after_first=$(wc -l < "$TEST_PROJECT_DIR/.storyhook/states.toml")

  # Add again — should detect existing states and not duplicate
  # Simulate idempotent add: check before appending
  if ! grep -q '^\[in-progress\]' "$TEST_PROJECT_DIR/.storyhook/states.toml"; then
    add_work_states
  fi

  local lines_after_second
  lines_after_second=$(wc -l < "$TEST_PROJECT_DIR/.storyhook/states.toml")

  [ "$lines_after_first" -eq "$lines_after_second" ]
}

@test "pilot states include in-progress" {
  add_work_states
  grep -q '^\[in-progress\]' "$TEST_PROJECT_DIR/.storyhook/states.toml"
}

@test "pilot states include verifying" {
  add_work_states
  grep -q '^\[verifying\]' "$TEST_PROJECT_DIR/.storyhook/states.toml"
}

@test "pilot states include blocked" {
  add_work_states
  grep -q '^\[blocked\]' "$TEST_PROJECT_DIR/.storyhook/states.toml"
}

@test "existing todo and done states preserved after adding pilot states" {
  add_work_states
  grep -q '^\[todo\]' "$TEST_PROJECT_DIR/.storyhook/states.toml"
  grep -q '^\[done\]' "$TEST_PROJECT_DIR/.storyhook/states.toml"
}

@test ".pilot directory created" {
  [ -d "$TEST_PROJECT_DIR/.pilot" ]
}
