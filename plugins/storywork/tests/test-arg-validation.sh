#!/usr/bin/env bash
# Argument validation: valid_story_id() is the one deliberately
# security-motivated guard this actuator introduces (a story id is
# interpolated verbatim into worktree paths and branch names via
# resolve_wname) -- non-empty, alphanumeric plus hyphen/underscore only,
# rejecting path traversal and embedded whitespace. Every case here asserts
# BOTH ok:false/exit 1 AND that no worktree/branch was ever created -- the
# guard must fire before any side effect, not just report failure after one.
# Applied to both dispatch and complete, mirroring plugins/issue/tests/
# test-arg-validation.sh's house style (same shape, story-id alphabet instead
# of issue's positive-integer check).
source "$(dirname "$0")/lib.sh"

# expected_wname — mirrors resolve_wname's derivation (first 3 alnum chars of
# the repo dir basename, lowercased, + "-<id>") so a would-be worktree/branch
# for a REJECTED id can be asserted absent without hardcoding a name.
expected_wname() {
  local repo="$1" id="$2" prefix
  prefix=$(basename "$repo" | tr -cd '[:alnum:]' | cut -c1-3 | tr '[:upper:]' '[:lower:]')
  printf '%s-%s' "$prefix" "$id"
}

# assert_no_side_effect <repo> <id> <label> — no worktree dir and no
# worktree-<wname> branch exist for <id> in <repo>.
assert_no_side_effect() {
  local repo="$1" id="$2" label="$3" wname
  wname=$(expected_wname "$repo" "$id")
  [ ! -e "$repo/.claude/worktrees/$wname" ] \
    || fail_test "$label: worktree directory was created for a rejected id"
  ( cd "$repo" && git show-ref --verify --quiet "refs/heads/worktree-$wname" ) \
    && fail_test "$label: worktree branch was created for a rejected id" || :
}

repo=$(mk_repo)

# ---------- bad top-level subcommand ----------
out=$(cd "$repo" && bash "$SCRIPT" bogus SH-1 2>&1); rc=$?
assert_eq "$rc" "1" "bad subcommand exits 1"
assert_eq "$(jqf "$out" .ok)" "false" "bad subcommand ok:false"
assert_contains "$(jqf "$out" .display)" "dispatch" "bad-subcommand usage names dispatch"
assert_contains "$(jqf "$out" .display)" "complete" "bad-subcommand usage names complete"

for verb in dispatch complete; do
  # ---------- missing id ----------
  out=$(cd "$repo" && bash "$SCRIPT" "$verb" 2>&1); rc=$?
  assert_eq "$rc" "1" "$verb missing id exits 1"
  assert_eq "$(jqf "$out" .ok)" "false" "$verb missing id ok:false"
  assert_contains "$(jqf "$out" .display)" "usage" "$verb missing id names usage"

  # ---------- id containing a path-traversal slash ----------
  out=$(cd "$repo" && bash "$SCRIPT" "$verb" "../../etc" 2>&1); rc=$?
  assert_eq "$rc" "1" "$verb path-traversal id exits 1"
  assert_eq "$(jqf "$out" .ok)" "false" "$verb path-traversal id ok:false"
  assert_contains "$(jqf "$out" .display)" "alphanumeric" "$verb path-traversal id names the guard"
  assert_no_side_effect "$repo" "../../etc" "$verb path-traversal"

  # ---------- id containing embedded whitespace ----------
  out=$(cd "$repo" && bash "$SCRIPT" "$verb" "SH 1" 2>&1); rc=$?
  assert_eq "$rc" "1" "$verb whitespace id exits 1"
  assert_eq "$(jqf "$out" .ok)" "false" "$verb whitespace id ok:false"
  assert_contains "$(jqf "$out" .display)" "alphanumeric" "$verb whitespace id names the guard"
  assert_no_side_effect "$repo" "SH 1" "$verb whitespace"

  # ---------- id containing dots (rejected -- not in the alphanumeric/-/_ set) ----------
  out=$(cd "$repo" && bash "$SCRIPT" "$verb" "SH..1" 2>&1); rc=$?
  assert_eq "$rc" "1" "$verb dotted id exits 1"
  assert_eq "$(jqf "$out" .ok)" "false" "$verb dotted id ok:false"
  assert_contains "$(jqf "$out" .display)" "alphanumeric" "$verb dotted id names the guard"
  assert_no_side_effect "$repo" "SH..1" "$verb dotted"

  # ---------- id starting with a hyphen (would be parsed as a flag downstream) ----------
  out=$(cd "$repo" && bash "$SCRIPT" "$verb" "-rf" 2>&1); rc=$?
  assert_eq "$rc" "1" "$verb leading-hyphen id exits 1"
  assert_eq "$(jqf "$out" .ok)" "false" "$verb leading-hyphen id ok:false"
  assert_no_side_effect "$repo" "-rf" "$verb leading-hyphen"
done

finish
