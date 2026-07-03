#!/usr/bin/env bats
# Tests for forge-integrity.sh — content-hash integrity snapshot/check
# replacing execution-loop.md's md5sum-of-two-files + `git diff --name-only`
# prose (F029, F058, F064, F091, F092, F096).
#
# Mock-free: drives real git in a throwaway /tmp repo per test (see CLAUDE.md).

SCRIPT="$BATS_TEST_DIRNAME/forge-integrity.sh"

setup() {
  TEST_DIR="$(mktemp -d)"
  FORGE_DIR="$TEST_DIR/.forge"
  mkdir -p "$FORGE_DIR"
  ( cd "$TEST_DIR" && git init -q . && git config user.email t@t.com && git config user.name t )
  echo '{"yolo":false}' > "$FORGE_DIR/config.json"
  echo '{"stories_attempted":0}' > "$FORGE_DIR/state.json"
  ( cd "$TEST_DIR" && git add -A && git commit -q -m "init" )
}

teardown() {
  rm -rf "$TEST_DIR"
  # Clean up this test's project-keyed snapshot dir so a stray leftover from
  # one test run can never leak state into another (paths are content-hashed
  # from $TEST_DIR's absolute path, which mktemp guarantees is unique already,
  # but this keeps /tmp tidy across a full test run).
  rm -rf "/tmp/forge-integrity"
}

run_in_repo() {
  run bash -c "cd '$TEST_DIR' && bash '$SCRIPT' $*"
}

jq_field() {
  echo "$output" | jq -r "$1"
}

# --- Argument validation ---

@test "requires --phase" {
  run_in_repo "snapshot --forge-dir .forge"
  [ "$status" -ne 0 ]
}

@test "rejects an invalid --scope" {
  run_in_repo "snapshot --phase p --forge-dir .forge --scope bogus"
  [ "$status" -ne 0 ]
}

@test "unknown subcommand exits nonzero" {
  run_in_repo "bogus --phase p --forge-dir .forge"
  [ "$status" -ne 0 ]
}

# --- Environment guards ---

@test "not a git repo: ok=false, does not crash" {
  local nogit
  nogit="$(mktemp -d)"
  mkdir -p "$nogit/.forge"
  run bash -c "cd '$nogit' && bash '$SCRIPT' snapshot --phase p --forge-dir .forge"
  [ "$status" -eq 0 ]
  [ "$(jq_field '.ok')" = "false" ]
  [ "$(jq_field '.error')" = "not_a_git_repo" ]
  rm -rf "$nogit"
}

@test "check with no prior snapshot for the phase: ok=false, does not crash" {
  run_in_repo "check --phase never-snapshotted --forge-dir .forge"
  [ "$status" -eq 0 ]
  [ "$(jq_field '.ok')" = "false" ]
  [[ "$(jq_field '.error')" == no_snapshot_for_phase_* ]]
}

# --- snapshot output shape ---

@test "snapshot: reports ok, phase, scope, head, file_count" {
  run_in_repo "snapshot --phase pre-gen --forge-dir .forge"
  [ "$status" -eq 0 ]
  [ "$(jq_field '.ok')" = "true" ]
  [ "$(jq_field '.phase')" = "pre-gen" ]
  [ "$(jq_field '.scope')" = "forge-only" ]
  [ "$(jq_field '.head')" != "" ]
  [ "$(jq_field '.file_count')" = "2" ]
}

@test "snapshot: full-tree scope counts every tracked file, not just the two forge files" {
  echo "code" > "$TEST_DIR/src.js"
  ( cd "$TEST_DIR" && git add -A && git commit -q -m "feat(ST-1): add src" )
  run_in_repo "snapshot --phase pre-eval --forge-dir .forge --scope full-tree"
  [ "$status" -eq 0 ]
  # init + config.json + state.json + src.js == at least 3 tracked files
  # (exact count depends on git init defaults, so just assert it's bigger
  # than the forge-only count)
  [ "$(jq_field '.file_count')" -gt 2 ]
}

# --- forge-only scope: no tampering ---

@test "check: no changes since snapshot reports tampered=false, action=none" {
  run_in_repo "snapshot --phase pre-gen --forge-dir .forge"
  run_in_repo "check --phase pre-gen --forge-dir .forge"
  [ "$status" -eq 0 ]
  [ "$(jq_field '.tampered')" = "false" ]
  [ "$(jq_field '.action')" = "none" ]
  [ "$(jq_field '.changed | length')" = "0" ]
  [ "$(jq_field '.head_moved')" = "false" ]
}

# --- forge-only scope: catches + auto-restores forge-file tampering ---

@test "check: generator corrupting state.json is caught and auto-restored" {
  run_in_repo "snapshot --phase pre-gen --forge-dir .forge"
  echo '{"stories_attempted": 999, "TAMPERED": true}' > "$FORGE_DIR/state.json"
  run_in_repo "check --phase pre-gen --forge-dir .forge"
  [ "$(jq_field '.tampered')" = "true" ]
  [ "$(jq_field '.action')" = "restored" ]
  [ "$(jq_field '.changed[0].file')" = ".forge/state.json" ]
  [ "$(jq_field '.changed[0].status')" = "modified" ]
  [ "$(cat "$FORGE_DIR/state.json")" = '{"stories_attempted":0}' ]
}

@test "check: forge-only scope ignores changes to files outside its scope" {
  run_in_repo "snapshot --phase pre-gen --forge-dir .forge"
  echo "generator work happens here, and that's expected" > "$TEST_DIR/app.js"
  run_in_repo "check --phase pre-gen --forge-dir .forge"
  [ "$(jq_field '.tampered')" = "false" ]
  # the new file must still exist -- forge-only scope must not touch it
  [ -f "$TEST_DIR/app.js" ]
}

# --- full-tree scope: catches the two gaps a filename-set diff misses (F092) ---

@test "check: full-tree scope catches an edit to a file already modified before the snapshot" {
  echo "generator's legitimate first draft" > "$TEST_DIR/src.js"
  ( cd "$TEST_DIR" && git add -A && git commit -q -m "feat(ST-1): add src" )
  echo "generator's second legitimate edit, still pre-eval" > "$TEST_DIR/src.js"
  run_in_repo "snapshot --phase pre-eval --forge-dir .forge --scope full-tree"
  echo "EVALUATOR TAMPERING -- this file was already dirty before the evaluator ran" > "$TEST_DIR/src.js"
  run_in_repo "check --phase pre-eval --forge-dir .forge --scope full-tree"
  [ "$(jq_field '.tampered')" = "true" ]
  [ "$(jq_field '.action')" = "restored" ]
  echo "$output" | jq -e '.changed[] | select(.file == "src.js" and .status == "modified")' >/dev/null
  [ "$(cat "$TEST_DIR/src.js")" = "generator's second legitimate edit, still pre-eval" ]
}

@test "check: full-tree scope catches and removes a brand-new untracked file" {
  run_in_repo "snapshot --phase pre-eval --forge-dir .forge --scope full-tree"
  echo "malicious new file" > "$TEST_DIR/evil.js"
  run_in_repo "check --phase pre-eval --forge-dir .forge --scope full-tree"
  [ "$(jq_field '.tampered')" = "true" ]
  [ "$(jq_field '.action')" = "restored" ]
  echo "$output" | jq -e '.changed[] | select(.file == "evil.js" and .status == "added")' >/dev/null
  [ ! -f "$TEST_DIR/evil.js" ]
}

@test "check: full-tree scope catches a removed tracked file" {
  echo "will be deleted" > "$TEST_DIR/gone.js"
  ( cd "$TEST_DIR" && git add -A && git commit -q -m "feat(ST-1): add gone.js" )
  run_in_repo "snapshot --phase pre-eval --forge-dir .forge --scope full-tree"
  rm -f "$TEST_DIR/gone.js"
  run_in_repo "check --phase pre-eval --forge-dir .forge --scope full-tree"
  [ "$(jq_field '.tampered')" = "true" ]
  [ "$(jq_field '.action')" = "restored" ]
  echo "$output" | jq -e '.changed[] | select(.file == "gone.js" and .status == "removed")' >/dev/null
  [ -f "$TEST_DIR/gone.js" ]
  [ "$(cat "$TEST_DIR/gone.js")" = "will be deleted" ]
}

# --- HEAD moved (F064): never auto-reverted ---

@test "check: a moved HEAD is tampered=true, action=manual_review_required, no file restore attempted" {
  run_in_repo "snapshot --phase pre-gen --forge-dir .forge"
  echo "sneaky" > "$TEST_DIR/sneaky.js"
  ( cd "$TEST_DIR" && git add -A && git commit -q -m "feat(ST-2): generator committed, violating Hard Rule 3" )
  run_in_repo "check --phase pre-gen --forge-dir .forge"
  [ "$(jq_field '.tampered')" = "true" ]
  [ "$(jq_field '.head_moved')" = "true" ]
  [ "$(jq_field '.action')" = "manual_review_required" ]
  [ "$(jq_field '.head_before')" != "$(jq_field '.head_after')" ]
  # the commit must NOT be reverted -- see F064's note about not destroying
  # the forensic trail with an automated git reset.
  [ -f "$TEST_DIR/sneaky.js" ]
}

# --- Multiple phases coexist independently ---

@test "snapshot/check: pre-gen and pre-eval phases do not clobber each other" {
  run_in_repo "snapshot --phase pre-gen --forge-dir .forge"
  echo '{"stories_attempted": 1}' > "$FORGE_DIR/state.json"
  run_in_repo "snapshot --phase pre-eval --forge-dir .forge"
  # Check pre-eval FIRST (against its own up-to-date baseline) so its
  # not-tampered result can't be disturbed by pre-gen's check restoring
  # state.json out from under it -- each phase's snapshot must be read back
  # independently regardless of check order.
  run_in_repo "check --phase pre-eval --forge-dir .forge"
  [ "$(jq_field '.tampered')" = "false" ]
  # pre-gen's snapshot still has the OLD state.json content as its baseline,
  # so it must report the change pre-eval's snapshot already absorbed as
  # tampering relative to ITS OWN baseline.
  run_in_repo "check --phase pre-gen --forge-dir .forge"
  [ "$(jq_field '.tampered')" = "true" ]
}

# --- Output is always valid JSON ---

@test "output is always valid JSON" {
  run_in_repo "snapshot --phase p --forge-dir .forge"
  echo "$output" | jq . >/dev/null
  run_in_repo "check --phase p --forge-dir .forge"
  echo "$output" | jq . >/dev/null
}
