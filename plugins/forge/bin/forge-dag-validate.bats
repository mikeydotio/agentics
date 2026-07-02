#!/usr/bin/env bats
# Tests for forge-dag-validate.sh — blocked-by cycle detection
#
# Drives the real `story` CLI against throwaway git+storyhook projects in
# /tmp (never mocked — see CLAUDE.md). Requires `story` on PATH; install via
# the storyhook-install skill if these are skipped/fail with "command not
# found".

SCRIPT="$BATS_TEST_DIRNAME/forge-dag-validate.sh"

setup() {
  TEST_DIR="$(mktemp -d)"
  export TEST_DIR
  ( cd "$TEST_DIR" && git init -q . && story init --prefix DV >/dev/null 2>&1 )
}

teardown() {
  if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
    rm -rf "$TEST_DIR"
  fi
}

jq_field() {
  echo "$output" | jq -r "$1"
}

# --- story CLI unavailable ---

@test "dag-validate: ok is false when story CLI is not on PATH" {
  PATH="/usr/bin:/bin" run bash "$SCRIPT" "$TEST_DIR"
  [ "$status" -eq 0 ]
  [ "$(jq_field '.ok')" = "false" ]
  [ "$(jq_field '.error')" = "story_cli_missing" ]
}

# --- Uninitialized project ---

@test "dag-validate: ok is false when .storyhook project is not initialized" {
  UNINIT_DIR="$(mktemp -d)"
  run bash "$SCRIPT" "$UNINIT_DIR"
  [ "$status" -eq 0 ]
  [ "$(jq_field '.ok')" = "false" ]
  [ "$(jq_field '.error')" = "story_list_failed" ]
  rm -rf "$UNINIT_DIR"
}

# --- Empty project ---

@test "dag-validate: zero stories is ok with no cycles" {
  run bash "$SCRIPT" "$TEST_DIR"
  [ "$status" -eq 0 ]
  [ "$(jq_field '.ok')" = "true" ]
  [ "$(jq_field '.has_cycles')" = "false" ]
  [ "$(jq_field '.story_count')" = "0" ]
  [ "$(echo "$output" | jq '.cycles | length')" -eq 0 ]
}

# --- Output structure ---

@test "dag-validate: output is valid JSON" {
  run bash "$SCRIPT" "$TEST_DIR"
  echo "$output" | jq . >/dev/null
}

@test "dag-validate: has a display field" {
  run bash "$SCRIPT" "$TEST_DIR"
  echo "$output" | jq -e '.display' >/dev/null
}

# --- Acyclic graphs ---

@test "dag-validate: forward wave-style chain has no cycles" {
  ( cd "$TEST_DIR" && \
    story new "Root" >/dev/null && \
    story new "A" >/dev/null && \
    story new "B" >/dev/null && \
    story relate DV-1 blocks DV-2 >/dev/null && \
    story relate DV-2 blocks DV-3 >/dev/null )
  run bash "$SCRIPT" "$TEST_DIR"
  [ "$status" -eq 0 ]
  [ "$(jq_field '.ok')" = "true" ]
  [ "$(jq_field '.has_cycles')" = "false" ]
  [ "$(jq_field '.story_count')" = "3" ]
}

@test "dag-validate: disconnected acyclic components have no cycles" {
  ( cd "$TEST_DIR" && \
    story new "A1" >/dev/null && story new "A2" >/dev/null && \
    story new "B1" >/dev/null && story new "B2" >/dev/null && \
    story relate DV-1 blocks DV-2 >/dev/null && \
    story relate DV-3 blocks DV-4 >/dev/null )
  run bash "$SCRIPT" "$TEST_DIR"
  [ "$(jq_field '.has_cycles')" = "false" ]
}

# --- Cyclic graphs ---

@test "dag-validate: direct two-story cycle is detected" {
  ( cd "$TEST_DIR" && \
    story new "A" >/dev/null && story new "B" >/dev/null && \
    story relate DV-1 blocks DV-2 >/dev/null && \
    story relate DV-2 blocks DV-1 >/dev/null )
  run bash "$SCRIPT" "$TEST_DIR"
  [ "$status" -eq 0 ]
  [ "$(jq_field '.ok')" = "true" ]
  [ "$(jq_field '.has_cycles')" = "true" ]
  [ "$(echo "$output" | jq '.cycles | length')" -eq 1 ]
  echo "$output" | jq -e '.cycles[0] | index("DV-1") != null' >/dev/null
  echo "$output" | jq -e '.cycles[0] | index("DV-2") != null' >/dev/null
}

@test "dag-validate: indirect multi-story cycle is detected" {
  ( cd "$TEST_DIR" && \
    story new "Root" >/dev/null && story new "A" >/dev/null && \
    story new "B" >/dev/null && \
    story relate DV-1 blocks DV-2 >/dev/null && \
    story relate DV-2 blocks DV-3 >/dev/null && \
    story relate DV-3 blocks DV-1 >/dev/null )
  run bash "$SCRIPT" "$TEST_DIR"
  [ "$(jq_field '.has_cycles')" = "true" ]
  local cycle_len
  cycle_len="$(echo "$output" | jq '.cycles[0] | length')"
  [ "$cycle_len" -ge 4 ]
}

@test "dag-validate: reported cycle path closes back on its first element" {
  ( cd "$TEST_DIR" && \
    story new "A" >/dev/null && story new "B" >/dev/null && \
    story relate DV-1 blocks DV-2 >/dev/null && \
    story relate DV-2 blocks DV-1 >/dev/null )
  run bash "$SCRIPT" "$TEST_DIR"
  echo "$output" | jq -e '.cycles[0] | .[0] == .[-1]' >/dev/null
}

@test "dag-validate: display reports FAILED with the cycle count when a cycle exists" {
  ( cd "$TEST_DIR" && \
    story new "A" >/dev/null && story new "B" >/dev/null && \
    story relate DV-1 blocks DV-2 >/dev/null && \
    story relate DV-2 blocks DV-1 >/dev/null )
  run bash "$SCRIPT" "$TEST_DIR"
  [[ "$(jq_field '.display')" == *"FAILED"* ]]
}

@test "dag-validate: display reports OK when no cycle exists" {
  ( cd "$TEST_DIR" && story new "A" >/dev/null )
  run bash "$SCRIPT" "$TEST_DIR"
  [[ "$(jq_field '.display')" == *"OK"* ]]
}

# --- Closed stories don't produce false positives ---

@test "dag-validate: a blocked-by edge to a since-closed story is not a cycle" {
  ( cd "$TEST_DIR" && \
    story new "A" >/dev/null && story new "B" >/dev/null && \
    story relate DV-2 blocked-by DV-1 >/dev/null && \
    story move DV-1 done >/dev/null )
  run bash "$SCRIPT" "$TEST_DIR"
  [ "$(jq_field '.ok')" = "true" ]
  [ "$(jq_field '.has_cycles')" = "false" ]
}

# --- Defaults to cwd when no project dir is given ---

@test "dag-validate: defaults to the current directory when no argument is given" {
  ( cd "$TEST_DIR" && story new "A" >/dev/null && \
    output="$(bash "$SCRIPT")" && \
    echo "$output" | jq -e '.ok == true' >/dev/null )
}

# --- Stderr noise on a successful call must not corrupt the JSON parse ---

@test "dag-validate: a stderr warning alongside a successful call doesn't break output" {
  local real_story
  real_story="$(command -v story)"
  local shim_dir="$TEST_DIR/shim"
  mkdir -p "$shim_dir"
  cat > "$shim_dir/story" <<EOF
#!/usr/bin/env bash
echo "warning: something noisy" >&2
exec "$real_story" "\$@"
EOF
  chmod +x "$shim_dir/story"
  ( cd "$TEST_DIR" && story new "A" >/dev/null )
  PATH="$shim_dir:$PATH" run bash "$SCRIPT" "$TEST_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | jq . >/dev/null
  [ "$(jq_field '.ok')" = "true" ]
  [ "$(jq_field '.story_count')" = "1" ]
}
