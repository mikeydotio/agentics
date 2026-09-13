#!/usr/bin/env bats
# Tests for greenlight-explore.sh — the plan-explorer launcher.
#
# Mock-free w.r.t. git (real repos + worktrees), but the `claude -p` call is
# stubbed by a fake `claude` on PATH that records its invocation (cwd, the
# GREENLIGHT_PLAN_EXPLORER tag, and args) and prints canned findings. Fixtures
# live under /tmp (not $TMPDIR) to keep git repos off Spotlight's index.

BIN="$BATS_TEST_DIRNAME/../bin/greenlight-explore.sh"

setup() {
  XROOT="$(mktemp -d /tmp/glx-run.XXXXXX)"
  REPO="$XROOT/repo"
  git init -q -b main "$REPO" 2>/dev/null || { mkdir -p "$REPO"; git init -q "$REPO"; git -C "$REPO" symbolic-ref HEAD refs/heads/main; }
  git -C "$REPO" config user.email t@t.io
  git -C "$REPO" config user.name tester
  ( cd "$REPO" && printf 'x\n' > f.txt && git add f.txt && git commit -qm init )

  STUB="$XROOT/bin"; mkdir -p "$STUB"
  export GL_STUB_LOG="$XROOT/claude.log"
  cat > "$STUB/claude" <<'EOF'
#!/usr/bin/env bash
{ echo "CWD=$PWD"; echo "EXPLORER=${GREENLIGHT_PLAN_EXPLORER:-}"; echo "ARGS=$*"; } >> "$GL_STUB_LOG"
printf '## Findings\nAll good.\n'
exit "${GL_STUB_RC:-0}"
EOF
  chmod +x "$STUB/claude"

  export TEST_HOME="$XROOT/home"; mkdir -p "$TEST_HOME"
  JQ_DIR="$(dirname "$(command -v jq)")"
}

teardown() {
  [ -n "${XROOT:-}" ] && rm -rf "$XROOT"
  return 0
}

# Run the launcher with the stub on PATH and an isolated HOME.
run_explore() {
  run env HOME="$TEST_HOME" GL_STUB_LOG="$GL_STUB_LOG" PATH="$STUB:$PATH" bash "$BIN" "$@"
}
j() { echo "$output" | jq -r "$1" 2>/dev/null; }

@test "run creates a scratch worktree, runs the explorer there with the tag, tears it down" {
  run_explore run --task "map the widget" --repo "$REPO"
  [ "$status" -eq 0 ]
  [ "$(j '.ok')" = "true" ]
  local fp; fp="$(j '.findings')"
  [ -f "$fp" ]
  grep -q "All good" "$fp"
  grep -q "EXPLORER=1" "$GL_STUB_LOG"
  grep -q -- "--permission-mode dontAsk" "$GL_STUB_LOG"
  grep -q "greenlight-scratch" "$GL_STUB_LOG"
  ! git -C "$REPO" worktree list | grep -q greenlight-scratch
  ! git -C "$REPO" branch --list 'greenlight/scratch-*' | grep -q .
}

@test "run --keep leaves the worktree and branch in place" {
  run_explore run --task "keep me" --repo "$REPO" --keep
  [ "$status" -eq 0 ]
  [ "$(j '.kept')" = "true" ]
  git -C "$REPO" worktree list | grep -q greenlight-scratch
  git -C "$REPO" branch --list 'greenlight/scratch-*' | grep -q .
}

@test "run --out writes findings to the given path and reports it" {
  local out="$XROOT/findings.md"
  run_explore run --task "x" --repo "$REPO" --out "$out"
  [ "$status" -eq 0 ]
  [ -f "$out" ]
  grep -q "All good" "$out"
  [ "$(j '.findings')" = "$out" ]
}

@test "run --model overrides the model passed to the explorer" {
  run_explore run --task "x" --repo "$REPO" --model claude-opus-4-8
  grep -q -- "--model claude-opus-4-8" "$GL_STUB_LOG"
  [ "$(j '.model')" = "claude-opus-4-8" ]
}

@test "the default model is sonnet" {
  run_explore run --task "x" --repo "$REPO"
  grep -q -- "--model claude-sonnet-5" "$GL_STUB_LOG"
}

@test "missing --task is a usage error (nonzero exit)" {
  run_explore run --repo "$REPO"
  [ "$status" -ne 0 ]
}

@test "a nonzero explorer exit still tears down and reports ok=false" {
  run env HOME="$TEST_HOME" GL_STUB_LOG="$GL_STUB_LOG" GL_STUB_RC=3 PATH="$STUB:$PATH" bash "$BIN" run --task "x" --repo "$REPO"
  [ "$(echo "$output" | jq -r '.ok')" = "false" ]
  ! git -C "$REPO" worktree list | grep -q greenlight-scratch
}

@test "the scratch branch carries the greenlight/scratch- prefix" {
  run_explore run --task "x" --repo "$REPO" --keep
  git -C "$REPO" branch --list 'greenlight/scratch-*' | grep -q 'greenlight/scratch-'
}

@test "missing claude CLI reports ok=false (no crash)" {
  run env HOME="$TEST_HOME" PATH="$JQ_DIR:/usr/bin:/bin" bash "$BIN" run --task "x" --repo "$REPO"
  [ "$(echo "$output" | jq -r '.ok // false')" = "false" ]
}

@test "run outside a git repo without --repo reports ok=false" {
  run env HOME="$TEST_HOME" PATH="$STUB:$PATH" bash "$BIN" run --task "x" --repo "$XROOT/not-a-repo"
  [ "$(echo "$output" | jq -r '.ok // false')" = "false" ]
}

@test "stdout is a single clean JSON object (findings do not leak to stdout)" {
  run_explore run --task "x" --repo "$REPO"
  echo "$output" | jq -e . >/dev/null
  # the canned findings text must NOT appear on the launcher's stdout
  ! echo "$output" | grep -q "All good"
}

# A fixture package changes only data; launcher and hook are production source.
prepare_config_package() {
  PACKAGE="$XROOT/plugin package"
  mkdir -p "$PACKAGE"
  cp -R "$BATS_TEST_DIRNAME/../bin" "$BATS_TEST_DIRNAME/../lib" \
    "$BATS_TEST_DIRNAME/../hooks" "$BATS_TEST_DIRNAME/../references" "$PACKAGE/"
  local bundled="$PACKAGE/references/default-config.yaml"
  sed -e 's|^plan_explorer_model:.*|plan_explorer_model: fixture-model|' \
    -e 's|^plan_explorer_scratch_prefix:.*|plan_explorer_scratch_prefix: research/|' \
    -e 's|^plan_explorer_worktree_segment:.*|plan_explorer_worktree_segment: .research/worktrees|' \
    "$bundled" > "$XROOT/defaults"
  mv "$XROOT/defaults" "$bundled"
}

run_package() {
  run env -i HOME="$TEST_HOME" PATH="$STUB:$PATH" GL_STUB_LOG="$GL_STUB_LOG" \
    "$@" bash "$PACKAGE/bin/greenlight-explore.sh" run --task x --repo "$REPO" --out "$XROOT/findings" --keep
}

@test "explorer inherits bundled model and scratch identity recognized by the real hook" {
  prepare_config_package
  run_package
  [ "$status" -eq 0 ]
  [ "$(j '.model')" = fixture-model ]
  [[ "$(j '.branch')" == research/* ]]
  local wt data
  wt="$(j '.worktree')"
  [[ "$wt" == "$REPO/.research/worktrees/"* ]]
  grep -F -- '--model fixture-model' "$GL_STUB_LOG"
  data="$(jq -cn --arg cwd "$wt" --arg file "$wt/f.txt" \
    '{tool_name:"Edit",tool_input:{file_path:$file},cwd:$cwd,permission_mode:"dontAsk"}')"
  run env -i HOME="$TEST_HOME" PATH="$PATH" PLUGIN_ROOT="$PACKAGE" GREENLIGHT_PLAN_EXPLORER=1 \
    bash "$PACKAGE/hooks/greenlight.sh" <<< "$data"
  [ "$status" -eq 0 ]
  jq -e '.hookSpecificOutput.permissionDecision == "allow"' <<< "$output"
  [ ! -e "$TEST_HOME/.config" ]
}

@test "explorer user pins and CLI model override bundled values" {
  prepare_config_package
  mkdir -p "$TEST_HOME/.config/greenlight"
  printf 'plan_explorer_model: user-model\nplan_explorer_scratch_prefix: user/\nplan_explorer_worktree_segment: .user/worktrees\n' > "$TEST_HOME/.config/greenlight/config.yaml"
  run_package
  [ "$status" -eq 0 ]
  [ "$(j '.model')" = user-model ]
  [[ "$(j '.branch')" == user/* ]]
  [[ "$(j '.worktree')" == "$REPO/.user/worktrees/"* ]]
  run env -i HOME="$TEST_HOME" PATH="$STUB:$PATH" GL_STUB_LOG="$GL_STUB_LOG" \
    bash "$PACKAGE/bin/greenlight-explore.sh" run --task x --repo "$REPO" --model cli-model --out "$XROOT/cli-findings"
  [ "$status" -eq 0 ]
  [ "$(j '.model')" = cli-model ]
}

@test "explorer root variables select the same bundled precedence as the hook" {
  prepare_config_package
  local production_root
  production_root="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  run_package PLUGIN_ROOT="$PACKAGE" CLAUDE_PLUGIN_ROOT="$production_root"
  [ "$status" -eq 0 ]
  [ "$(j '.model')" = fixture-model ]
  run_package PLUGIN_ROOT= CLAUDE_PLUGIN_ROOT="$PACKAGE"
  [ "$status" -eq 0 ]
  [ "$(j '.model')" = fixture-model ]
  run_package PLUGIN_ROOT="$production_root" CLAUDE_PLUGIN_ROOT="$PACKAGE"
  [ "$status" -eq 0 ]
  [ "$(j '.model')" = claude-sonnet-5 ]
}

@test "explorer refuses invalid configuration before creating worktrees or running Claude" {
  prepare_config_package
  mkdir -p "$TEST_HOME/.config/greenlight"
  printf 'ai_enabled: invalid\n' > "$TEST_HOME/.config/greenlight/config.yaml"
  run_package
  [ "$status" -eq 1 ]
  [[ "$output" == *'greenlight config:'* ]]
  [[ "$output" == *'"ok": false'* ]]
  [ ! -e "$GL_STUB_LOG" ]
  [ ! -e "$REPO/.research" ]
  [ "$(git -C "$REPO" worktree list --porcelain | sed -n '/^worktree /p' | wc -l | tr -d ' ')" -eq 1 ]
  rm "$TEST_HOME/.config/greenlight/config.yaml" "$PACKAGE/references/default-config.yaml"
  run_package
  [ "$status" -eq 1 ]
  [[ "$output" == *'greenlight config:'* ]]
  [ ! -e "$GL_STUB_LOG" ]
}
