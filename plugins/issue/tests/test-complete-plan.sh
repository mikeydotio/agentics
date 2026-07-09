#!/usr/bin/env bash
# `complete plan <n>` — READ-ONLY guard-rail classification. Over a realistic repo
# (see mk_complete_repo) holding a merged branch, an unmerged branch, a merged PR
# head branch (local + pushed), a clean worktree, and a LOCKED worktree, asserts:
# only mergeable/clean targets are listed; the unmerged/locked/dirty/current/
# default items are skipped-with-reason and never queued for deletion.
source "$(dirname "$0")/lib.sh"

repo=$(mk_complete_repo)
export FAKE_GH_CLOSED_BY_PRS='[{"number":61}]'   # PR #61 closed the issue; head fix/thing-61, MERGED

out=$(cd "$repo" && bash "$SCRIPT" complete plan 77 2>&1)
assert_eq "$(jqf "$out" .ok)" "true" "plan ok:true"
assert_eq "$(jqf "$out" .issue)" "77" "plan issue 77"
assert_eq "$(jqf "$out" .state)" "OPEN" "plan state OPEN"
assert_eq "$(jqf "$out" .default_branch)" "main" "plan default main"
assert_eq "$(jqf "$out" '.plan.close')" "true" "plan will close (OPEN)"

# worktrees: rep-77 removable, 77 locked → skipped
assert_contains "$(jqf "$out" '[.plan.worktrees.removable[].path]|join(",")')" "/rep-77" "removable has rep-77"
assert_not_contains "$(jqf "$out" '[.plan.worktrees.removable[].path]|join(",")')" "/77" "removable excludes locked 77"
assert_contains "$(jqf "$out" '[.plan.worktrees.skipped[]|.path+":"+.reason]|join(",")')" "/77:locked" "77 skipped as locked"

# branches: merged worktree branch + merged PR head are deletable; unmerged is skipped
dl=$(jqf "$out" '.plan.branches.local_deletable|join(",")')
assert_contains "$dl" "worktree-rep-77" "merged worktree branch deletable"
assert_contains "$dl" "fix/thing-61" "merged PR head deletable (local)"
assert_not_contains "$dl" "worktree-77" "unmerged branch NOT deletable"
assert_contains "$(jqf "$out" '[.plan.branches.skipped[]|.branch+":"+.reason]|join(",")')" "worktree-77:unmerged" "unmerged branch skipped"
assert_contains "$(jqf "$out" '.plan.branches.remote_deletable|join(",")')" "fix/thing-61" "merged PR head deletable (remote)"

# the default branch is NEVER a delete target anywhere
allbr=$(jqf "$out" '[.plan.branches.local_deletable[], .plan.branches.remote_deletable[], (.plan.branches.skipped[].branch)]|join(",")')
assert_not_contains ",$allbr," ",main," "default branch never listed"

# actions_count = 1 close + 1 worktree + 2 local branches + 1 remote branch = 5
assert_eq "$(jqf "$out" .actions_count)" "5" "actions_count tally"

# --- dirty worktree is skipped (mutate rep-77, re-scan) ---
echo dirt > "$repo/.claude/worktrees/rep-77/dirty"
out=$(cd "$repo" && bash "$SCRIPT" complete plan 77 2>&1)
assert_not_contains "$(jqf "$out" '[.plan.worktrees.removable[].path]|join(",")')" "/rep-77" "dirty rep-77 no longer removable"
assert_contains "$(jqf "$out" '[.plan.worktrees.skipped[]|.path+":"+.reason]|join(",")')" "/rep-77:dirty" "dirty rep-77 skipped"

# --- the current worktree is skipped (run FROM inside rep-77) ---
rm -f "$repo/.claude/worktrees/rep-77/dirty"
out=$(cd "$repo/.claude/worktrees/rep-77" && bash "$SCRIPT" complete plan 77 2>&1)
assert_contains "$(jqf "$out" '[.plan.worktrees.skipped[]|.path+":"+.reason]|join(",")')" "/rep-77:current" "current worktree skipped"

finish
