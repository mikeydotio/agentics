#!/usr/bin/env bats
# Tests for greenlight.sh — the PreToolUse safety hook (F080: this plugin
# had zero test coverage before this suite).
#
# Mock-free: drives the real hook script end to end via stdin JSON, exactly
# as Claude Code would invoke it. Each test gets a throwaway $HOME so the
# hook's config auto-init (~/.config/greenlight/config.yaml, copied from
# the plugin's bundled default-config.yaml on first run) never touches the
# real user's config.

HOOK="$BATS_TEST_DIRNAME/../hooks/greenlight.sh"
PLUGIN_ROOT="$BATS_TEST_DIRNAME/.."

setup() {
  TEST_HOME="$(mktemp -d)"
  export TEST_HOME
}

teardown() {
  rm -rf "$TEST_HOME"
}

# Feed a Bash tool_use through the hook.
#
# IMPORTANT: build the JSON payload with `jq -n` (never string-interpolate
# the raw command into a heredoc/bash -c string) — several test commands
# below deliberately contain their own `$(...)`, and an UNQUOTED heredoc
# delimiter (`<<JSON`, no quotes) re-expands command substitutions found in
# its body. An earlier draft of this helper did exactly that and silently
# *executed* a test's `rm -rf` payload instead of just describing it to the
# hook. `jq -n --arg` never re-parses its output as shell, and a here-string
# (`<<<`) with an already-fully-resolved, double-quoted variable is not
# subject to that re-expansion the way an unquoted heredoc body is.
run_bash() {
  local command="$1" perm_mode="${2:-default}"
  local json
  json="$(jq -cn --arg cmd "$command" --arg mode "$perm_mode" \
    '{tool_name: "Bash", tool_input: {command: $cmd}, permission_mode: $mode}')"
  run env HOME="$TEST_HOME" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$HOOK" <<< "$json"
}

run_tool() {
  local tool_name="$1"
  local json
  json="$(jq -cn --arg name "$tool_name" \
    '{tool_name: $name, tool_input: {}, permission_mode: "default"}')"
  run env HOME="$TEST_HOME" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$HOOK" <<< "$json"
}

decision() {
  echo "$output" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null
}

has_context() {
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext // empty' >/dev/null 2>&1
}

set_config() {
  local key="$1" value="$2"
  mkdir -p "$TEST_HOME/.config/greenlight"
  [ -f "$TEST_HOME/.config/greenlight/config.yaml" ] || cp "$PLUGIN_ROOT/references/default-config.yaml" "$TEST_HOME/.config/greenlight/config.yaml"
  local tmp
  tmp=$(mktemp)
  sed "s/^${key}:.*/${key}: ${value}/" "$TEST_HOME/.config/greenlight/config.yaml" > "$tmp" && mv "$tmp" "$TEST_HOME/.config/greenlight/config.yaml"
}

# --- Config auto-init ---

@test "auto-initializes config from the bundled default on first run" {
  [ ! -f "$TEST_HOME/.config/greenlight/config.yaml" ]
  run_bash "ls"
  [ -f "$TEST_HOME/.config/greenlight/config.yaml" ]
}

@test "F077/F078: ai_enabled defaults to false in the auto-initialized config" {
  run_bash "ls"
  grep -qE '^ai_enabled:\s*false' "$TEST_HOME/.config/greenlight/config.yaml"
}

@test "F082: ai_show_rationale defaults to false in the auto-initialized config" {
  run_bash "ls"
  grep -qE '^ai_show_rationale:\s*false' "$TEST_HOME/.config/greenlight/config.yaml"
}

@test "F078: the default ai_model is a structured-outputs-capable model" {
  run_bash "ls"
  grep -qE '^ai_model:\s*claude-haiku-4-5' "$TEST_HOME/.config/greenlight/config.yaml"
}

# --- Non-Bash tools ---

@test "readonly tools (Read, Glob, Grep) are always allowed" {
  run_tool "Read"
  [ "$(decision)" = "allow" ]
}

@test "a non-Bash, non-readonly tool passes through silently (no decision)" {
  run_tool "Write"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- Deterministic ALLOW ---

@test "known-safe readonly commands are allowed" {
  run_bash "ls -la"
  [ "$(decision)" = "allow" ]
}

@test "jq/grep pipelines are allowed" {
  run_bash "cat file.json | jq '.foo' | grep bar"
  [ "$(decision)" = "allow" ]
}

@test "git status/log/diff are allowed" {
  run_bash "git status"
  [ "$(decision)" = "allow" ]
  run_bash "git log --oneline"
  [ "$(decision)" = "allow" ]
  run_bash "git diff HEAD~1"
  [ "$(decision)" = "allow" ]
}

@test "git branch -D (delete) is NOT allowed (falls to uncertain)" {
  run_bash "git branch -D some-branch"
  [ "$(decision)" != "allow" ]
}

# --- Deterministic PASS (known destructive) ---

@test "rm -rf surfaces a destructive warning, never auto-allowed" {
  run_bash "rm -rf important_dir"
  [ "$(decision)" != "allow" ]
  has_context
  [[ "$output" == *"file deletion"* ]]
}

@test "sudo surfaces a privilege-escalation warning" {
  run_bash "sudo apt-get install foo"
  has_context
  [[ "$output" == *"privilege escalation"* ]]
}

# --- Permission mode gating ---

@test "bypassPermissions mode disables all evaluation (no output even for rm -rf)" {
  run_bash "rm -rf /" "bypassPermissions"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "default mode still evaluates and warns on rm -rf" {
  run_bash "rm -rf important_dir" "default"
  has_context
}

# --- F075: quoted `>` / `->` must not false-positive as redirection ---

@test "F075: a quoted '>' inside the command string is not treated as redirection" {
  run_bash 'echo "a > b"'
  [ "$(decision)" = "allow" ]
}

@test "F075: a quoted '->' inside the command string is not treated as redirection" {
  run_bash 'echo "a -> b"'
  [ "$(decision)" = "allow" ]
}

@test "F075: forge-style commit message arrows do not defer" {
  run_bash 'git commit -m "refactor: rename A -> B"'
  [ "$(decision)" = "allow" ]
}

@test "F075: grep pattern containing '>' inside quotes is not treated as redirection" {
  run_bash 'grep -q "x>y" file.txt'
  [ "$(decision)" = "allow" ]
}

@test "F075: a REAL unquoted redirection is still detected and deferred" {
  run_bash "echo hello > /tmp/somefile.txt"
  [ "$(decision)" != "allow" ]
}

@test "F075: story comment with an arrow in the free-text argument is allowed" {
  run_bash 'story comment ST-1 "map wave -> story"'
  [ "$(decision)" = "allow" ]
}

# --- F076/F077: fast allowlist for forge's inner loop ---

@test "F076/F077: story CLI subcommands are allowed" {
  run_bash "story next --json"
  [ "$(decision)" = "allow" ]
  run_bash "story move ST-1 done"
  [ "$(decision)" = "allow" ]
  run_bash "story comment ST-1 \"some text\""
  [ "$(decision)" = "allow" ]
}

@test "F076/F077: git add/commit/checkout are allowed" {
  run_bash "git add .forge/"
  [ "$(decision)" = "allow" ]
  run_bash "git commit -m 'feat: add thing'"
  [ "$(decision)" = "allow" ]
  run_bash "git checkout ."
  [ "$(decision)" = "allow" ]
}

@test "F076/F077: cargo/npm/go test and build are allowed" {
  run_bash "cargo test"
  [ "$(decision)" = "allow" ]
  run_bash "cargo build"
  [ "$(decision)" = "allow" ]
  run_bash "npm test"
  [ "$(decision)" = "allow" ]
  run_bash "go test ./..."
  [ "$(decision)" = "allow" ]
  run_bash "go build ./..."
  [ "$(decision)" = "allow" ]
}

@test "F076/F077: make test is allowed, but an arbitrary make target is not" {
  run_bash "make test"
  [ "$(decision)" = "allow" ]
  run_bash "make test-forge"
  [ "$(decision)" = "allow" ]
  run_bash "make deploy-to-prod"
  [ "$(decision)" != "allow" ]
}

# --- F081: destructive command inside command substitution ---

@test "F081: a destructive command nested in \$(...) is classified as destructive, not merely uncertain" {
  run_bash 'echo $(rm -rf /tmp/foo)'
  [ "$(decision)" != "allow" ]
  has_context
  [[ "$output" == *"file deletion"* ]]
}

@test "a safe command nested in \$(...) is still allowed" {
  run_bash 'echo $(git status)'
  [ "$(decision)" = "allow" ]
}

# --- Uncertain commands: mode behavior ---

@test "strict mode defers uncertain commands silently (no AI, no context)" {
  set_config mode strict
  run_bash "npx some-random-tool"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "standard mode with AI disabled (the default) defers uncertain commands silently, without an API call" {
  # ai_enabled defaults to false -- confirm no curl is even attempted by
  # shimming curl to fail loudly if invoked.
  local shim_dir json
  shim_dir="$(mktemp -d)"
  cat > "$shim_dir/curl" <<'EOF'
#!/usr/bin/env bash
echo "CURL SHOULD NOT HAVE BEEN CALLED" >&2
exit 1
EOF
  chmod +x "$shim_dir/curl"
  json="$(jq -cn '{tool_name: "Bash", tool_input: {command: "npx some-random-tool"}, permission_mode: "default"}')"
  run env PATH="$shim_dir:$PATH" HOME="$TEST_HOME" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$HOOK" <<< "$json"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  rm -rf "$shim_dir"
}

@test "AI fallback with no ANTHROPIC_API_KEY set falls through to silent defer even when explicitly enabled" {
  set_config ai_enabled true
  local json
  json="$(jq -cn '{tool_name: "Bash", tool_input: {command: "npx some-random-tool"}, permission_mode: "default"}')"
  run env -u ANTHROPIC_API_KEY HOME="$TEST_HOME" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$HOOK" <<< "$json"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- Custom allow/pass lists ---

@test "custom_allow forces a command to be allowed regardless of classification" {
  set_config custom_allow "terraform"
  run_bash "terraform apply"
  [ "$(decision)" = "allow" ]
}

@test "custom_pass forces a command to always defer, even if otherwise safe" {
  set_config custom_pass "ls"
  run_bash "ls"
  [ "$(decision)" != "allow" ]
}

# --- Sed/quote edge cases beyond redirection ---

@test "sed without -i is allowed" {
  run_bash "sed 's/foo/bar/' file.txt"
  [ "$(decision)" = "allow" ]
}

@test "sed -i is NOT allowed (in-place edit is uncertain/destructive territory)" {
  run_bash "sed -i 's/foo/bar/' file.txt"
  [ "$(decision)" != "allow" ]
}

# --- Output is always valid JSON when non-empty ---

@test "every non-empty hook output is valid JSON" {
  run_bash "rm -rf x"
  if [ -n "$output" ]; then
    echo "$output" | jq . >/dev/null
  fi
}
