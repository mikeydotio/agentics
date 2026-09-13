#!/usr/bin/env bats
# A writable output path must not authorize the command that produces output.
load contract-helper

@test "AGE-54: writable redirection cannot approve uncertain execution" {
  local provider setting command
  for provider in claude codex; do
    for setting in deny allow; do
      printf 'plan_explorer_uncertain: %s\nai_enabled: false\n' "$setting" > "$GL_CONFIG"
      for command in 'npx some-package' 'bash -c "echo hi"' 'story doctor' \
        'unknown-executable --inspect'; do
        run_payload "$(payload "$provider" Bash "$command > $GL_TEST_ROOT/output")" 1
        assert_decision deny
        [ ! -e "$GL_TEST_ROOT/output" ]
        [ ! -e "$GL_TEST_ROOT/curl.log" ]
      done
    done
  done
}

@test "AGE-54: writable redirection cannot approve destructive execution or invoke AI" {
  local provider command
  printf 'plan_explorer_uncertain: ai\nai_enabled: true\n' > "$GL_CONFIG"
  jq -cn '{content:[{type:"text",text:({answer:false,rationale:"Fixture would approve."}|tojson)}]}' \
    > "$GL_TEST_ROOT/response.json"
  for provider in claude codex; do
    for command in 'rm fixture' 'story purge ST-1 --force' 'story update --force' \
      'story plugin install package' 'sudo some-command'; do
      run_payload "$(payload "$provider" Bash "$command >> $GL_TEST_ROOT/output")" 1
      assert_decision deny
      [[ "$output" == *'destructive/privileged'* ]]
      [ ! -e "$GL_TEST_ROOT/curl.log" ]
    done
  done
}

@test "AGE-54: writable redirection still checks later segments and substitutions" {
  local provider command
  for provider in claude codex; do
    for command in "echo hi > $GL_TEST_ROOT/output && npx some-package" \
      "echo hi > $GL_TEST_ROOT/output; story purge ST-1 --force" \
      'echo $(npx some-package)' 'echo `npx some-package`' \
      'echo $(story purge ST-1 --force)'; do
      run_payload "$(payload "$provider" Bash "$command > $GL_TEST_ROOT/output")" 1
      assert_decision deny
    done
  done
}

@test "AGE-54: safe temporary redirection retains host-specific approval" {
  local provider operator
  for provider in claude codex; do
    for operator in '>' '>>' '2>'; do
      run_payload "$(payload "$provider" Bash "echo hi $operator $GL_TEST_ROOT/output")" 1
      if [[ "$provider" == claude ]]; then assert_decision allow; else assert_neutral; fi
      [ ! -e "$GL_TEST_ROOT/output" ]
    done
  done
}

@test "AGE-54: protected or indeterminate destinations deny before AI evaluation" {
  local provider command
  git init -q "$GL_TEST_ROOT/protected"
  printf 'plan_explorer_uncertain: ai\nai_enabled: true\n' > "$GL_CONFIG"
  for provider in claude codex; do
    for command in "unknown-executable > $GL_TEST_ROOT/protected/output" \
      "echo hi > $GL_TEST_ROOT/protected/output" 'echo hi >'; do
      run_payload "$(payload "$provider" Bash "$command")" 1
      assert_decision deny
      [ ! -e "$GL_TEST_ROOT/curl.log" ]
    done
  done
}

@test "AGE-54: redirected uncertainty reaches opted-in AI instead of early approval" {
  local provider
  printf 'plan_explorer_uncertain: ai\nai_enabled: true\nlog_file: %s/decisions.log\n' \
    "$GL_TEST_ROOT" > "$GL_CONFIG"
  jq -cn '{content:[{type:"text",text:({answer:false,rationale:"Fixture would approve."}|tojson)}]}' \
    > "$GL_TEST_ROOT/response.json"
  for provider in claude codex; do
    : > "$GL_TEST_ROOT/curl.log"
    run_payload "$(payload "$provider" Bash "unknown-executable > $GL_TEST_ROOT/output")" 1
    if [[ "$provider" == claude ]]; then assert_decision allow; else assert_neutral; fi
    [ -s "$GL_TEST_ROOT/curl.log" ]
    grep -F 'AI_RESULT] answer=false' "$GL_TEST_ROOT/decisions.log"
    grep -F "unknown-executable > $GL_TEST_ROOT/output" "$GL_TEST_ROOT/curl.log"
  done
}

@test "AGE-54: normal-session redirection still defers without an AI call" {
  local provider command
  printf 'ai_enabled: true\n' > "$GL_CONFIG"
  for provider in claude codex; do
    for command in 'echo hi' 'npx some-package' 'rm fixture'; do
      run_payload "$(payload "$provider" Bash "$command > $GL_TEST_ROOT/output")"
      assert_neutral
      [ -z "$output" ]
      [ ! -e "$GL_TEST_ROOT/curl.log" ]
    done
  done
}
