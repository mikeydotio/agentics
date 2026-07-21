#!/usr/bin/env bash
# Regression for the issue #99 defect class (agentics' `issue` plugin sibling
# issue — the exact reason freshen_base_ref/branch_is_merged live in the
# shared session.sh): `complete` must recognise a branch merged on the
# REMOTE (origin/main) even when the local checkout's `main` LAGS it — the
# daemon-managed-repo condition where nothing ever pulls local main. Over the
# stale-base fixture (mk_stale_base_repo) it asserts the merged-on-origin
# worktree branch is classified deletable and ACTUALLY deleted — which needs
# BOTH the fresh origin/<base> merged check AND the `git branch -d`->`-D`
# escalation, since `git branch -d` alone refuses it here.
source "$(dirname "$0")/lib.sh"

# The fixture must genuinely leave local main lagging: the worktree branch is
# merged on origin/main but must NOT be an ancestor of local main (else the
# bug can't manifest and the test would pass vacuously).
repo=$(mk_stale_base_repo SH-88)
wname=$(basename "$repo" | tr -cd '[:alnum:]' | cut -c1-3 | tr '[:upper:]' '[:lower:]')-SH-88

( cd "$repo" && git merge-base --is-ancestor "refs/heads/worktree-$wname" main 2>/dev/null ) \
  && fail_test "fixture invalid: worktree-$wname already an ancestor of local main" || :
# ...and local main must lag the REAL origin (queried directly): origin
# advanced to the merge commit while local main — and its stale origin/main
# tracking ref — both sit at init. Comparing against ls-remote (not the stale
# tracking ref) proves the lag the fix's freshen must close.
[ "$(cd "$repo" && git rev-parse main)" != "$(cd "$repo" && git ls-remote origin main | awk '{print $1}')" ] \
  || fail_test "fixture invalid: local main is not stale vs the real origin"

# ---------- the merged-on-origin worktree branch is actually deleted ----------
out=$(cd "$repo" && bash "$SCRIPT" complete SH-88 2>&1)
assert_eq "$(jqf "$out" .ok)" "true" "exec ok:true"
assert_contains "$(jqf "$out" '.removed.branches | join(",")')" \
  "worktree-$wname" "merged-on-origin branch reported removed despite lagging local main"
( cd "$repo" && git show-ref --verify --quiet "refs/heads/worktree-$wname" ) \
  && fail_test "worktree-$wname still present after complete (delete escalation failed)" || :

finish
