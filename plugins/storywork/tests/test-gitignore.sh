#!/usr/bin/env bash
# agentics issue #55 (session.sh header, `cmd_dispatch` Step 5): dispatch
# idempotently gitignores the per-story worktree container (.claude/worktrees/)
# so a daemon-managed repo's own worktrees never pollute `git status`.
# Mirrors plugins/issue/tests/test-gitignore.sh case-for-case, retargeted at
# `story.sh dispatch` — this call site shares the exact same session.sh
# `worktree_ignore_status`/`append_worktree_ignore` helpers but, pre-this-test,
# had NO coverage of its own: mutation-testing story.sh (deleting the whole
# Step 5 body) left the full storywork suite green.
source "$(dirname "$0")/lib.sh"

FAKE_TMUX_DIR="$TESTS_DIR/fakes"
RULE=".claude/worktrees/"

# dispatch_real <repo-dir> <story-id> — run a real (non-dry-run) dispatch
# against <repo-dir> with the fake tmux/story wired in, echo the emitted JSON.
# FAKE_STORY_STATE=in-progress throughout: these cases are about gitignore
# hygiene, not claim semantics (already covered by test-dispatch.sh).
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

# --- (a) fresh repo: the rule is added and the dir is genuinely ignored -------
repo=$(mk_dispatch_repo)
out=$(dispatch_real "$repo" SH-42)
assert_eq "$(jqf "$out" .ok)" "true" "fresh: ok:true"
assert_eq "$(jqf "$out" .gitignore)" "added" "fresh: gitignore reports added"
assert_contains "$(cat "$repo/.gitignore")" "$RULE" "fresh: rule written to .gitignore"
wname42=$(basename "$repo" | tr -cd '[:alnum:]' | cut -c1-3 | tr '[:upper:]' '[:lower:]')-SH-42
( cd "$repo" && git check-ignore -q ".claude/worktrees/$wname42" ) \
  && : || fail_test "fresh: git check-ignore does not ignore the worktree leaf"
# The real worktree dir (dispatch genuinely creates one) must not appear as
# untracked in git status — the actual end-to-end guarantee #55 exists for.
assert_not_contains "$(cd "$repo" && git status --porcelain)" ".claude/worktrees" \
  "fresh: real worktree dir does not appear in git status (genuinely ignored)"

# --- (b) idempotency: a second dispatch is a no-op, no duplicate line ---------
out=$(dispatch_real "$repo" SH-43)
assert_eq "$(jqf "$out" .ok)" "true" "second: ok:true"
assert_eq "$(jqf "$out" .gitignore)" "already-ignored" "second: reports already-ignored"
count=$(grep -cxF "$RULE" "$repo/.gitignore")
assert_eq "$count" "1" "second: rule present exactly once (no duplicate)"

# --- (c) pre-existing broad `.claude/` rule: file left byte-for-byte untouched -
broad=$(mk_dispatch_repo)
printf 'node_modules/\n.claude/\n' > "$broad/.gitignore"
before=$(cat "$broad/.gitignore")
out=$(dispatch_real "$broad" SH-7)
assert_eq "$(jqf "$out" .ok)" "true" "broad: ok:true"
assert_eq "$(jqf "$out" .gitignore)" "already-ignored" "broad: reports already-ignored"
assert_eq "$(cat "$broad/.gitignore")" "$before" "broad: .gitignore left unmodified"

# --- (d) .gitignore with no trailing newline: appended cleanly ----------------
nonl=$(mk_dispatch_repo)
printf 'node_modules/' > "$nonl/.gitignore"   # deliberately no trailing \n
out=$(dispatch_real "$nonl" SH-9)
assert_eq "$(jqf "$out" .ok)" "true" "no-newline: ok:true"
assert_eq "$(jqf "$out" .gitignore)" "added" "no-newline: gitignore added"
# The pre-existing entry and the new rule must each be intact on their own line.
assert_eq "$(grep -cxF 'node_modules/' "$nonl/.gitignore")" "1" "no-newline: prior entry intact on its own line"
assert_eq "$(grep -cxF "$RULE" "$nonl/.gitignore")" "1" "no-newline: rule on its own line"
wname9=$(basename "$nonl" | tr -cd '[:alnum:]' | cut -c1-3 | tr '[:upper:]' '[:lower:]')-SH-9
( cd "$nonl" && git check-ignore -q ".claude/worktrees/$wname9" ) \
  && : || fail_test "no-newline: worktree leaf ignored after append"

# --- (e) failure path: an unwritable .gitignore degrades to add-failed, ok:true
# Skip under root, which bypasses file permission bits.
if [ "$(id -u)" != "0" ]; then
  ro=$(mk_dispatch_repo)
  printf 'node_modules/\n' > "$ro/.gitignore"
  chmod 0444 "$ro/.gitignore"
  out=$(dispatch_real "$ro" SH-11)
  assert_eq "$(jqf "$out" .ok)" "true" "unwritable: ok stays true (gitignore hygiene is best-effort)"
  assert_eq "$(jqf "$out" .gitignore)" "add-failed" "unwritable: reports add-failed"
  chmod 0644 "$ro/.gitignore"   # let cleanup rm it
fi

finish
