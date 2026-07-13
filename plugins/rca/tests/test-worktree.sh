#!/usr/bin/env bash
# rca-worktree.sh: create/status/destroy round-trip; --copy of an untracked file
# lands in the worktree; setup_failed leaves the worktree; destroy tolerates an
# already-removed worktree; create from INSIDE another worktree resolves the
# main repo root.
source "$(dirname "$0")/lib.sh"

REPO="$(make_fixture_repo)"
cd "$REPO"
mkdir -p .rca/inv/repro

# ---- create (with an untracked --copy) ---------------------------------------
printf 'untracked repro contents\n' > repro.sh   # untracked in the main tree
out=$(bash "$WORKTREE" create inv --ref HEAD --copy repro.sh)
assert_json "$out" '.ok == true' "create ok"
assert_eq "$(jqf "$out" '.branch')" "rca/inv" "branch rca/inv"
assert_json "$out" '.copied == ["repro.sh"]' "copied reports repro.sh"
WT="$REPO/.claude/worktrees/rca/inv/worktree"
[ -d "$WT" ] || fail_test "worktree dir not created"
[ -f "$WT/repro.sh" ] || fail_test "untracked --copy did NOT travel to the worktree"
assert_eq "$(cat "$WT/repro.sh")" "untracked repro contents" "copied file content matches"
# worktree.json written to state dir AND to the .rca/<slug>/ investigation dir
[ -f "$REPO/.claude/worktrees/rca/inv/worktree.json" ] || fail_test "state worktree.json missing"
[ -f "$REPO/.rca/inv/worktree.json" ] || fail_test ".rca/<slug>/worktree.json missing"

# ---- status: exists + dirty (untracked copy makes it dirty) ------------------
out=$(bash "$WORKTREE" status inv)
assert_json "$out" '.exists == true' "status exists true"
assert_eq "$(jqf "$out" '.branch')" "rca/inv" "status branch"
assert_json "$out" '.dirty == true' "untracked copy → dirty"

# ---- destroy round-trip ------------------------------------------------------
out=$(bash "$WORKTREE" destroy inv)
assert_json "$out" '.ok == true and .removed == true' "destroy ok"
[ -d "$WT" ] && fail_test "worktree dir still present after destroy"
[ -f "$REPO/.rca/inv/worktree.json" ] && fail_test ".rca worktree.json not cleaned"
out=$(bash "$WORKTREE" status inv)
assert_json "$out" '.exists == false and .dirty == false' "status absent after destroy"

# ---- destroy tolerates an already-removed worktree ---------------------------
out=$(bash "$WORKTREE" destroy inv)
assert_json "$out" '.ok == true and .removed == true' "destroy is idempotent"

# ---- setup_failed leaves the worktree for inspection -------------------------
mkdir -p .rca/setupfail
out=$(bash "$WORKTREE" create setupfail --setup-cmd 'echo nope >&2; exit 3' || true)
assert_json "$out" '.ok == false and .error == "setup_failed"' "failing setup → setup_failed"
assert_json "$out" '.tail | test("nope")' "setup_failed carries a tail"
[ -d "$REPO/.claude/worktrees/rca/setupfail/worktree" ] || fail_test "setup_failed should LEAVE the worktree"
bash "$WORKTREE" destroy setupfail >/dev/null 2>&1

# ---- successful setup runs and reports setup_ran -----------------------------
mkdir -p .rca/setupok
out=$(bash "$WORKTREE" create setupok --setup-cmd 'echo built > .built')
assert_json "$out" '.ok == true and .setup_ran == true' "successful setup → setup_ran true"
[ -f "$REPO/.claude/worktrees/rca/setupok/worktree/.built" ] || fail_test "setup-cmd did not run in worktree"
bash "$WORKTREE" destroy setupok >/dev/null 2>&1

# ---- create from INSIDE another worktree resolves the MAIN root --------------
mkdir -p .rca/outer .rca/inner
bash "$WORKTREE" create outer >/dev/null
OUTER_WT="$REPO/.claude/worktrees/rca/outer/worktree"
[ -d "$OUTER_WT" ] || fail_test "outer worktree missing"
# Run create for a second slug from *inside* the outer worktree.
out=$(cd "$OUTER_WT" && bash "$WORKTREE" create inner)
assert_json "$out" '.ok == true' "create from inside a worktree ok"
inner_path=$(jqf "$out" '.path')
# The inner worktree must live under the MAIN repo root, NOT nested in the outer.
assert_eq "$inner_path" "$REPO/.claude/worktrees/rca/inner/worktree" "inner resolves to MAIN root"
assert_not_contains "$inner_path" "worktrees/rca/outer/" "inner is NOT nested under the outer worktree"
bash "$WORKTREE" destroy inner >/dev/null 2>&1
bash "$WORKTREE" destroy outer >/dev/null 2>&1

finish
