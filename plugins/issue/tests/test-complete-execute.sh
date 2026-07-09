#!/usr/bin/env bash
# `complete execute <n>` — DESTRUCTIVE, but only on the safe set. Over the same
# realistic repo (mk_complete_repo), asserts execute closes the issue, removes the
# clean worktree + fully-merged branches (local & remote), and PRESERVES the
# unmerged branch, the locked worktree, and the default branch. Also covers
# ISSUE_DRY_RUN (previews commands, mutates nothing) and --no-close.
source "$(dirname "$0")/lib.sh"
export FAKE_GH_CLOSED_BY_PRS='[{"number":61}]'   # PR #61 (MERGED, head fix/thing-61) closed the issue

# ---------- dry-run first: previews everything, changes nothing ----------
repo=$(mk_complete_repo)
log=$(mktemp /tmp/issue-exec-log.XXXXXX)
out=$(cd "$repo" && ISSUE_DRY_RUN=1 FAKE_GH_LOG="$log" bash "$SCRIPT" complete execute 77 2>&1)
assert_eq "$(jqf "$out" .ok)" "true" "dry ok:true"
assert_eq "$(jqf "$out" .dry_run)" "true" "dry flag"
cmds=$(jqf "$out" '.commands|join("\n")')
assert_contains "$cmds" "gh issue close 77" "dry lists close"
assert_contains "$cmds" "git worktree remove" "dry lists worktree remove"
assert_contains "$cmds" "git branch -d worktree-rep-77" "dry lists local branch delete"
assert_contains "$cmds" "git push origin --delete fix/thing-61" "dry lists remote branch delete"
# nothing actually happened:
assert_not_contains "$(cat "$log")" "issue close" "dry did not call gh issue close"
( cd "$repo" && git show-ref --verify --quiet refs/heads/worktree-rep-77 ) \
  && echo "ok" >/dev/null || fail_test "dry preserved merged branch (still exists)"
[ -d "$repo/.claude/worktrees/rep-77" ] || fail_test "dry preserved rep-77 worktree"
rm -f "$log"

# ---------- real execute: acts on the safe set only ----------
repo=$(mk_complete_repo)
out=$(cd "$repo" && bash "$SCRIPT" complete execute 77 2>&1)
assert_eq "$(jqf "$out" .ok)" "true" "exec ok:true"
assert_eq "$(jqf "$out" .closed)" "true" "exec closed the issue (was OPEN)"

# removed: clean worktree + merged local branches + merged remote branch
assert_contains "$(jqf "$out" '.removed.worktrees|join(",")')" "/rep-77" "removed rep-77 worktree"
rl=$(jqf "$out" '.removed.branches_local|join(",")')
assert_contains "$rl" "worktree-rep-77" "removed merged worktree branch"
assert_contains "$rl" "fix/thing-61" "removed merged PR head (local)"
assert_contains "$(jqf "$out" '.removed.branches_remote|join(",")')" "fix/thing-61" "removed merged PR head (remote)"

# on-disk truth: the removed things are gone…
[ -d "$repo/.claude/worktrees/rep-77" ] && fail_test "rep-77 worktree still present" || :
( cd "$repo" && git show-ref --verify --quiet refs/heads/worktree-rep-77 ) \
  && fail_test "worktree-rep-77 branch still present" || :
( cd "$repo" && git show-ref --verify --quiet refs/heads/fix/thing-61 ) \
  && fail_test "fix/thing-61 local branch still present" || :
[ -z "$(cd "$repo" && git ls-remote --heads origin fix/thing-61 2>/dev/null)" ] \
  || fail_test "fix/thing-61 remote branch still present"

# …and the guarded things are PRESERVED
( cd "$repo" && git show-ref --verify --quiet refs/heads/worktree-77 ) \
  || fail_test "GUARD: unmerged branch worktree-77 was deleted"
[ -d "$repo/.claude/worktrees/77" ] \
  || fail_test "GUARD: locked worktree 77 was removed"
( cd "$repo" && git show-ref --verify --quiet refs/heads/main ) \
  || fail_test "GUARD: default branch main was deleted"

# ---------- --no-close: cleans up but leaves the issue open ----------
repo=$(mk_complete_repo)
out=$(cd "$repo" && bash "$SCRIPT" complete execute 77 --no-close 2>&1)
assert_eq "$(jqf "$out" .ok)" "true" "no-close ok:true"
assert_eq "$(jqf "$out" .closed)" "false" "no-close leaves issue open"
assert_contains "$(jqf "$out" '.removed.worktrees|join(",")')" "/rep-77" "no-close still cleans worktree"

# ---------- --no-clean (Close only): closes but deletes nothing ----------
repo=$(mk_complete_repo)
out=$(cd "$repo" && bash "$SCRIPT" complete execute 77 --no-clean 2>&1)
assert_eq "$(jqf "$out" .ok)" "true" "no-clean ok:true"
assert_eq "$(jqf "$out" .closed)" "true" "no-clean still closes the issue"
assert_eq "$(jqf "$out" '.removed.worktrees|length')" "0" "no-clean removes no worktrees"
assert_eq "$(jqf "$out" '.removed.branches_local|length')" "0" "no-clean removes no branches"
assert_contains "$(jqf "$out" .display)" "cleanup skipped" "no-clean display notes skip"
[ -d "$repo/.claude/worktrees/rep-77" ] || fail_test "no-clean must NOT remove the worktree"
( cd "$repo" && git show-ref --verify --quiet refs/heads/worktree-rep-77 ) \
  || fail_test "no-clean must NOT delete the merged branch"

finish
