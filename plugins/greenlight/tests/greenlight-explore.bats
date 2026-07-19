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
