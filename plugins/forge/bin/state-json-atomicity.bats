#!/usr/bin/env bats
# Structural regression guard for the agentics#33 design doc's shipping
# prerequisite: every script that writes .forge/state.json must use the
# temp-file+rename idiom (write to a `.tmp` sibling, then `mv` into place)
# rather than a direct redirect, so a concurrent reader (forge-state.sh,
# forge-status.sh, the session-start hook) can never observe a partially-
# written file mid-write.
#
# Verified true for every real writer as of this change (forge-step-exit.sh,
# forge-loop-state.sh's write_state(), hooks/session-stop.sh — all already
# used the `> "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"`
# idiom before agentics#33 touched anything). This file is a regression
# guard, not a fix: it exists so a future writer can't silently reintroduce
# a direct, non-atomic write.
#
# forge-fix-archive.sh is deliberately NOT covered here even though an
# earlier draft of the agentics#33 design doc described it as a "state.json
# writer" mid-fix_loop-transition -- that's inaccurate. forge-fix-archive.sh
# never touches .forge/state.json at all; it only moves TRIAGE.md/PLAN.md/
# plan-mapping.json into fix-cycles/cycle-N/. The pipeline's `state` string
# (interrogate/fix_loop/design/...) is never persisted anywhere -- it's
# derived live, on every forge-state.sh invocation, purely from artifact
# file presence + a storyhook query. The last test below documents this.

FORGE_BIN_DIR="$BATS_TEST_DIRNAME"
FORGE_HOOKS_DIR="$(cd "$BATS_TEST_DIRNAME/../hooks" && pwd)"

@test "forge-step-exit.sh writes state.json via temp-file+rename, never a direct redirect" {
  run grep -nE '>\s*"[^"]*state\.json"' "$FORGE_BIN_DIR/forge-step-exit.sh"
  [ "$status" -ne 0 ]
  run grep -c '${STATE_FILE}\.tmp' "$FORGE_BIN_DIR/forge-step-exit.sh"
  [ "$output" -ge 1 ]
}

@test "forge-loop-state.sh's write_state() writes via temp-file+rename, never a direct redirect" {
  run grep -nE '>\s*"[^"]*state\.json"' "$FORGE_BIN_DIR/forge-loop-state.sh"
  [ "$status" -ne 0 ]
  run grep -c '${STATE_FILE}\.tmp' "$FORGE_BIN_DIR/forge-loop-state.sh"
  [ "$output" -ge 1 ]
}

@test "hooks/session-stop.sh writes state.json via temp-file+rename, never a direct redirect" {
  run grep -nE '>\s*"[^"]*state\.json"' "$FORGE_HOOKS_DIR/session-stop.sh"
  [ "$status" -ne 0 ]
  run grep -c '${STATE_FILE}\.tmp' "$FORGE_HOOKS_DIR/session-stop.sh"
  [ "$output" -ge 1 ]
}

@test "forge-fix-archive.sh does not write .forge/state.json at all" {
  run grep -c 'state\.json' "$FORGE_BIN_DIR/forge-fix-archive.sh"
  [ "$output" -eq 0 ]
}
