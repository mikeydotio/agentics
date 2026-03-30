#!/usr/bin/env bats
# Tests for pilot state machine — state transitions, config, locking

load helpers

setup() {
  setup_test_project
  add_work_states
}

teardown() {
  teardown_test_project
}

# --- State File Tests ---

@test "state.json can be created with valid structure" {
  create_state_json "paused"
  [ -f "$TEST_PROJECT_DIR/.pilot/state.json" ]
  assert_json_field "$TEST_PROJECT_DIR/.pilot/state.json" ".version" "1"
  assert_json_field "$TEST_PROJECT_DIR/.pilot/state.json" ".status" "paused"
}

@test "state.json status values are valid" {
  for status in running paused complete; do
    create_state_json "$status"
    assert_json_field "$TEST_PROJECT_DIR/.pilot/state.json" ".status" "$status"
  done
}

@test "config.json has all required fields" {
  create_config_json
  [ -f "$TEST_PROJECT_DIR/.pilot/config.json" ]
  assert_json_field "$TEST_PROJECT_DIR/.pilot/config.json" ".max_retries" "4"
  assert_json_field "$TEST_PROJECT_DIR/.pilot/config.json" ".max_stories_per_session" "5"
  assert_json_field "$TEST_PROJECT_DIR/.pilot/config.json" ".max_sessions" "10"
  assert_json_field "$TEST_PROJECT_DIR/.pilot/config.json" ".max_total_retries" "20"
  assert_json_field "$TEST_PROJECT_DIR/.pilot/config.json" ".canary_stories" "3"
  assert_json_field "$TEST_PROJECT_DIR/.pilot/config.json" ".trigger_interval" "15m"
  assert_json_field "$TEST_PROJECT_DIR/.pilot/config.json" ".heartbeat_window_minutes" "30"
}

# --- Lock Tests ---

@test "lock.json can be created" {
  create_lock_json
  [ -f "$TEST_PROJECT_DIR/.pilot/lock.json" ]
  assert_json_field "$TEST_PROJECT_DIR/.pilot/lock.json" ".holder" "session-test-123"
}

@test "fresh lock heartbeat is within window" {
  create_lock_json
  local heartbeat_at
  heartbeat_at="$(jq -r '.heartbeat_at' "$TEST_PROJECT_DIR/.pilot/lock.json")"
  local heartbeat_epoch
  heartbeat_epoch="$(date -d "$heartbeat_at" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$heartbeat_at" +%s 2>/dev/null)"
  local now_epoch
  now_epoch="$(date +%s)"
  local age_minutes=$(( (now_epoch - heartbeat_epoch) / 60 ))
  [ "$age_minutes" -lt 30 ]
}

@test "stale lock heartbeat exceeds window" {
  create_stale_lock
  local heartbeat_at
  heartbeat_at="$(jq -r '.heartbeat_at' "$TEST_PROJECT_DIR/.pilot/lock.json")"
  local heartbeat_epoch
  heartbeat_epoch="$(date -d "$heartbeat_at" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$heartbeat_at" +%s 2>/dev/null)"
  local now_epoch
  now_epoch="$(date +%s)"
  local age_minutes=$(( (now_epoch - heartbeat_epoch) / 60 ))
  [ "$age_minutes" -ge 30 ]
}

# --- Verdict Log Tests ---

@test "verdict entry has required fields" {
  local verdict='{"story":"HP-5","attempt":1,"verdict":"fail","failures":[{"criterion":"API returns 404","evidence":"handler returns 500","suggestion":"add NotFoundError catch"}],"timestamp":"2026-03-28T14:35:00Z"}'
  echo "$verdict" > "$TEST_PROJECT_DIR/.pilot/verdicts.jsonl"

  assert_json_field "$TEST_PROJECT_DIR/.pilot/verdicts.jsonl" ".story" "HP-5"
  assert_json_field "$TEST_PROJECT_DIR/.pilot/verdicts.jsonl" ".verdict" "fail"
  [ "$(jq '.failures | length' "$TEST_PROJECT_DIR/.pilot/verdicts.jsonl")" -eq 1 ]
}

# --- Plan Mapping Tests ---

@test "plan-mapping.json structure is valid" {
  cat > "$TEST_PROJECT_DIR/.pilot/plan-mapping.json" <<'EOF'
{
  "plan_hash": "abc123",
  "project_story": "HP-1",
  "stories": {
    "HP-2": {
      "task_ref": "Task 1.1",
      "wave": 1,
      "title": "Create config module",
      "acceptance_criteria": "Config loads from YAML file and returns typed object",
      "design_section": "## Config Module\nLoads YAML config from disk.",
      "files_expected": ["src/config.ts"]
    }
  }
}
EOF

  assert_json_field "$TEST_PROJECT_DIR/.pilot/plan-mapping.json" ".plan_hash" "abc123"
  [ "$(jq '.stories | length' "$TEST_PROJECT_DIR/.pilot/plan-mapping.json")" -eq 1 ]
  assert_json_field "$TEST_PROJECT_DIR/.pilot/plan-mapping.json" '.stories["HP-2"].wave' "1"
}
