#!/usr/bin/env bash
# issue #107: `/issue do <n>` must always build new work on the latest
# origin/<default> tip, never a stale local branch a daemon-managed repo has
# permanently stopped pulling. `dispatch` now creates the per-issue worktree
# itself (git worktree add), based on a freshly-fetched origin/<default>
# rather than delegating to `claude -w` (which branched off local HEAD with no
# fetch at all). These drive REAL (non-dry-run) dispatch runs — same fake
# tmux/gh harness as test-gitignore.sh/test-readiness.sh — across the three
# base-freshness tiers: FRESH (stale-local-main proof, the core regression),
# CACHED (fetch fails but a prior origin/<default> ref exists), and
# HEAD-FALLBACK (origin/<default> never resolved at all — offline AND never
# fetched — including the ISSUE_REQUIRE_FRESH_BASE=1 hard-fail escalation).
source "$(dirname "$0")/lib.sh"

FAKE_TMUX_DIR="$TESTS_DIR/fakes"

# dispatch_real <repo-dir> <issue> — run a real (non-dry-run) dispatch against
# <repo-dir> with the fake tmux/gh wired in, and echo the emitted JSON.
dispatch_real() {
  local dir="$1" n="$2"
  ( cd "$dir" \
      && PATH="$FAKE_TMUX_DIR:$PATH" \
         TMUX="fake,0,0" TMUX_PANE="%0" \
         ISSUE_LABEL="" \
         ISSUE_READY_DELAY=0 \
         ISSUE_CONFIRM_DELAY=0 ISSUE_PASTE_SETTLE_DELAY=0 \
         FAKE_TMUX_CAPTURE=marker \
         bash "$SCRIPT" dispatch "$n" 2>&1 )
}

# ==============================================================================
# Case 1 (the #107 proof): local main is genuinely stale vs. origin/main. The
# new worktree branch must land on the FRESH origin tip, never the stale local
# one — this is exactly the daemon-managed-repo condition (issue #99's sibling)
# where nothing ever pulls local main.
# ==============================================================================
repo=$(mk_stale_dispatch_repo)

# Fixture sanity: local main really does lag the REAL origin (queried
# directly via ls-remote, never the local tracking ref — the fetch under test
# hasn't run yet, so no tracking ref exists to accidentally launder this check).
stale_local_oid=$(cd "$repo" && git rev-parse main)
fresh_origin_oid=$(cd "$repo" && git ls-remote origin main | awk '{print $1}')
[ "$stale_local_oid" != "$fresh_origin_oid" ] \
  || fail_test "fixture invalid: local main is not stale vs the real origin"

out=$(dispatch_real "$repo" 42)
assert_eq "$(jqf "$out" .ok)" "true" "stale-base: ok:true"
assert_eq "$(jqf "$out" .base_branch)" "main" "stale-base: base_branch main"
assert_eq "$(jqf "$out" .base_fresh)" "true" "stale-base: fetch succeeded -> base_fresh:true"
assert_eq "$(jqf "$out" .base_oid)" "$fresh_origin_oid" "stale-base: base_oid is the FRESH origin tip"
[ "$(jqf "$out" .base_oid)" != "$stale_local_oid" ] \
  || fail_test "stale-base: base_oid equals the STALE local tip (the #107 regression)"
wt_oid=$(cd "$repo" && git rev-parse worktree-rep-42)
assert_eq "$wt_oid" "$fresh_origin_oid" "stale-base: worktree branch tip == fresh origin/main"
[ "$wt_oid" != "$stale_local_oid" ] \
  || fail_test "stale-base: worktree branch tip equals the STALE local main (the #107 regression)"
# The worktree must actually exist on disk, checked out at that commit.
[ -d "$repo/.claude/worktrees/rep-42" ] || fail_test "stale-base: worktree directory missing"
assert_eq "$(cd "$repo/.claude/worktrees/rep-42" && git rev-parse HEAD)" "$fresh_origin_oid" \
  "stale-base: worktree HEAD checked out at the fresh tip"
assert_eq "$(jqf "$out" 'has("warning")')" "false" "stale-base: no staleness warning on the happy path"

# ==============================================================================
# Case 2: CACHED tier — the fetch fails, but a prior origin/<default> ref
# already exists (a previous successful fetch/push populated it). The worktree
# must still be based on that cached ref, with a warning naming the miss.
# ==============================================================================
cached=$(mk_dispatch_repo)
# `git push -u` already populated refs/remotes/origin/main locally (verified
# empirically) — capture that cached OID, THEN break the origin so the next
# fetch (inside dispatch) fails outright.
cached_oid=$(cd "$cached" && git rev-parse refs/remotes/origin/main)
( cd "$cached" && git remote set-url origin /nonexistent/issue-107-dead-origin/fake/repo.git )

out=$(dispatch_real "$cached" 42)
assert_eq "$(jqf "$out" .ok)" "true" "cached: ok:true (never hard-fails on a refresh miss)"
assert_eq "$(jqf "$out" .base_fresh)" "false" "cached: fetch failed -> base_fresh:false"
assert_eq "$(jqf "$out" .base_oid)" "$cached_oid" "cached: base_oid is the last-known origin/main"
assert_contains "$(jqf "$out" .warning)" "couldn't refresh origin/main" "cached: warning names the refresh miss"
assert_eq "$(cd "$cached" && git rev-parse worktree-rep-42)" "$cached_oid" \
  "cached: worktree branch tip == the cached origin/main OID"

# ==============================================================================
# Case 3: HEAD-FALLBACK tier — origin/<default> has NEVER resolved (offline AND
# never fetched: a fresh repo whose origin was never reachable). Bases on local
# HEAD with a LOUD warning that the freshness guarantee was NOT met, and
# ISSUE_REQUIRE_FRESH_BASE=1 escalates that miss to a hard ok:false.
# ==============================================================================
dead=$(mktemp -d /tmp/issue-dispatch-dead.XXXXXX)
_TMP_REPOS+=("$dead")
( cd "$dead" && git init -q -b main \
    && git config user.email t@t && git config user.name t \
    && git remote add origin /nonexistent/issue-107-never-existed/fake/repo.git \
    && echo a > f && git add f && git commit -qm init ) >/dev/null 2>&1
head_oid=$(cd "$dead" && git rev-parse HEAD)

out=$(dispatch_real "$dead" 42)
assert_eq "$(jqf "$out" .ok)" "true" "head-fallback: ok:true (warns, doesn't block, by default)"
assert_eq "$(jqf "$out" .base_fresh)" "false" "head-fallback: base_fresh:false"
assert_eq "$(jqf "$out" .base_oid)" "$head_oid" "head-fallback: base_oid is local HEAD"
assert_contains "$(jqf "$out" .warning)" "NOT the latest origin tip" "head-fallback: warning states the guarantee was NOT met"
assert_eq "$(cd "$dead" && git rev-parse worktree-rep-42)" "$head_oid" \
  "head-fallback: worktree branch tip == local HEAD"

# ISSUE_REQUIRE_FRESH_BASE=1 escalates the SAME miss to a hard failure. A
# different issue number avoids colliding with the worktree/branch case 3 just
# created above.
out=$( cd "$dead" \
    && PATH="$FAKE_TMUX_DIR:$PATH" TMUX="fake,0,0" TMUX_PANE="%0" \
       ISSUE_LABEL="" ISSUE_REQUIRE_FRESH_BASE=1 \
       ISSUE_READY_DELAY=0 \
       ISSUE_CONFIRM_DELAY=0 ISSUE_PASTE_SETTLE_DELAY=0 \
       FAKE_TMUX_CAPTURE=marker \
       bash "$SCRIPT" dispatch 43 2>&1 )
assert_eq "$(jqf "$out" .ok)" "false" "require-fresh-base: ok:false when the guarantee can't be met"
assert_contains "$(jqf "$out" .display)" "ISSUE_REQUIRE_FRESH_BASE" "require-fresh-base: display names the knob"
( cd "$dead" && git show-ref --verify --quiet refs/heads/worktree-rep-43 ) \
  && fail_test "require-fresh-base: no worktree/branch should exist after a pre-worktree hard-fail" || :

finish
