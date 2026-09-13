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
  # Plan-explorer fixtures live outside $TMPDIR (see mk_fixture) to keep git
  # repos off Spotlight's index; clean them here.
  [ -n "${XROOT:-}" ] && rm -rf "$XROOT"
  return 0
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

# ─── Plan-explorer fixtures & drivers ────────────────────────────────────
#
# The plan-explorer policy keys off a real git branch + worktree layout, so
# these helpers build an actual repo with a `main` branch and a scratch
# worktree on a `greenlight/scratch-*` branch under `.claude/worktrees/`.
# Fixtures live under /tmp (NOT $TMPDIR) so a burst of small git repos never
# backs up Spotlight's mds_stores. Sets globals REPO and WT; teardown removes
# XROOT.
mk_fixture() {
  XROOT="$(mktemp -d /tmp/glx.XXXXXX)"
  REPO="$XROOT/repo"
  git init -q -b main "$REPO" 2>/dev/null || { mkdir -p "$REPO"; git init -q "$REPO"; git -C "$REPO" symbolic-ref HEAD refs/heads/main; }
  git -C "$REPO" config user.email t@t.io
  git -C "$REPO" config user.name tester
  ( cd "$REPO" && printf 'x\n' > tracked.txt && git add tracked.txt && git commit -qm init )
  mkdir -p "$REPO/.claude/worktrees"
  WT="$REPO/.claude/worktrees/greenlight-scratch-t"
  git -C "$REPO" worktree add -q -b greenlight/scratch-t "$WT" HEAD
}

# Edit/Write/NotebookEdit: single file_path. $1 file_path, $2 cwd, $3 tool, $4 explorer(1/0)
run_edit_x() {
  local fp="$1" cwd="$2" tool="${3:-Edit}" exp="${4:-1}"
  local json envargs=()
  json="$(jq -cn --arg fp "$fp" --arg cwd "$cwd" --arg t "$tool" \
    '{tool_name:$t, tool_input:{file_path:$fp}, permission_mode:"dontAsk", cwd:$cwd}')"
  [ "$exp" = "1" ] && envargs=(GREENLIGHT_PLAN_EXPLORER=1)
  run env HOME="$TEST_HOME" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "${envargs[@]}" bash "$HOOK" <<< "$json"
}

# MultiEdit: single file_path + edits[]. $1 file_path, $2 cwd
run_multiedit_x() {
  local fp="$1" cwd="$2"
  local json
  json="$(jq -cn --arg fp "$fp" --arg cwd "$cwd" \
    '{tool_name:"MultiEdit", tool_input:{file_path:$fp, edits:[{old_string:"a",new_string:"b"}]}, permission_mode:"dontAsk", cwd:$cwd}')"
  run env HOME="$TEST_HOME" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" GREENLIGHT_PLAN_EXPLORER=1 bash "$HOOK" <<< "$json"
}

# Bash as explorer: $1 command, $2 cwd
run_bash_x() {
  local cmd="$1" cwd="$2"
  local json
  json="$(jq -cn --arg c "$cmd" --arg cwd "$cwd" \
    '{tool_name:"Bash", tool_input:{command:$c}, permission_mode:"dontAsk", cwd:$cwd}')"
  run env HOME="$TEST_HOME" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" GREENLIGHT_PLAN_EXPLORER=1 bash "$HOOK" <<< "$json"
}

# Arbitrary non-enumerated tool as explorer: $1 tool_name, $2 cwd
run_tool_x() {
  local tool="$1" cwd="$2"
  local json
  json="$(jq -cn --arg t "$tool" --arg cwd "$cwd" \
    '{tool_name:$t, tool_input:{}, permission_mode:"dontAsk", cwd:$cwd}')"
  run env HOME="$TEST_HOME" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" GREENLIGHT_PLAN_EXPLORER=1 bash "$HOOK" <<< "$json"
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

# ─── Plan-explorer policy (GREENLIGHT_PLAN_EXPLORER=1) ────────────────────
#
# Active ONLY when the env var is set. A spawned `claude -p` explorer runs in
# dontAsk mode where the hook is the sole arbiter: it ALLOWs exploration and
# edits inside a disposable scratch worktree, and DENYs (with guidance) edits
# to the real tree, destructive commands, and uncertain commands.

reason() { echo "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null; }

# --- Edit-family: path fitness ---

@test "explorer: editing a tracked file off-scratch is DENIED" {
  mk_fixture
  run_edit_x "$REPO/tracked.txt" "$REPO"
  [ "$(decision)" = "deny" ]
  [ -n "$(reason)" ]
}

@test "explorer: creating a new untracked file in the repo tree off-scratch is DENIED" {
  mk_fixture
  run_edit_x "$REPO/brand-new.txt" "$REPO" "Write"
  [ "$(decision)" = "deny" ]
}

@test "explorer: editing a file INSIDE the scratch worktree is ALLOWED" {
  mk_fixture
  run_edit_x "$WT/tracked.txt" "$WT"
  [ "$(decision)" = "allow" ]
}

@test "explorer: writing a brand-new file inside the scratch worktree is ALLOWED" {
  mk_fixture
  run_edit_x "$WT/scratch-notes.md" "$WT" "Write"
  [ "$(decision)" = "allow" ]
}

@test "explorer: writing under /tmp is ALLOWED (outside any repo tree)" {
  mk_fixture
  run_edit_x "/tmp/gl-explorer-out.txt" "$REPO" "Write"
  [ "$(decision)" = "allow" ]
}

@test "explorer: an absolute path escaping the worktree into the main tree is DENIED" {
  mk_fixture
  # cwd is the scratch worktree, but the target points back into the real repo
  run_edit_x "$REPO/tracked.txt" "$WT"
  [ "$(decision)" = "deny" ]
}

@test "explorer: a symlink inside the worktree resolving to the main tree is DENIED" {
  mk_fixture
  ln -s "$REPO/tracked.txt" "$WT/link-to-real.txt"
  run_edit_x "$WT/link-to-real.txt" "$WT"
  [ "$(decision)" = "deny" ]
}

@test "explorer: MultiEdit inside the worktree is ALLOWED, in the main tree is DENIED" {
  mk_fixture
  run_multiedit_x "$WT/tracked.txt" "$WT"
  [ "$(decision)" = "allow" ]
  run_multiedit_x "$REPO/tracked.txt" "$REPO"
  [ "$(decision)" = "deny" ]
}

@test "explorer: NotebookEdit inside the worktree is ALLOWED" {
  mk_fixture
  run_edit_x "$WT/nb.ipynb" "$WT" "NotebookEdit"
  [ "$(decision)" = "allow" ]
}

@test "explorer: a relative file_path resolves against cwd (worktree) and is ALLOWED" {
  mk_fixture
  run_edit_x "tracked.txt" "$WT"
  [ "$(decision)" = "allow" ]
}

@test "explorer: a relative file_path in the main tree cwd is DENIED" {
  mk_fixture
  run_edit_x "tracked.txt" "$REPO"
  [ "$(decision)" = "deny" ]
}

# --- Bash: exploration vs mutation ---

@test "explorer: readonly bash is ALLOWED" {
  mk_fixture
  run_bash_x "ls -la" "$REPO"
  [ "$(decision)" = "allow" ]
  run_bash_x "git status" "$WT"
  [ "$(decision)" = "allow" ]
}

@test "explorer: a destructive command is DENIED even inside the worktree" {
  mk_fixture
  run_bash_x "rm -rf build" "$WT"
  [ "$(decision)" = "deny" ]
  [ -n "$(reason)" ]
}

@test "explorer: git push is DENIED" {
  mk_fixture
  run_bash_x "git push origin main" "$WT"
  [ "$(decision)" = "deny" ]
}

@test "explorer: an uncertain command is DENIED by default" {
  mk_fixture
  run_bash_x "npx some-random-tool" "$WT"
  [ "$(decision)" = "deny" ]
}

@test "explorer: safe build/test commands are ALLOWED even off-scratch (write only build artifacts)" {
  mk_fixture
  run_bash_x "cargo build" "$REPO"
  [ "$(decision)" = "allow" ]
  run_bash_x "make test" "$REPO"
  [ "$(decision)" = "allow" ]
}

@test "explorer: shell redirection to a target inside the worktree is ALLOWED" {
  mk_fixture
  run_bash_x "echo hello > out.txt" "$WT"
  [ "$(decision)" = "allow" ]
}

@test "explorer: shell redirection to a tracked file in the main tree is DENIED" {
  mk_fixture
  run_bash_x "echo pwned > tracked.txt" "$REPO"
  [ "$(decision)" = "deny" ]
}

@test "explorer: shell redirection to /tmp is ALLOWED" {
  mk_fixture
  run_bash_x "echo hi > /tmp/gl-redir-out.txt" "$REPO"
  [ "$(decision)" = "allow" ]
}

# --- Other tools & readonly ---

@test "explorer: Read is ALLOWED" {
  mk_fixture
  run_tool_x "Read" "$WT"
  [ "$(decision)" = "allow" ]
}

@test "explorer: a non-enumerated tool defers (no decision; dontAsk then denies)" {
  mk_fixture
  run_tool_x "SomeFutureTool" "$WT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- Config knobs ---

@test "AGE-54: explorer legacy allow denies uncertain commands with migration guidance" {
  mk_fixture
  set_config plan_explorer_uncertain allow
  run_bash_x "npx some-random-tool" "$WT"
  [ "$(decision)" = "deny" ]
  [[ "$output" == *'plan_explorer_uncertain: allow'* ]]
}

@test "explorer: plan_explorer_enabled=false disables the policy entirely" {
  mk_fixture
  set_config plan_explorer_enabled false
  run_edit_x "$REPO/tracked.txt" "$REPO"
  # policy off → Edit falls through to normal (silent) handling
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- Non-regression: absent the env var, behavior is unchanged ---

@test "non-regression: without the explorer env var, Edit passes through silently" {
  mk_fixture
  run_edit_x "$REPO/tracked.txt" "$REPO" "Edit" 0
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "non-regression: without the explorer env var, rm -rf still warns via context (no deny)" {
  run_bash "rm -rf important_dir"
  [ "$(decision)" != "deny" ]
  has_context
}
