#!/usr/bin/env bash
# Regression for the SAME defect class agentics' `reconcile-pr` plugin already
# fixed under #108 (see plugins/reconcile-pr/tests/test-cwd-inside-worktree.sh):
# a subcommand must anchor its repo-root/worktree-path derivation to the MAIN
# worktree, never to CWD's own `git rev-parse --show-toplevel` — which returns
# a DIFFERENT (and equally "real") answer depending on which linked worktree
# CWD happens to be standing in.
#
# Pre-fix, story.sh derived `dir` (and therefore `repo_name`/`worktree_path`)
# from `basename "$(git rev-parse --show-toplevel)"`. From inside one of
# story.sh's OWN worktrees, that returns the WORKTREE's own root, not the main
# repo's — so any worktree_path built from it is a nonsensical path nested
# inside the worktree itself, matching NOTHING in `git worktree list`:
#   - `complete`, run from inside the very worktree it should clean up, could
#     not find it: `_story_worktree_status` reported "missing" (not even
#     "skipped") and complete returned ok:true having done nothing — the
#     worktree leaked on disk forever.
#   - `dispatch`, run from inside an EXISTING worktree of the same repo (e.g.
#     a second story dispatched from within a live session), would create its
#     NEW worktree NESTED inside the CWD worktree instead of alongside it at
#     the main repo's own `.claude/worktrees/`.
#
# Fixed by anchoring `dir` via `repo_root()` (git-common-dir's parent),
# mirroring reconcile-pr.sh's `need_repo` exactly.
source "$(dirname "$0")/lib.sh"

expected_wname() {
  local repo="$1" id="$2" prefix
  prefix=$(basename "$repo" | tr -cd '[:alnum:]' | cut -c1-3 | tr '[:upper:]' '[:lower:]')
  printf '%s-%s' "$prefix" "$id"
}

# ==============================================================================
# Case A: `complete` run with CWD INSIDE the very worktree it is cleaning up.
# The worktree is checked out ON its branch (--no-track -b), exactly as
# cmd_dispatch's own `git worktree add` creates it (NOT detached) — the exact
# fixture the review reproduced this defect against.
# ==============================================================================
repoA=$(mk_dispatch_repo)
wnameA=$(expected_wname "$repoA" "SH-CWD-A")
(
  cd "$repoA" || exit 1
  git worktree add -q --no-track -b "worktree-$wnameA" ".claude/worktrees/$wnameA"
) >/dev/null 2>&1

outA=$(cd "$repoA/.claude/worktrees/$wnameA" && bash "$SCRIPT" complete SH-CWD-A 2>&1)
assert_eq "$(jqf "$outA" .ok)" "true" "cwdA: ok:true"
assert_eq "$(jqf "$outA" '.removed.worktrees | length')" "0" \
  "cwdA: the current worktree must NEVER be removed out from under itself"
assert_contains "$(jqf "$outA" '.skipped | join(",")')" "current" \
  "cwdA: current worktree correctly reported skipped (not silently classed 'missing')"
[ -d "$repoA/.claude/worktrees/$wnameA" ] || fail_test "cwdA: worktree directory must still exist on disk"
( cd "$repoA" && git worktree list --porcelain | grep -q "/.claude/worktrees/$wnameA\$" ) \
  || fail_test "cwdA: worktree must still be registered in git worktree list"
# The branch IS checked out here, so git itself refuses to delete it (-d AND
# -D both refuse a branch used by a worktree) — story.sh must record that as
# a failure, never silently succeed or silently drop it.
assert_contains "$(jqf "$outA" '.failed | join(",")')" "worktree-$wnameA" \
  "cwdA: git's own refusal to delete a checked-out branch is reported, not swallowed"
( cd "$repoA" && git show-ref --verify --quiet "refs/heads/worktree-$wnameA" ) \
  || fail_test "cwdA: the branch backing the current worktree must not be deleted"

# ==============================================================================
# Case B: `dispatch` run with CWD INSIDE an EXISTING (different) worktree of
# the SAME repo. The new worktree must land beside it, anchored to the MAIN
# repo root — never nested inside the CWD worktree.
# ==============================================================================
repoB=$(mk_dispatch_repo)
wnameB1=$(expected_wname "$repoB" "SH-CWD-B1")
(
  cd "$repoB" || exit 1
  git branch "worktree-$wnameB1"
  git worktree add -q --detach ".claude/worktrees/$wnameB1"
) >/dev/null 2>&1

wnameB2=$(expected_wname "$repoB" "SH-CWD-B2")
outB=$( cd "$repoB/.claude/worktrees/$wnameB1" \
    && PATH="$FAKE_TMUX_DIR:$PATH" \
       TMUX="fake,0,0" TMUX_PANE="%0" \
       FAKE_STORY_STATE=in-progress \
       STORY_READY_DELAY=0 STORY_READY_FALLBACK_DELAY=0 \
       STORY_CONFIRM_DELAY=0 STORY_PASTE_SETTLE_DELAY=0 \
       FAKE_TMUX_CAPTURE=marker \
       bash "$SCRIPT" dispatch SH-CWD-B2 2>&1 )
assert_eq "$(jqf "$outB" .ok)" "true" "cwdB: ok:true"
assert_eq "$(jqf "$outB" .window_name)" "$wnameB2" "cwdB: window_name resolved against the MAIN repo"
assert_contains "$(jqf "$outB" .worktree_path)" "/.claude/worktrees/$wnameB2" \
  "cwdB: worktree_path's leaf is the new worktree's own name"
assert_not_contains "$(jqf "$outB" .worktree_path)" "/.claude/worktrees/$wnameB1/" \
  "cwdB: worktree_path must NOT be nested inside the CWD worktree"
[ -d "$repoB/.claude/worktrees/$wnameB2" ] \
  || fail_test "cwdB: new worktree missing at the main-repo-relative path"
[ ! -e "$repoB/.claude/worktrees/$wnameB1/.claude" ] \
  || fail_test "cwdB: new worktree must NOT be nested inside the CWD worktree on disk"
( cd "$repoB" && git show-ref --verify --quiet "refs/heads/worktree-$wnameB2" ) \
  || fail_test "cwdB: new worktree branch missing"

finish
