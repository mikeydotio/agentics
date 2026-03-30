# Shared test helpers for pilot tests
# Source this from .bats files: load helpers

# Create a temporary project directory with mock storyhook
setup_test_project() {
  TEST_PROJECT_DIR="$(mktemp -d)"
  export TEST_PROJECT_DIR

  # Initialize git repo
  git -C "$TEST_PROJECT_DIR" init -q
  git -C "$TEST_PROJECT_DIR" config user.email "test@test.com"
  git -C "$TEST_PROJECT_DIR" config user.name "Test"

  # Create minimal storyhook structure
  mkdir -p "$TEST_PROJECT_DIR/.storyhook"
  cat > "$TEST_PROJECT_DIR/.storyhook/states.toml" <<'TOML'
[todo]
super = "open"
description = "Ready to pick up"

[done]
super = "closed"
description = "Completed"
TOML

  # Create .pilot directory
  mkdir -p "$TEST_PROJECT_DIR/.pilot"

  # Create .planning directory
  mkdir -p "$TEST_PROJECT_DIR/.planning"
}

teardown_test_project() {
  if [[ -n "${TEST_PROJECT_DIR:-}" && -d "$TEST_PROJECT_DIR" ]]; then
    rm -rf "$TEST_PROJECT_DIR"
  fi
}

# Create a mock state.json
create_state_json() {
  local status="${1:-paused}"
  cat > "$TEST_PROJECT_DIR/.pilot/state.json" <<EOF
{
  "version": 1,
  "project_story": "HP-1",
  "plan_file": ".planning/PLAN.md",
  "status": "$status",
  "trigger_name": "pilot-resume",
  "retry_counts": {},
  "canary_remaining": 0,
  "stories_this_session": 0,
  "stories_attempted": 0,
  "total_retries": 0,
  "sessions_completed": 0,
  "storyhook_consecutive_failures": 0,
  "started_at": "2026-03-28T12:00:00Z",
  "updated_at": "2026-03-28T14:30:00Z"
}
EOF
}

# Create a mock config.json
create_config_json() {
  cat > "$TEST_PROJECT_DIR/.pilot/config.json" <<'EOF'
{
  "max_retries": 4,
  "max_stories_per_session": 5,
  "max_sessions": 10,
  "max_total_retries": 20,
  "canary_stories": 3,
  "trigger_interval": "15m",
  "heartbeat_window_minutes": 30
}
EOF
}

# Create a mock lock.json
create_lock_json() {
  local heartbeat_at="${1:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
  cat > "$TEST_PROJECT_DIR/.pilot/lock.json" <<EOF
{
  "holder": "session-test-123",
  "acquired_at": "2026-03-28T14:30:00Z",
  "heartbeat_at": "$heartbeat_at"
}
EOF
}

# Create a stale lock (heartbeat > 31 minutes ago)
create_stale_lock() {
  local stale_time
  stale_time="$(date -u -d '35 minutes ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-35M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
  create_lock_json "$stale_time"
}

# Append pilot states to states.toml
add_work_states() {
  cat >> "$TEST_PROJECT_DIR/.storyhook/states.toml" <<'TOML'

[in-progress]
super = "open"
description = "Generator working on this story"

[verifying]
super = "open"
description = "Evaluator reviewing this story"

[blocked]
super = "open"
description = "Dependency unmet, decision needed, or max retries exhausted"
TOML
}

# Create a minimal PLAN.md with waves
create_test_plan() {
  cat > "$TEST_PROJECT_DIR/.planning/PLAN.md" <<'EOF'
# Implementation Plan

## Task Breakdown

### Wave 1 (no dependencies)
- [ ] Task 1.1: Create config module
  - Acceptance: Config loads from YAML file and returns typed object
  - Files: src/config.ts
- [ ] Task 1.2: Create logger module
  - Acceptance: Logger writes structured JSON to stdout
  - Files: src/logger.ts

### Wave 2 (depends on Wave 1)
- [ ] Task 2.1: Create API server
  - Acceptance: Server starts on configured port and responds to health check
  - Files: src/server.ts, src/routes/health.ts
EOF
}

# Create a minimal DESIGN.md
create_test_design() {
  cat > "$TEST_PROJECT_DIR/.planning/DESIGN.md" <<'EOF'
# System Design

## Config Module
Loads YAML config from disk. Returns a typed configuration object.

## Logger Module
Structured JSON logger. Writes to stdout. Supports log levels.

## API Server
Express-based HTTP server. Reads config for port. Health check endpoint at GET /health.
EOF
}

# Assert file contains string
assert_file_contains() {
  local file="$1" expected="$2"
  if ! grep -qF "$expected" "$file"; then
    echo "Expected '$file' to contain: $expected" >&2
    echo "Actual content:" >&2
    cat "$file" >&2
    return 1
  fi
}

# Assert JSON field value
assert_json_field() {
  local file="$1" field="$2" expected="$3"
  local actual
  actual="$(jq -r "$field" "$file")"
  if [[ "$actual" != "$expected" ]]; then
    echo "Expected $field to be '$expected' but got '$actual'" >&2
    return 1
  fi
}
