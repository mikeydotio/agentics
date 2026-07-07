#!/usr/bin/env bash
# preflight is read-only: OPEN gate, fork refusal, protected-head refusal, and a
# correct plan for the happy case. All run against one checkout (no side effects).
source "$(dirname "$0")/lib.sh"

CO="$(reconcile_fixture conflict)"
PR=7

# Happy: OPEN PR, base main, head pr-branch.
out=$(rp "$CO" preflight "$PR")
assert_eq "$(jqf "$out" '.ok')"           "true"      "happy → ok:true"
assert_eq "$(jqf "$out" '.base')"         "main"      "happy → base main"
assert_eq "$(jqf "$out" '.head')"         "pr-branch" "happy → head pr-branch"
assert_eq "$(jqf "$out" '.is_cross_repo')" "false"    "happy → not cross-repo"
assert_eq "$(jqf "$out" '.commit_count')" "2"         "happy → commit_count 2"
assert_contains "$(jqf "$out" '.plan.worktree_path')" ".claude/worktrees/reconcile-pr/$PR/worktree" "happy → worktree path"
# Read-only: no state dir created.
[ -e "$CO/.claude/worktrees/reconcile-pr/$PR" ] && fail_test "preflight created state (should be read-only)"

# Closed PR → refused.
out=$(cd "$CO" && FAKE_GH_STATE=CLOSED bash "$SCRIPT" preflight "$PR")
assert_eq "$(jqf "$out" '.ok')" "false" "closed → ok:false"
assert_contains "$(jqf "$out" '.display')" "CLOSED" "closed → mentions CLOSED"

# Fork / cross-repo PR → refused.
out=$(cd "$CO" && FAKE_GH_CROSS=true bash "$SCRIPT" preflight "$PR")
assert_eq "$(jqf "$out" '.ok')" "false" "fork → ok:false"
assert_contains "$(jqf "$out" '.display')" "fork" "fork → mentions fork"

# Protected head branch → refused (we could never safely force-push it).
out=$(cd "$CO" && FAKE_GH_HEAD=main bash "$SCRIPT" preflight "$PR")
assert_eq "$(jqf "$out" '.ok')" "false" "protected head → ok:false"
assert_contains "$(jqf "$out" '.display')" "protected" "protected head → mentions protected"

# PR not found → refused.
out=$(cd "$CO" && FAKE_GH_VIEW_FAIL=1 bash "$SCRIPT" preflight "$PR")
assert_eq "$(jqf "$out" '.ok')" "false" "not found → ok:false"

# Unauthenticated gh → refused.
out=$(cd "$CO" && FAKE_GH_AUTH_FAIL=1 bash "$SCRIPT" preflight "$PR")
assert_eq "$(jqf "$out" '.ok')" "false" "unauth → ok:false"
assert_contains "$(jqf "$out" '.display')" "authenticated" "unauth → mentions auth"

finish
