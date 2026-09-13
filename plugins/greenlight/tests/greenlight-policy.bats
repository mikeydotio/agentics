#!/usr/bin/env bats
# Exercise explorer policy through the production hook; commands are JSON data.
load contract-helper

configure_policy() {
  printf 'ai_enabled: %s\nai_show_rationale: false\nlog_file: %s/decisions.log\n' \
    "${2:-false}" "$GL_TEST_ROOT" > "$GL_CONFIG"
  if [[ "$1" != missing ]]; then
    printf 'plan_explorer_uncertain: %s\n' "$1" >> "$GL_CONFIG"
  fi
}

safe_response() {
  jq -cn '{content:[{type:"text",text:({answer:false,rationale:"Fixture confirms read-only behavior."}|tojson)}]}' \
    > "$GL_TEST_ROOT/response.json"
}

@test "AGE-54: legacy allow denies every uncertain execution family on both hosts" {
  local provider command
  configure_policy allow
  cp "$GL_CONFIG" "$GL_TEST_ROOT/original-config"
  for provider in claude codex; do
    for command in 'npx some-package' 'bunx some-package' 'pipx run some-package' \
      'uvx some-package' 'npm exec some-package' 'bash -c "echo hi"' \
      'sh -c "echo hi"' 'python3 -c "print(1)"' 'node -e "console.log(1)"' \
      'unknown-executable --inspect' './unknown-script' 'story doctor' \
      'story hooks install' 'story unknown-verb' '/usr/local/bin/npx some-package' \
      'env MODE=test npx some-package' 'time -p npx some-package'; do
      run_payload "$(payload "$provider" Bash "$command")" 1
      assert_decision deny
      [[ "$output" == *'plan_explorer_uncertain: allow'* ]]
      [[ "$output" == *'unsupported'* ]]
      [[ "$output" == *'deny'* && "$output" == *'ai'* ]]
    done
  done
  cmp "$GL_CONFIG" "$GL_TEST_ROOT/original-config"
  [ ! -e "$GL_TEST_ROOT/curl.log" ]
}

@test "AGE-54: legacy allow denies uncertainty in compounds and substitutions" {
  local provider command
  configure_policy allow
  for provider in claude codex; do
    for command in 'pwd && npx some-package' 'npx some-package; pwd' \
      'pwd | npx some-package' 'pwd || npx some-package' \
      'echo $(npx some-package)' 'echo `npx some-package`' \
      'echo $(pwd | npx some-package)' 'cat <(npx some-package)'; do
      run_payload "$(payload "$provider" Bash "$command")" 1
      assert_decision deny
    done
  done
}

@test "AGE-54: missing default and invalid uncertainty policies deny on both hosts" {
  local provider setting
  for provider in claude codex; do
    for setting in missing deny invalid ''; do
      configure_policy "$setting" true
      safe_response
      run_payload "$(payload "$provider" Bash 'npx some-package')" 1
      assert_decision deny
      [ ! -e "$GL_TEST_ROOT/curl.log" ]
    done
  done
}

@test "AGE-54: legacy allow never invokes an enabled approving AI" {
  local provider
  configure_policy allow true
  safe_response
  for provider in claude codex; do
    run_payload "$(payload "$provider" Bash 'npx some-package')" 1
    assert_decision deny
    [ ! -e "$GL_TEST_ROOT/curl.log" ]
  done
}

@test "AGE-54: deterministic approvals and custom configuration retain precedence" {
  local provider command
  configure_policy allow true
  printf 'custom_allow: trusted-local-tool\ncustom_pass: blocked-local-tool\n' >> "$GL_CONFIG"
  for provider in claude codex; do
    for command in pwd 'story list' 'python3 --version' 'trusted-local-tool --inspect'; do
      run_payload "$(payload "$provider" Bash "$command")" 1
      if [[ "$provider" == claude ]]; then assert_decision allow; else assert_neutral; fi
      [ ! -e "$GL_TEST_ROOT/curl.log" ]
    done
    run_payload "$(payload "$provider" Bash blocked-local-tool)" 1
    assert_decision deny
    [[ "$output" == *'destructive/privileged'* ]]
  done
}

@test "AGE-54: AI opt-in still evaluates uncertain commands on both hosts" {
  local provider
  configure_policy ai true
  safe_response
  for provider in claude codex; do
    : > "$GL_TEST_ROOT/curl.log"
    run_payload "$(payload "$provider" Bash 'unknown-readonly-tool --inspect')" 1
    if [[ "$provider" == claude ]]; then assert_decision allow; else assert_neutral; fi
    [ -s "$GL_TEST_ROOT/curl.log" ]
    grep -F 'AI_RESULT] answer=false' "$GL_TEST_ROOT/decisions.log"
  done
}

@test "AGE-54: known destructive verbs never reach an otherwise approving AI" {
  local provider command
  configure_policy ai true
  safe_response
  for provider in claude codex; do
    # Positive control: uncertainty really reaches the evaluator in this fixture.
    run_payload "$(payload "$provider" Bash 'unknown-readonly-tool --inspect')" 1
    [ -s "$GL_TEST_ROOT/curl.log" ]
    for command in 'rm fixture' 'story purge ST-1 --force' 'story update --force' \
      'story project delete --force' 'story plugin install package' \
      'story plugin uninstall package' 'echo $(story purge ST-1 --force)'; do
      : > "$GL_TEST_ROOT/curl.log"
      run_payload "$(payload "$provider" Bash "$command")" 1
      assert_decision deny
      [[ "$output" == *'destructive/privileged'* ]]
      [ ! -s "$GL_TEST_ROOT/curl.log" ]
    done
  done
}

@test "AGE-54: disabled or failed AI cannot approve explorer uncertainty" {
  local provider enabled
  for provider in claude codex; do
    for enabled in false true; do
      configure_policy ai "$enabled"
      printf '{' > "$GL_TEST_ROOT/response.json"
      run_payload "$(payload "$provider" Bash 'unknown-readonly-tool --inspect')" 1
      assert_decision deny
      [[ "$output" == *'could not confirm'* ]]
    done
  done
}

@test "AGE-54: legacy setting is inert outside explorer mode" {
  local provider
  configure_policy allow
  for provider in claude codex; do
    run_payload "$(payload "$provider" Bash 'npx some-package')"
    assert_neutral
    [ -z "$output" ]
  done
}
