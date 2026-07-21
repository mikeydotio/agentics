#!/usr/bin/env bash
# Regression for the base-freshness defect class (agentics' `issue` plugin
# issues #99/#107, the exact reason session.sh's freshen_base_ref/
# branch_is_merged were extracted): `dispatch` must always base the new
# worktree on the freshest reachable origin/<default> tip, never a stale
# local branch a daemon-managed repo has permanently stopped pulling, and it
# must correctly REPORT which freshness tier it landed in. story.sh's
# cmd_dispatch captures its OWN `git fetch`'s exit code (mirroring
# plugins/issue/bin/issue.sh's cmd_dispatch, NOT routing through
# freshen_base_ref, whose contract is "any fetch failure is swallowed") so it
# can distinguish FRESH (fetch ok) from CACHED (fetch failed, a prior
# origin/<default> ref still resolves) from HEAD-FALLBACK (origin/<default>
# has never resolved at all).
source "$(dirname "$0")/lib.sh"

FAKE_TMUX_DIR="$TESTS_DIR/fakes"

# dispatch_real <repo-dir> <story-id> — run a real (non-dry-run) dispatch
# against <repo-dir> with the fake tmux/story wired in, and echo the emitted
# JSON. FAKE_STORY_STATE=in-progress throughout: these cases are about base
# freshness, not claim semantics (already covered by test-dispatch.sh).
dispatch_real() {
  local dir="$1" id="$2"
  ( cd "$dir" \
      && PATH="$FAKE_TMUX_DIR:$PATH" \
         TMUX="fake,0,0" TMUX_PANE="%0" \
         FAKE_STORY_STATE=in-progress \
         STORY_READY_DELAY=0 STORY_READY_FALLBACK_DELAY=0 \
         STORY_CONFIRM_DELAY=0 STORY_PASTE_SETTLE_DELAY=0 \
         FAKE_TMUX_CAPTURE=marker \
         bash "$SCRIPT" dispatch "$id" 2>&1 )
}

# ==============================================================================
# Case 1 (the #107-class proof): local main is genuinely stale vs. origin.
# The new worktree branch must land on the FRESH origin tip, never the stale
# local one.
# ==============================================================================
repo=$(mk_stale_dispatch_repo)

stale_local_oid=$(cd "$repo" && git rev-parse main)
fresh_origin_oid=$(cd "$repo" && git ls-remote origin main | awk '{print $1}')
[ "$stale_local_oid" != "$fresh_origin_oid" ] \
  || fail_test "fixture invalid: local main is not stale vs the real origin"

out=$(dispatch_real "$repo" SH-42)
assert_eq "$(jqf "$out" .ok)" "true" "stale-base: ok:true"
assert_eq "$(jqf "$out" .base_branch)" "main" "stale-base: base_branch main"
assert_eq "$(jqf "$out" .base_fresh)" "true" "stale-base: fetch succeeded -> base_fresh:true"
assert_eq "$(jqf "$out" .base_oid)" "$fresh_origin_oid" "stale-base: base_oid is the FRESH origin tip"
[ "$(jqf "$out" .base_oid)" != "$stale_local_oid" ] \
  || fail_test "stale-base: base_oid equals the STALE local tip"
wname=$(basename "$repo" | tr -cd '[:alnum:]' | cut -c1-3 | tr '[:upper:]' '[:lower:]')-SH-42
wt_oid=$(cd "$repo" && git rev-parse "worktree-$wname")
assert_eq "$wt_oid" "$fresh_origin_oid" "stale-base: worktree branch tip == fresh origin/main"
[ "$wt_oid" != "$stale_local_oid" ] \
  || fail_test "stale-base: worktree branch tip equals the STALE local main"
[ -d "$repo/.claude/worktrees/$wname" ] || fail_test "stale-base: worktree directory missing"
assert_eq "$(cd "$repo/.claude/worktrees/$wname" && git rev-parse HEAD)" "$fresh_origin_oid" \
  "stale-base: worktree HEAD checked out at the fresh tip"
assert_eq "$(jqf "$out" 'has("warning")')" "false" "stale-base: no staleness warning on the happy path"

# ==============================================================================
# Case 2: CACHED tier — the fetch fails, but a prior origin/<default> ref
# already exists (a previous successful fetch/push populated it).
# ==============================================================================
cached=$(mk_dispatch_repo)
cached_oid=$(cd "$cached" && git rev-parse refs/remotes/origin/main)
( cd "$cached" && git remote set-url origin /nonexistent/storywork-107-dead-origin/fake/repo.git )

out=$(dispatch_real "$cached" SH-42)
assert_eq "$(jqf "$out" .ok)" "true" "cached: ok:true (never hard-fails on a refresh miss)"
assert_eq "$(jqf "$out" .base_fresh)" "false" "cached: fetch failed -> base_fresh:false"
assert_eq "$(jqf "$out" .base_oid)" "$cached_oid" "cached: base_oid is the last-known origin/main"
assert_contains "$(jqf "$out" .warning)" "couldn't refresh origin/main" "cached: warning names the refresh miss"
wname_cached=$(basename "$cached" | tr -cd '[:alnum:]' | cut -c1-3 | tr '[:upper:]' '[:lower:]')-SH-42
assert_eq "$(cd "$cached" && git rev-parse "worktree-$wname_cached")" "$cached_oid" \
  "cached: worktree branch tip == the cached origin/main OID"

# ==============================================================================
# Case 3: HEAD-FALLBACK tier — origin/<default> has NEVER resolved (offline
# AND never fetched). Bases on local HEAD with a LOUD warning, and
# STORY_REQUIRE_FRESH_BASE=1 escalates that miss to a hard ok:false.
# ==============================================================================
dead=$(mktemp -d /tmp/storywork-dispatch-dead.XXXXXX)
_TMP_REPOS+=("$dead")
( cd "$dead" && git init -q -b main \
    && git config user.email t@t && git config user.name t \
    && git remote add origin /nonexistent/storywork-107-never-existed/fake/repo.git \
    && echo a > f && git add f && git commit -qm init ) >/dev/null 2>&1
head_oid=$(cd "$dead" && git rev-parse HEAD)

out=$(dispatch_real "$dead" SH-42)
assert_eq "$(jqf "$out" .ok)" "true" "head-fallback: ok:true (warns, doesn't block, by default)"
assert_eq "$(jqf "$out" .base_fresh)" "false" "head-fallback: base_fresh:false"
assert_eq "$(jqf "$out" .base_oid)" "$head_oid" "head-fallback: base_oid is local HEAD"
assert_contains "$(jqf "$out" .warning)" "NOT the latest origin tip" "head-fallback: warning states the guarantee was NOT met"
wname_dead=$(basename "$dead" | tr -cd '[:alnum:]' | cut -c1-3 | tr '[:upper:]' '[:lower:]')-SH-42
assert_eq "$(cd "$dead" && git rev-parse "worktree-$wname_dead")" "$head_oid" \
  "head-fallback: worktree branch tip == local HEAD"

# STORY_REQUIRE_FRESH_BASE=1 escalates the SAME miss to a hard failure. A
# different story id avoids colliding with the worktree/branch case 3 above.
out=$( cd "$dead" \
    && PATH="$FAKE_TMUX_DIR:$PATH" TMUX="fake,0,0" TMUX_PANE="%0" \
       FAKE_STORY_STATE=in-progress STORY_REQUIRE_FRESH_BASE=1 \
       STORY_READY_DELAY=0 STORY_READY_FALLBACK_DELAY=0 \
       STORY_CONFIRM_DELAY=0 STORY_PASTE_SETTLE_DELAY=0 \
       FAKE_TMUX_CAPTURE=marker \
       bash "$SCRIPT" dispatch SH-43 2>&1 )
assert_eq "$(jqf "$out" .ok)" "false" "require-fresh-base: ok:false when the guarantee can't be met"
assert_contains "$(jqf "$out" .display)" "STORY_REQUIRE_FRESH_BASE" "require-fresh-base: display names the knob"
wname_dead43=$(basename "$dead" | tr -cd '[:alnum:]' | cut -c1-3 | tr '[:upper:]' '[:lower:]')-SH-43
( cd "$dead" && git show-ref --verify --quiet "refs/heads/worktree-$wname_dead43" ) \
  && fail_test "require-fresh-base: no worktree/branch should exist after a pre-worktree hard-fail" || :

finish
