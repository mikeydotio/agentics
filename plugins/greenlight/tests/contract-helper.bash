# Production hook fixtures; only external HTTP is stubbed.
GL_HOOK="$BATS_TEST_DIRNAME/../hooks/greenlight.sh"
GL_PLUGIN_ROOT="$BATS_TEST_DIRNAME/.."

setup() {
  GL_TEST_ROOT="$(mktemp -d /tmp/age103-greenlight.XXXXXX)"
  mkdir -p "$GL_TEST_ROOT/.config/greenlight" "$GL_TEST_ROOT/bin"
  GL_CONFIG="$GL_TEST_ROOT/.config/greenlight/config.yaml"
  printf 'ai_enabled: false\nai_show_rationale: false\nlog_file: %s/decisions.log\n' \
    "$GL_TEST_ROOT" > "$GL_CONFIG"
  # A sentinel credential and isolated environment guarantee no real request.
  cat > "$GL_TEST_ROOT/bin/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$GL_CURL_LOG"
if [[ "$*" != *'x-api-key: age103-test-sentinel'* ]]; then exit 90; fi
cat "$GL_RESPONSE_FILE"
EOF
  chmod +x "$GL_TEST_ROOT/bin/curl"
}

teardown() {
  rm -rf "$GL_TEST_ROOT"
}

payload() {
  jq -cn --arg provider "$1" --arg tool "$2" --arg command "$3" \
    --arg cwd "$GL_TEST_ROOT" \
    '{hook_event_name:"PreToolUse",tool_name:$tool,tool_input:{command:$command},
      permission_mode:"default",cwd:$cwd}
     + (if $provider == "codex" then {turn_id:"test-turn"} else {} end)'
}

run_payload() {
  run env -i HOME="$GL_TEST_ROOT" PATH="$GL_TEST_ROOT/bin:$PATH" \
    CLAUDE_PLUGIN_ROOT="$GL_PLUGIN_ROOT" GREENLIGHT_PLAN_EXPLORER="${2:-0}" \
    ANTHROPIC_API_KEY=age103-test-sentinel \
    GL_CURL_LOG="$GL_TEST_ROOT/curl.log" GL_RESPONSE_FILE="$GL_TEST_ROOT/response.json" \
    bash "$GL_HOOK" <<< "$1"
}

assert_neutral() {
  [ "${status:?bats run must precede assertions}" -eq 0 ]
  [ -z "$output" ] || jq -e '
    (.hookSpecificOutput // {}) |
    (has("permissionDecision") | not) and (has("permissionDecisionReason") | not)
  ' <<< "$output"
}

assert_decision() {
  [ "${status:?bats run must precede assertions}" -eq 0 ]
  jq -e --arg expected "$1" '
    .hookSpecificOutput.permissionDecision == $expected and
    (.hookSpecificOutput.permissionDecisionReason | length > 0)
  ' <<< "$output"
}

assert_context() {
  jq -e --arg text "$1" '.hookSpecificOutput.additionalContext | contains($text)' <<< "$output"
}

run_safe_ai() {
  printf 'ai_enabled: true\nai_show_rationale: %s\nlog_file: %s/decisions.log\n' \
    "$2" "$GL_TEST_ROOT" > "$GL_CONFIG"
  jq -cn '{content:[{type:"text",text:({answer:false,rationale:"Fixture confirms read-only behavior."}|tojson)}]}' \
    > "$GL_TEST_ROOT/response.json"
  run_payload "$(payload "$1" Bash 'unknown-readonly-tool --inspect')"
  [ -s "$GL_TEST_ROOT/curl.log" ]
  # Neutral output alone could hide a failed AI parse; prove false reached the
  # production AI decision branch instead of falling through as an API failure.
  grep -F 'AI_RESULT] answer=false rationale=Fixture confirms read-only behavior.' \
    "$GL_TEST_ROOT/decisions.log"
}

