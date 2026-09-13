#!/usr/bin/env bats
load contract-helper

@test "Codex deterministic Bash approval emits no permission decision or orphan reason" {
  run_payload "$(payload codex Bash pwd)"
  assert_neutral
  [ -z "$output" ]
  [ ! -e "$GL_TEST_ROOT/curl.log" ]
}

@test "Claude deterministic Bash approval retains allow and reason" {
  run_payload "$(payload claude Bash pwd)"
  assert_decision allow
  [ ! -e "$GL_TEST_ROOT/curl.log" ]
}

@test "Codex readonly tool approval is neutral" {
  run_payload "$(payload codex Read '')"
  assert_neutral
  [ -z "$output" ]
}

@test "Claude readonly tool approval retains allow" {
  run_payload "$(payload claude Read '')"
  assert_decision allow
}

@test "Codex AI safe approval without rationale is neutral after parsing boolean false" {
  run_safe_ai codex false
  assert_neutral
  [ -z "$output" ]
}

@test "Codex AI safe approval with rationale emits context only" {
  run_safe_ai codex true
  assert_neutral
  assert_context 'Fixture confirms read-only behavior.'
}

@test "Claude AI safe approval without rationale retains allow" {
  run_safe_ai claude false
  assert_decision allow
  jq -e '.hookSpecificOutput | has("additionalContext") | not' <<< "$output"
}

@test "Claude AI safe approval with rationale retains allow and context" {
  run_safe_ai claude true
  assert_decision allow
  assert_context 'Fixture confirms read-only behavior.'
}

@test "Codex plan explorer destructive command remains denied" {
  run_payload "$(payload codex Bash 'rm -rf fixture-directory')" 1
  assert_decision deny
}

@test "Claude plan explorer destructive command remains denied" {
  run_payload "$(payload claude Bash 'rm -rf fixture-directory')" 1
  assert_decision deny
}

@test "Codex destructive warning remains context only" {
  run_payload "$(payload codex Bash 'rm -rf fixture-directory')"
  assert_neutral
  assert_context 'file deletion'
}

@test "Claude destructive warning remains context only" {
  run_payload "$(payload claude Bash 'rm -rf fixture-directory')"
  assert_neutral
  assert_context 'file deletion'
}

@test "Malformed JSON remains inert" {
  run_payload '{'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "Codex unrelated tool remains inert" {
  run_payload "$(payload codex SomeFutureTool '')"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "Claude unrelated tool remains inert" {
  run_payload "$(payload claude SomeFutureTool '')"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "Codex manifest invocation resolves its PLUGIN_ROOT-only environment" {
  local invocation
  invocation="$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$GL_PLUGIN_ROOT/hooks/hooks.json")"
  run env -i HOME="$GL_TEST_ROOT" PATH="$GL_TEST_ROOT/bin:$PATH" \
    PLUGIN_ROOT="$GL_PLUGIN_ROOT" bash -c "$invocation" <<< "$(payload codex Bash pwd)"
  assert_neutral
}

@test "turn_id presence selects Codex regardless of its value or root environment" {
  local value json
  for value in null false 0 '""' '"test-turn"'; do
    json="$(payload claude Bash pwd | jq -c --argjson value "$value" '. + {turn_id:$value}')"
    run_payload "$json"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    grep -F '[ALLOW] Bash: Bash: safe readonly command(s)' "$GL_TEST_ROOT/decisions.log"
  done
}

@test "PLUGIN_ROOT alone does not misclassify a Claude payload as Codex" {
  run env -i HOME="$GL_TEST_ROOT" PATH="$GL_TEST_ROOT/bin:$PATH" \
    PLUGIN_ROOT="$GL_PLUGIN_ROOT" bash "$GL_HOOK" <<< "$(payload claude Bash pwd)"
  assert_decision allow
}

@test "AI rationale survives JSON escaping for both hosts with unchanged log detail" {
  local provider rationale
  rationale='Fixture "quotes" and \slashes
second line with literal $HOME and $(pwd).'
  printf 'ai_enabled: true\nai_show_rationale: true\nlog_file: %s/decisions.log\n' "$GL_TEST_ROOT" > "$GL_CONFIG"
  jq -cn --arg rationale "$rationale" \
    '{content:[{type:"text",text:({answer:false,rationale:$rationale}|tojson)}]}' > "$GL_TEST_ROOT/response.json"
  for provider in claude codex; do
    run_payload "$(payload "$provider" Bash 'unknown-readonly-tool --inspect')"
    [ "$status" -eq 0 ]
    jq -e --arg expected "[greenlight] AI analysis: $rationale" \
      '.hookSpecificOutput.additionalContext == $expected' <<< "$output"
    if [[ "$provider" == codex ]]; then
      jq -e '.hookSpecificOutput | keys == ["additionalContext", "hookEventName"]' <<< "$output"
    else
      assert_decision allow
    fi
    grep -F '[ALLOW] AI confirmed safe: Fixture "quotes" and \slashes' "$GL_TEST_ROOT/decisions.log"
  done
}
