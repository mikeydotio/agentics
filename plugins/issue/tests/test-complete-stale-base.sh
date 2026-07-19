#!/usr/bin/env bash
# Regression for issue #99: `complete` must recognise a branch merged on the
# REMOTE (origin/main) even when the local checkout's `main` LAGS it — the
# daemon-managed-repo condition where nothing ever pulls local main. Over the
# stale-base fixture (mk_stale_base_repo) it asserts the merged-on-origin worktree
# branch is classified deletable and ACTUALLY deleted — which needs BOTH the fresh
# origin/<base> merged check AND the git-branch -d->-D escalation, since `git
# branch -d` alone refuses it here — while a genuinely-unmerged branch stays refused.
source "$(dirname "$0")/lib.sh"

# The fixture must genuinely leave local main lagging: worktree-rep-88 is merged
# on origin/main but must NOT be an ancestor of local main (else the bug can't
# manifest and the test would pass vacuously).
repo=$(mk_stale_base_repo)
( cd "$repo" && git merge-base --is-ancestor refs/heads/worktree-rep-88 main 2>/dev/null ) \
  && fail_test "fixture invalid: worktree-rep-88 already an ancestor of local main" || :
# …and local main must lag the REAL origin (queried directly): origin advanced to
# the merge commit while local main — and its stale origin/main tracking ref —
# both sit at init. Comparing against ls-remote (not the stale tracking ref)
# proves the lag the fix's freshen must close.
[ "$(cd "$repo" && git rev-parse main)" != "$(cd "$repo" && git ls-remote origin main | awk '{print $1}')" ] \
  || fail_test "fixture invalid: local main is not stale vs the real origin"

# ---------- plan: merged-on-origin is deletable; unmerged still skipped ----------
out=$(cd "$repo" && bash "$SCRIPT" complete plan 88 2>&1)
assert_eq "$(jqf "$out" .ok)" "true" "plan ok:true"
assert_eq "$(jqf "$out" .default_branch)" "main" "plan default main"
dl=$(jqf "$out" '.plan.branches.local_deletable|join(",")')
assert_contains "$dl" "worktree-rep-88" "merged-on-origin branch deletable despite lagging local main"
assert_not_contains "$dl" "worktree-88" "genuinely-unmerged branch NOT deletable"
assert_contains "$(jqf "$out" '[.plan.branches.skipped[]|.branch+":"+.reason]|join(",")')" \
  "worktree-88:unmerged" "unmerged branch still skipped with reason"

# ---------- execute: the merged-on-origin branch is actually deleted ----------
repo=$(mk_stale_base_repo)
out=$(cd "$repo" && bash "$SCRIPT" complete execute 88 2>&1)
assert_eq "$(jqf "$out" .ok)" "true" "exec ok:true"
assert_eq "$(jqf "$out" .closed)" "true" "exec closed the issue (was OPEN)"
assert_contains "$(jqf "$out" '.removed.branches_local|join(",")')" \
  "worktree-rep-88" "merged-on-origin branch reported removed"
( cd "$repo" && git show-ref --verify --quiet refs/heads/worktree-rep-88 ) \
  && fail_test "worktree-rep-88 still present after execute (delete escalation failed)" || :

# guard: the genuinely-unmerged branch is preserved and reported
( cd "$repo" && git show-ref --verify --quiet refs/heads/worktree-88 ) \
  || fail_test "GUARD: unmerged worktree-88 was deleted"
assert_contains "$(jqf "$out" '[.skipped[]|.ref+":"+.reason]|join(",")')" \
  "worktree-88:local, unmerged" "unmerged branch preserved and reported"

finish
