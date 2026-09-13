#!/usr/bin/env bats
load contract-helper

assert_parse_failure() {
  [ "$status" -eq 0 ] || return 1
  [ -z "$output" ] || return 1
  grep -F '[AI_FAIL]' "$GL_TEST_ROOT/decisions.log" || return 1
  grep -F '[PASS] AI fallback failed, deferring to user' "$GL_TEST_ROOT/decisions.log" || return 1
  ! grep -E '\[(ALLOW|AI_RESULT)\]' "$GL_TEST_ROOT/decisions.log"
}


@test "AI boolean false approves with rationale disabled" {
  run_safe_ai claude false
  assert_decision allow
  jq -e '.hookSpecificOutput | has("additionalContext") | not' <<< "$output"
}

@test "AI boolean false approves and retains rationale and diagnostics" {
  run_safe_ai claude true
  assert_decision allow
  assert_context 'Fixture confirms read-only behavior.'
  grep -F '[ALLOW] AI confirmed safe: Fixture confirms read-only behavior.' "$GL_TEST_ROOT/decisions.log"
}

set_response() {
  printf 'ai_enabled: true\nai_show_rationale: true\nlog_file: %s/decisions.log\n' "$GL_TEST_ROOT" > "$GL_CONFIG"
  jq -cn --arg text "$1" '{content:[{type:"text",text:$text}]}' > "$GL_TEST_ROOT/response.json"
}


@test "AI boolean true preserves destructive context for both hosts" {
  local provider
  for provider in claude codex; do
    set_response '{"answer":true,"rationale":"Fixture changes files."}'
    run_payload "$(payload "$provider" Bash 'unknown-tool --inspect')"
    assert_neutral
    assert_context 'POTENTIALLY DESTRUCTIVE. Fixture changes files.'
    grep -F '[AI_RESULT] answer=true rationale=Fixture changes files.' "$GL_TEST_ROOT/decisions.log"
  done
}

@test "AI rejects every nonboolean answer instead of treating it as safe" {
  local answer
  for answer in null '"false"' '"true"' '"unexpected"' 0 1 '[]' '{}' '""'; do
    : > "$GL_TEST_ROOT/decisions.log"
    set_response "$(jq -cn --argjson answer "$answer" '{answer:$answer,rationale:"Fixture rationale."}')"
    run_payload "$(payload claude Bash 'unknown-tool --inspect')"
    assert_parse_failure || return 1
  done
}

@test "AI rejects missing fields and malformed structured text" {
  local text
  for text in '{"rationale":"Fixture rationale."}' '{"answer":true}' '{' '[]' 'null' 'false' '{"answer":true,"rationale":"First"} {"answer":false,"rationale":"Second"}'; do
    : > "$GL_TEST_ROOT/decisions.log"
    set_response "$text"
    run_payload "$(payload claude Bash 'unknown-tool --inspect')"
    assert_parse_failure || return 1
  done
}

@test "AI rejects invalid rationales even with a valid boolean answer" {
  local rationale
  for rationale in null false true 0 1 '[]' '{}' '""'; do
    : > "$GL_TEST_ROOT/decisions.log"
    set_response "$(jq -cn --argjson rationale "$rationale" '{answer:true,rationale:$rationale}')"
    run_payload "$(payload claude Bash 'unknown-tool --inspect')"
    assert_parse_failure || return 1
  done
}

@test "AI malformed outer response defers with diagnostics" {
  set_response '{}'
  printf '{' > "$GL_TEST_ROOT/response.json"
  run_payload "$(payload claude Bash 'unknown-tool --inspect')"
  assert_parse_failure
}
