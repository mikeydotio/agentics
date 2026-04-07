#!/usr/bin/env bats
# Tests for forge-archive.sh

SCRIPT="$BATS_TEST_DIRNAME/forge-archive.sh"

setup() {
  TEST_DIR="$(mktemp -d)"
  export TEST_DIR
  FORGE_DIR="$TEST_DIR/.forge"
  ARCHIVE_DIR="$TEST_DIR/.forge-archives"
  mkdir -p "$FORGE_DIR"
}

teardown() {
  if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
    rm -rf "$TEST_DIR"
  fi
}

# --- Output structure ---

@test "archive: output is valid JSON" {
  echo "# My Project" > "$FORGE_DIR/IDEA.md"
  run bash "$SCRIPT" "$FORGE_DIR" "$ARCHIVE_DIR"
  echo "$output" | jq . >/dev/null
}

@test "archive: ok is true when forge dir exists with content" {
  echo "# Test" > "$FORGE_DIR/IDEA.md"
  run bash "$SCRIPT" "$FORGE_DIR" "$ARCHIVE_DIR"
  local ok
  ok="$(echo "$output" | jq -r '.ok')"
  [ "$ok" = "true" ]
}

@test "archive: ok is false when no forge dir" {
  rm -rf "$FORGE_DIR"
  run bash "$SCRIPT" "$FORGE_DIR" "$ARCHIVE_DIR"
  local ok
  ok="$(echo "$output" | jq -r '.ok')"
  [ "$ok" = "false" ]
}

@test "archive: error field set when no forge dir" {
  rm -rf "$FORGE_DIR"
  run bash "$SCRIPT" "$FORGE_DIR" "$ARCHIVE_DIR"
  local err
  err="$(echo "$output" | jq -r '.error')"
  [ "$err" = "no_forge_dir" ]
}

# --- Archive directory ---

@test "archive: creates archive directory if missing" {
  echo "# Test" > "$FORGE_DIR/IDEA.md"
  [ ! -d "$ARCHIVE_DIR" ]
  run bash "$SCRIPT" "$FORGE_DIR" "$ARCHIVE_DIR"
  [ "$status" -eq 0 ]
  [ -d "$ARCHIVE_DIR" ]
}

# --- Tarball creation ---

@test "archive: tarball file exists after run" {
  echo "# Test" > "$FORGE_DIR/IDEA.md"
  run bash "$SCRIPT" "$FORGE_DIR" "$ARCHIVE_DIR"
  local archive_path
  archive_path="$(echo "$output" | jq -r '.archive_path')"
  [ -f "$archive_path" ]
}

@test "archive: removes .forge/ after archive" {
  echo "# Test" > "$FORGE_DIR/IDEA.md"
  run bash "$SCRIPT" "$FORGE_DIR" "$ARCHIVE_DIR"
  [ ! -d "$FORGE_DIR" ]
}

@test "archive: tarball contains forge files" {
  echo "# Test" > "$FORGE_DIR/IDEA.md"
  echo "design content" > "$FORGE_DIR/DESIGN.md"
  mkdir -p "$FORGE_DIR/handoffs"
  echo "handoff" > "$FORGE_DIR/handoffs/handoff-interrogate.md"
  run bash "$SCRIPT" "$FORGE_DIR" "$ARCHIVE_DIR"
  local archive_path
  archive_path="$(echo "$output" | jq -r '.archive_path')"
  local contents
  contents="$(tar tzf "$archive_path")"
  echo "$contents" | grep -q "IDEA.md"
  echo "$contents" | grep -q "DESIGN.md"
  echo "$contents" | grep -q "handoffs/handoff-interrogate.md"
}

@test "archive: includes gitignored runtime files" {
  echo "# Test" > "$FORGE_DIR/IDEA.md"
  echo '{"status":"paused"}' > "$FORGE_DIR/state.json"
  run bash "$SCRIPT" "$FORGE_DIR" "$ARCHIVE_DIR"
  local archive_path
  archive_path="$(echo "$output" | jq -r '.archive_path')"
  tar tzf "$archive_path" | grep -q "state.json"
}

# --- Project name extraction ---

@test "archive: extracts project name from IDEA.md" {
  echo "# Widget Dashboard" > "$FORGE_DIR/IDEA.md"
  run bash "$SCRIPT" "$FORGE_DIR" "$ARCHIVE_DIR"
  local slug
  slug="$(echo "$output" | jq -r '.project_slug')"
  [ "$slug" = "widget-dashboard" ]
}

@test "archive: uses unnamed when no IDEA.md" {
  echo "some other file" > "$FORGE_DIR/config.json"
  run bash "$SCRIPT" "$FORGE_DIR" "$ARCHIVE_DIR"
  local slug
  slug="$(echo "$output" | jq -r '.project_slug')"
  [ "$slug" = "unnamed" ]
}

@test "archive: slugifies special characters" {
  echo "# My Cool Project! (v2)" > "$FORGE_DIR/IDEA.md"
  run bash "$SCRIPT" "$FORGE_DIR" "$ARCHIVE_DIR"
  local slug
  slug="$(echo "$output" | jq -r '.project_slug')"
  # Should be lowercase, hyphens only, no special chars
  [[ "$slug" =~ ^[a-z0-9-]+$ ]]
  [[ "$slug" != *--* ]]
}

@test "archive: truncates long project names" {
  echo "# This Is A Very Long Project Name That Exceeds The Maximum Allowed Length For Slugs" > "$FORGE_DIR/IDEA.md"
  run bash "$SCRIPT" "$FORGE_DIR" "$ARCHIVE_DIR"
  local slug
  slug="$(echo "$output" | jq -r '.project_slug')"
  [ "${#slug}" -le 40 ]
}

# --- Archive naming ---

@test "archive: filename contains project slug" {
  echo "# My API" > "$FORGE_DIR/IDEA.md"
  run bash "$SCRIPT" "$FORGE_DIR" "$ARCHIVE_DIR"
  local name
  name="$(echo "$output" | jq -r '.archive_name')"
  [[ "$name" == forge-my-api-*.tar.gz ]]
}

@test "archive: filename contains timestamp" {
  echo "# Test" > "$FORGE_DIR/IDEA.md"
  run bash "$SCRIPT" "$FORGE_DIR" "$ARCHIVE_DIR"
  local name
  name="$(echo "$output" | jq -r '.archive_name')"
  # Match pattern: forge-test-YYYYMMDD-HHMMSS.tar.gz
  [[ "$name" =~ ^forge-test-[0-9]{8}-[0-9]{6}\.tar\.gz$ ]]
}

@test "archive: archive_path matches actual file location" {
  echo "# Test" > "$FORGE_DIR/IDEA.md"
  run bash "$SCRIPT" "$FORGE_DIR" "$ARCHIVE_DIR"
  local archive_path
  archive_path="$(echo "$output" | jq -r '.archive_path')"
  [ -f "$archive_path" ]
  [[ "$archive_path" == "$ARCHIVE_DIR/"* ]]
}

# --- Size reporting ---

@test "archive: reports non-zero archive size" {
  echo "# Test" > "$FORGE_DIR/IDEA.md"
  echo "lots of content here" > "$FORGE_DIR/DESIGN.md"
  run bash "$SCRIPT" "$FORGE_DIR" "$ARCHIVE_DIR"
  local size
  size="$(echo "$output" | jq -r '.archive_size')"
  [ "$size" -gt 0 ]
}
