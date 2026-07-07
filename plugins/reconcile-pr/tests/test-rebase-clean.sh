#!/usr/bin/env bash
# start on a non-conflicting PR → clean; on an up-to-date PR → already_current.
source "$(dirname "$0")/lib.sh"
PR=7

# ---- already_current: PR head already contains latest base -------------------
CO="$(reconcile_fixture current)"
out=$(rp "$CO" start "$PR")
assert_eq "$(jqf "$out" '.status')" "already_current" "current → already_current"
assert_eq "$(jqf "$out" '.ok')" "true" "current → ok:true"
# No worktree/state should be created when there is nothing to do.
[ -e "$CO/.claude/worktrees/reconcile-pr/$PR" ] && fail_test "already_current created state (should not)"

# ---- clean rebase: disjoint changes replay without conflict ------------------
CO2="$(reconcile_fixture clean)"
out=$(rp "$CO2" start "$PR")
assert_eq "$(jqf "$out" '.ok')" "true" "clean → ok:true"
assert_eq "$(jqf "$out" '.status')" "clean" "clean → status clean"
WT="$(wt_path "$CO2" "$PR")"
[ -d "$WT" ] || fail_test "clean rebase should create the worktree"
# The rebased worktree HEAD contains BOTH the PR file and main's change.
[ -f "$WT/feature.txt" ] || fail_test "clean rebase lost the PR's feature.txt"
assert_contains "$(cat "$WT/file.txt" 2>/dev/null)" "main-added" "clean rebase kept main's change"
head_oid=$(jqf "$out" '.head_oid')
assert_ne "$head_oid" "" "clean → head_oid present"

# status re-orients to clean.
out=$(rp "$CO2" status "$PR")
assert_eq "$(jqf "$out" '.phase')" "clean" "status after clean → phase clean"

# cleanup tears it down.
out=$(rp "$CO2" cleanup "$PR")
assert_eq "$(jqf "$out" '.ok')" "true" "cleanup → ok:true"
[ -e "$CO2/.claude/worktrees/reconcile-pr/$PR" ] && fail_test "cleanup did not remove state"

finish
