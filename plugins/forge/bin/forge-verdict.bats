#!/usr/bin/env bats
# Tests for forge-verdict.sh — deterministic append to .forge/verdicts.jsonl
# (F034), matching the single evaluator verdict schema unified in
# plugins/agents/agents/evaluator.md (WS3).

SCRIPT="$BATS_TEST_DIRNAME/forge-verdict.sh"

setup() {
  TEST_DIR="$(mktemp -d)"
  FORGE_DIR="$TEST_DIR/.forge"
  mkdir -p "$FORGE_DIR"
}

teardown() {
  rm -rf "$TEST_DIR"
}

jq_field() {
  echo "$output" | jq -r "$1"
}

# --- Required arguments ---

@test "requires --story" {
  run bash "$SCRIPT" --attempt 1 --verdict pass --failures-json '[]' --forge-dir "$FORGE_DIR"
  [ "$status" -ne 0 ]
}

@test "requires --attempt" {
  run bash "$SCRIPT" --story ST-1 --verdict pass --failures-json '[]' --forge-dir "$FORGE_DIR"
  [ "$status" -ne 0 ]
}

@test "requires --verdict to be pass or fail" {
  run bash "$SCRIPT" --story ST-1 --attempt 1 --verdict maybe --failures-json '[]' --forge-dir "$FORGE_DIR"
  [ "$status" -ne 0 ]
}

@test "requires --failures-json" {
  run bash "$SCRIPT" --story ST-1 --attempt 1 --verdict pass --forge-dir "$FORGE_DIR"
  [ "$status" -ne 0 ]
}

@test "rejects malformed --failures-json" {
  run bash "$SCRIPT" --story ST-1 --attempt 1 --verdict pass --failures-json 'not json' --forge-dir "$FORGE_DIR"
  [ "$status" -ne 0 ]
}

@test "rejects malformed --verdict-json" {
  run bash "$SCRIPT" --story ST-1 --attempt 1 --verdict pass --failures-json '[]' --verdict-json 'not json' --forge-dir "$FORGE_DIR"
  [ "$status" -ne 0 ]
}

@test "rejects --verdict-json whose own .verdict disagrees with --verdict" {
  run bash "$SCRIPT" --story ST-1 --attempt 1 --verdict pass --failures-json '[]' \
    --verdict-json '{"verdict":"fail","failures":[]}' --forge-dir "$FORGE_DIR"
  [ "$status" -ne 0 ]
  [ ! -f "$FORGE_DIR/verdicts.jsonl" ]
}

# --- Minimal (failures-json only) form ---

@test "appends a well-formed line for a passing verdict with no failures" {
  run bash "$SCRIPT" --story ST-1 --attempt 1 --verdict pass --failures-json '[]' --forge-dir "$FORGE_DIR"
  [ "$status" -eq 0 ]
  [ "$(jq_field '.ok')" = "true" ]
  [ -f "$FORGE_DIR/verdicts.jsonl" ]
  line="$(tail -n1 "$FORGE_DIR/verdicts.jsonl")"
  [ "$(echo "$line" | jq -r '.story')" = "ST-1" ]
  [ "$(echo "$line" | jq -r '.attempt')" = "1" ]
  [ "$(echo "$line" | jq -r '.verdict_full.verdict')" = "pass" ]
  [ "$(echo "$line" | jq -r '.verdict_full.failures | length')" = "0" ]
  [ "$(echo "$line" | jq -r '.timestamp')" != "null" ]
}

@test "appends the failures array verbatim for a failing verdict" {
  run bash "$SCRIPT" --story ST-2 --attempt 2 --verdict fail \
    --failures-json '[{"category":"criteria","criterion":"c1","evidence":"e1","suggestion":"s1"}]' \
    --forge-dir "$FORGE_DIR"
  [ "$status" -eq 0 ]
  line="$(tail -n1 "$FORGE_DIR/verdicts.jsonl")"
  [ "$(echo "$line" | jq -r '.verdict_full.verdict')" = "fail" ]
  [ "$(echo "$line" | jq -r '.verdict_full.failures | length')" = "1" ]
  [ "$(echo "$line" | jq -r '.verdict_full.failures[0].criterion')" = "c1" ]
}

# --- Full evaluator-schema passthrough form ---

@test "verdict-json passthrough stores the full schema fields verbatim" {
  full='{"verdict":"fail","failures":[{"category":"security","criterion":"x","evidence":"y","suggestion":"z"}],"criteria_checks":[{"criterion":"c","status":"fail","evidence":"e"}],"edge_case_findings":[],"security_findings":[{"vulnerability":"v","severity":"high","location":"f:1"}],"design_adherence":"drifted","design_drift_details":"d","summary":"s"}'
  run bash "$SCRIPT" --story ST-3 --attempt 1 --verdict fail --failures-json '[]' --verdict-json "$full" --forge-dir "$FORGE_DIR"
  [ "$status" -eq 0 ]
  line="$(tail -n1 "$FORGE_DIR/verdicts.jsonl")"
  [ "$(echo "$line" | jq -r '.verdict_full.design_adherence')" = "drifted" ]
  [ "$(echo "$line" | jq -r '.verdict_full.security_findings | length')" = "1" ]
  [ "$(echo "$line" | jq -r '.verdict_full.criteria_checks | length')" = "1" ]
  [ "$(echo "$line" | jq -r '.verdict_full.summary')" = "s" ]
}

# --- Append semantics ---

@test "multiple calls append multiple lines, never overwrite" {
  bash "$SCRIPT" --story ST-1 --attempt 1 --verdict fail --failures-json '[]' --forge-dir "$FORGE_DIR" >/dev/null
  bash "$SCRIPT" --story ST-1 --attempt 2 --verdict pass --failures-json '[]' --forge-dir "$FORGE_DIR" >/dev/null
  [ "$(wc -l < "$FORGE_DIR/verdicts.jsonl" | tr -d ' ')" = "2" ]
  first_verdict="$(sed -n '1p' "$FORGE_DIR/verdicts.jsonl" | jq -r '.verdict_full.verdict')"
  second_verdict="$(sed -n '2p' "$FORGE_DIR/verdicts.jsonl" | jq -r '.verdict_full.verdict')"
  [ "$first_verdict" = "fail" ]
  [ "$second_verdict" = "pass" ]
}

@test "each line is valid, self-contained JSON (true jsonl, not one big array)" {
  bash "$SCRIPT" --story ST-1 --attempt 1 --verdict pass --failures-json '[]' --forge-dir "$FORGE_DIR" >/dev/null
  bash "$SCRIPT" --story ST-2 --attempt 1 --verdict pass --failures-json '[]' --forge-dir "$FORGE_DIR" >/dev/null
  while IFS= read -r l; do
    echo "$l" | jq . >/dev/null
  done < "$FORGE_DIR/verdicts.jsonl"
}

@test "output is always valid JSON" {
  run bash "$SCRIPT" --story ST-1 --attempt 1 --verdict pass --failures-json '[]' --forge-dir "$FORGE_DIR"
  echo "$output" | jq . >/dev/null
}
