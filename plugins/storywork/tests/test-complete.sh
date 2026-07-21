#!/usr/bin/env bash
# story.sh complete — worktree/branch cleanup ONLY.
#
# Mirrors `issue.sh complete execute <n> --no-close`'s split: the actuator
# never touches story state (no `story move`, `story block`, anything) —
# conductor's own --if-state-guarded `story move <id> done` (Phase 2) is what
# actually closes the story, exactly as conductor removes the in-progress
# label itself today rather than delegating that to issue.sh. The scan is
# also deliberately narrower than issue.sh's collect_targets: no GitHub PR
# lookup (worktree-directory-name is storyhook's sole PR<->story linkage), so
# only the ONE worktree + `worktree-<wname>` branch this dispatch itself would
# have created is ever a candidate.
source "$(dirname "$0")/lib.sh"

# complete_real <repo-dir> <story-id> — run story.sh complete against
# <repo-dir>, echo the emitted JSON.
complete_real() {
  local dir="$1" id="$2"
  ( cd "$dir" && bash "$SCRIPT" complete "$id" 2>&1 )
}

expected_wname() {
  local repo="$1" id="$2" prefix
  prefix=$(basename "$repo" | tr -cd '[:alnum:]' | cut -c1-3 | tr '[:upper:]' '[:lower:]')
  printf '%s-%s' "$prefix" "$id"
}

# ==============================================================================
# Case 1: a removable worktree + a MERGED local branch — both get removed.
# ==============================================================================
repo1=$(mk_dispatch_repo)
wname1=$(expected_wname "$repo1" "SH-1")
log1=$(mktemp /tmp/storywork-log.XXXXXX)
(
  cd "$repo1" || exit 1
  git branch "worktree-$wname1"                       # merged (no commits of its own)
  git worktree add -q --detach ".claude/worktrees/$wname1"
) >/dev/null 2>&1

out1=$(FAKE_STORY_LOG="$log1" complete_real "$repo1" SH-1)
assert_eq "$(jqf "$out1" .ok)" "true" "case1: ok:true"
assert_contains "$(jqf "$out1" '.removed.worktrees | join(",")')" ".claude/worktrees/$wname1" \
  "case1: the clean worktree was removed"
assert_contains "$(jqf "$out1" '.removed.branches | join(",")')" "worktree-$wname1" \
  "case1: the merged local branch was removed"
[ ! -e "$repo1/.claude/worktrees/$wname1" ] || fail_test "case1: worktree directory still on disk"
( cd "$repo1" && git show-ref --verify --quiet "refs/heads/worktree-$wname1" ) \
  && fail_test "case1: merged branch still exists" || :
[ ! -s "$log1" ] || fail_test "case1: story.sh complete must never call the story CLI (log: $(cat "$log1"))"

# ==============================================================================
# Case 2: an UNMERGED local branch (own commit, never merged) is preserved,
# not deleted.
# ==============================================================================
repo2=$(mk_dispatch_repo)
wname2=$(expected_wname "$repo2" "SH-2")
(
  cd "$repo2" || exit 1
  git checkout -q -b "worktree-$wname2" main
  echo w > wfile; git add wfile; git commit -qm "wip"
  git checkout -q main
) >/dev/null 2>&1

out2=$(complete_real "$repo2" SH-2)
assert_eq "$(jqf "$out2" .ok)" "true" "case2: ok:true"
assert_eq "$(jqf "$out2" '.removed.branches | length')" "0" "case2: unmerged branch not removed"
assert_contains "$(jqf "$out2" '.skipped | join(",")')" "worktree-$wname2" \
  "case2: unmerged branch reported as skipped/preserved"
( cd "$repo2" && git show-ref --verify --quiet "refs/heads/worktree-$wname2" ) \
  || fail_test "case2: unmerged branch was wrongly deleted"

# ==============================================================================
# Case 3: current/locked/dirty worktrees are preserved, not removed.
# ==============================================================================
repo3=$(mk_dispatch_repo)
wname3_locked="$(expected_wname "$repo3" "SH-3")"
(
  cd "$repo3" || exit 1
  git branch "worktree-$wname3_locked"
  git worktree add -q --lock --detach ".claude/worktrees/$wname3_locked"
) >/dev/null 2>&1

out3=$(complete_real "$repo3" SH-3)
assert_eq "$(jqf "$out3" .ok)" "true" "case3: ok:true"
assert_eq "$(jqf "$out3" '.removed.worktrees | length')" "0" "case3: locked worktree not removed"
assert_contains "$(jqf "$out3" '.skipped | join(",")')" "locked" "case3: locked worktree reported skipped"
[ -e "$repo3/.claude/worktrees/$wname3_locked" ] || fail_test "case3: locked worktree wrongly removed"

# Dirty worktree, separate story id in the same repo.
repo3dirty=$(mk_dispatch_repo)
wname3_dirty="$(expected_wname "$repo3dirty" "SH-3D")"
(
  cd "$repo3dirty" || exit 1
  git branch "worktree-$wname3_dirty"
  git worktree add -q --detach ".claude/worktrees/$wname3_dirty"
  echo dirty > ".claude/worktrees/$wname3_dirty/untracked.txt"
) >/dev/null 2>&1

out3d=$(complete_real "$repo3dirty" SH-3D)
assert_eq "$(jqf "$out3d" .ok)" "true" "case3d: ok:true"
assert_eq "$(jqf "$out3d" '.removed.worktrees | length')" "0" "case3d: dirty worktree not removed"
assert_contains "$(jqf "$out3d" '.skipped | join(",")')" "dirty" "case3d: dirty worktree reported skipped"
[ -e "$repo3dirty/.claude/worktrees/$wname3_dirty" ] || fail_test "case3d: dirty worktree wrongly removed"

# ==============================================================================
# Case 4: nothing was ever dispatched for this id — no worktree, no branch.
# Must be a clean no-op, not an error.
# ==============================================================================
repo4=$(mk_dispatch_repo)

out4=$(complete_real "$repo4" SH-404)
assert_eq "$(jqf "$out4" .ok)" "true" "case4: ok:true (nothing to clean up is not an error)"
assert_eq "$(jqf "$out4" '.removed.worktrees | length')" "0" "case4: no worktrees removed"
assert_eq "$(jqf "$out4" '.removed.branches | length')" "0" "case4: no branches removed"

# ==============================================================================
# Case 5: STORY_DRY_RUN=1 — same removable-worktree + merged-branch setup as
# case 1, but under dry-run: story.sh must preview the removal (dry_run:true +
# a commands[] array) and perform NEITHER destructive side effect. Regression
# for a review finding: cmd_complete's two destructive branches (`git worktree
# remove`, the merged-branch delete) ran for real regardless of
# $STORY_DRY_RUN, unlike issue.sh's cmd_complete_execute, which gates every
# destructive branch on $DRY_RUN.
# ==============================================================================
repo5=$(mk_dispatch_repo)
wname5=$(expected_wname "$repo5" "SH-5")
(
  cd "$repo5" || exit 1
  git branch "worktree-$wname5"                       # merged (no commits of its own)
  git worktree add -q --detach ".claude/worktrees/$wname5"
) >/dev/null 2>&1

out5=$(cd "$repo5" && STORY_DRY_RUN=1 bash "$SCRIPT" complete SH-5 2>&1)
assert_eq "$(jqf "$out5" .ok)" "true" "case5: dry-run ok:true"
assert_eq "$(jqf "$out5" .dry_run)" "true" "case5: dry_run flag set"
cmds5=$(jqf "$out5" '.commands | join("\n")')
assert_contains "$cmds5" "git worktree remove" "case5: dry-run previews the worktree removal"
assert_contains "$cmds5" "worktree-$wname5" "case5: dry-run previews the branch delete"
# nothing actually happened — both destructive side effects are no-ops under dry-run:
[ -d "$repo5/.claude/worktrees/$wname5" ] || fail_test "case5: dry-run must NOT remove the worktree"
( cd "$repo5" && git show-ref --verify --quiet "refs/heads/worktree-$wname5" ) \
  || fail_test "case5: dry-run must NOT delete the merged branch"

finish
