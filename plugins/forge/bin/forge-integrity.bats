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

# The shipped script keys its snapshot directory by a 16-char `git hash-object`
# digest of the project's absolute path, then by session (forge-integrity.sh
# :133-156). Recomputing that digest here is what lets teardown delete THIS
# test's snapshots without touching the shared root. The duplication is
# deliberate and is pinned: `teardown's key derivation still matches the
# script's snapshot path` below reds the moment the two drift, which is what
# keeps a drifted derivation from degrading teardown into a silent no-op.
SNAPSHOT_ROOT="/tmp/forge-integrity"

snapshot_dir_for_test() {
  printf '%s/%s' "$SNAPSHOT_ROOT" \
    "$(printf '%s' "$TEST_DIR" | git hash-object --stdin | cut -c1-16)"
}

snapshot_file_for_test() {
  printf '%s/default/%s.json' "$(snapshot_dir_for_test)" "$1"
}

teardown() {
  rm -rf "$TEST_DIR"
  # Delete ONLY this test's own project-keyed snapshot dir.
  #
  # This was `rm -rf "/tmp/forge-integrity"` — the whole shared root — on the
  # grounds that per-test paths are unique anyway and it "keeps /tmp tidy".
  # The paths are indeed unique; the ROOT is not. That root is machine-global:
  # it holds the live baselines of every project on the box, so the blanket rm
  # deleted the snapshots of every concurrently running copy of this suite AND
  # of any real forge session in another repository (AGE-34). Measured, with
  # that rm as the only concurrent actor and no second suite running: 14 of 19
  # tests failed.
  rm -rf "$(snapshot_dir_for_test)"
  # Tidiness without the capability. `rmdir` is not recursive: it removes the
  # shared root only when this run left it empty, and fails harmlessly the
  # instant any other project's snapshots are present.
  rmdir "$SNAPSHOT_ROOT" 2>/dev/null || true
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

@test "check after its fixture-owned snapshot is lost: ok=false, does not crash" {
  run_in_repo "snapshot --phase lost --forge-dir .forge"
  [ "$(jq_field '.ok')" = "true" ]
  rm -f "$(snapshot_file_for_test lost)"
  run_in_repo "check --phase lost --forge-dir .forge"
  [ "$status" -eq 0 ]
  [ "$(jq_field '.ok')" = "false" ]
  [ "$(jq_field '.error')" = "no_snapshot_for_phase_lost" ]
}

@test "check with a corrupt fixture-owned snapshot exits nonzero with diagnostics" {
  run_in_repo "snapshot --phase corrupt --forge-dir .forge"
  [ "$(jq_field '.ok')" = "true" ]
  printf '%s\n' '{not-json' > "$(snapshot_file_for_test corrupt)"
  run_in_repo "check --phase corrupt --forge-dir .forge"
  [ "$status" -ne 0 ]
  [ -n "$output" ]
}

@test "check with an unreadable fixture-owned snapshot exits nonzero with diagnostics" {
  run_in_repo "snapshot --phase unreadable --forge-dir .forge"
  [ "$(jq_field '.ok')" = "true" ]
  chmod 000 "$(snapshot_file_for_test unreadable)"
  run_in_repo "check --phase unreadable --forge-dir .forge"
  [ "$status" -ne 0 ]
  [ -n "$output" ]
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

# --- F100: --session-id scopes snapshots so concurrent same-project runs can't collide ---

@test "two concurrent sessions in the SAME project do not clobber each other's snapshot" {
  # Session A snapshots, then tampers its own state.json (simulating its
  # own generator run) -- session B (different --session-id, same phase
  # name, same project) must have its OWN baseline, unaffected by A's.
  run_in_repo "snapshot --phase pre-gen --forge-dir .forge --session-id session-A"
  [ "$(jq_field '.ok')" = "true" ]
  echo '{"stories_attempted": 1}' > "$FORGE_DIR/state.json"
  run_in_repo "snapshot --phase pre-gen --forge-dir .forge --session-id session-B"
  [ "$(jq_field '.ok')" = "true" ]

  # Check session B FIRST: its own baseline was taken AFTER the state.json
  # change above, so nothing has changed since -- ok. (Order matters here:
  # a tampered check auto-restores file content, which would otherwise
  # disturb the file before this check runs -- same ordering caveat as the
  # pre-gen/pre-eval phase-isolation test above, just across sessions
  # instead of phases.)
  run_in_repo "check --phase pre-gen --forge-dir .forge --session-id session-B"
  [ "$(jq_field '.tampered')" = "false" ]

  # Session A's baseline predates that change, so ITS check must see it as
  # tampering relative to ITS OWN snapshot -- proving the two sessions
  # never shared one snapshot file (without session scoping, both checks
  # above would have read/raced on the same path).
  run_in_repo "check --phase pre-gen --forge-dir .forge --session-id session-A"
  [ "$(jq_field '.tampered')" = "true" ]
}

@test "omitting --session-id preserves the prior project-only-scoped path (back-compat)" {
  run_in_repo "snapshot --phase p --forge-dir .forge"
  run_in_repo "check --phase p --forge-dir .forge"
  [ "$(jq_field '.ok')" = "true" ]
  [ "$(jq_field '.tampered')" = "false" ]
}

# --- AGE-34: teardown owns exactly its own subtree, and knows where that is ---

@test "teardown's key derivation still matches the script's snapshot path" {
  run_in_repo "snapshot --phase p --forge-dir .forge"
  [ "$(jq_field '.ok')" = "true" ]
  # Deliberately asserted against the file the script ACTUALLY wrote, not
  # against a second copy of the same derivation — the latter would agree with
  # itself even after both drifted away from forge-integrity.sh.
  #
  # If this reds, teardown has silently become a no-op: it is deleting a path
  # the script no longer writes, so every run leaks a snapshot dir and the
  # blanket-rm temptation that caused AGE-34 comes straight back.
  [ -f "$(snapshot_dir_for_test)/default/p.json" ]
}

@test "a session id with unsafe path characters is sanitized, not passed through raw" {
  run_in_repo "snapshot --phase p --forge-dir .forge --session-id '../../etc/evil'"
  [ "$(jq_field '.ok')" = "true" ]
  # The snapshot must land under forge-integrity's own /tmp tree, not have
  # escaped it via the session id.
  [ ! -d "/tmp/etc" ]
}
