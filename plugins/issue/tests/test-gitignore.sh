#!/usr/bin/env bash
# issue #55: dispatch idempotently gitignores the per-issue worktree dir
# (.claude/worktrees/) so `claude -w` doesn't dirty the parent repo's git status.
#
# Unlike the other suites, these drive a REAL (non-dry-run) dispatch headlessly:
# a fake `tmux` (tests/fakes/tmux) prepended on PATH satisfies Steps 5-8 without
# a live tmux server, dummy $TMUX/$TMUX_PANE pass the Step-1 precondition, the
# fake `gh` answers issue lookups, and labeling is disabled (ISSUE_LABEL="")
# to keep the run focused on the gitignore write. All poll delays are zeroed so
# the run returns immediately.
source "$(dirname "$0")/lib.sh"

FAKE_TMUX_DIR="$TESTS_DIR/fakes"
RULE=".claude/worktrees/"

# dispatch_real <repo-dir> <issue> — run a real (non-dry-run) dispatch against
# <repo-dir> with the fake tmux/gh wired in, and echo the emitted JSON.
dispatch_real() {
  local dir="$1" n="$2"
  ( cd "$dir" \
      && PATH="$FAKE_TMUX_DIR:$PATH" \
         TMUX="fake,0,0" TMUX_PANE="%0" \
         ISSUE_LABEL="" \
         ISSUE_READY_DELAY=0 ISSUE_READY_FALLBACK_DELAY=0 \
         ISSUE_CONFIRM_DELAY=0 ISSUE_PASTE_SETTLE_DELAY=0 \
         bash "$SCRIPT" dispatch "$n" 2>&1 )
}

# --- (a) fresh repo: the rule is added and the dir is genuinely ignored -------
repo=$(mk_dispatch_repo)
out=$(dispatch_real "$repo" 42)
assert_eq "$(jqf "$out" .ok)" "true" "fresh: ok:true"
assert_eq "$(jqf "$out" .gitignore)" "added" "fresh: gitignore reports added"
assert_contains "$(cat "$repo/.gitignore")" "$RULE" "fresh: rule written to .gitignore"
( cd "$repo" && git check-ignore -q ".claude/worktrees/42" ) \
  && : || fail_test "fresh: git check-ignore does not ignore the worktree leaf"
# issue #107: dispatch now genuinely CREATES the worktree (git worktree add),
# so this is the first point #55's end-to-end guarantee is actually testable —
# the real worktree dir must not show up as untracked in git status.
assert_not_contains "$(cd "$repo" && git status --porcelain)" ".claude/worktrees" \
  "fresh: real worktree dir does not appear in git status (genuinely ignored)"

# --- (b) idempotency: a second dispatch is a no-op, no duplicate line ---------
out=$(dispatch_real "$repo" 43)
assert_eq "$(jqf "$out" .ok)" "true" "second: ok:true"
assert_eq "$(jqf "$out" .gitignore)" "already-ignored" "second: reports already-ignored"
count=$(grep -cxF "$RULE" "$repo/.gitignore")
assert_eq "$count" "1" "second: rule present exactly once (no duplicate)"

# --- (c) pre-existing broad `.claude/` rule: file left byte-for-byte untouched -
broad=$(mk_dispatch_repo)
printf 'node_modules/\n.claude/\n' > "$broad/.gitignore"
before=$(cat "$broad/.gitignore")
out=$(dispatch_real "$broad" 7)
assert_eq "$(jqf "$out" .gitignore)" "already-ignored" "broad: reports already-ignored"
assert_eq "$(cat "$broad/.gitignore")" "$before" "broad: .gitignore left unmodified"

# --- (d) .gitignore with no trailing newline: appended cleanly ----------------
nonl=$(mk_dispatch_repo)
printf 'node_modules/' > "$nonl/.gitignore"   # deliberately no trailing \n
out=$(dispatch_real "$nonl" 9)
assert_eq "$(jqf "$out" .gitignore)" "added" "no-newline: gitignore added"
# The pre-existing entry and the rule must each be intact on their own line.
assert_eq "$(grep -cxF 'node_modules/' "$nonl/.gitignore")" "1" "no-newline: prior entry intact on its own line"
assert_eq "$(grep -cxF "$RULE" "$nonl/.gitignore")" "1" "no-newline: rule on its own line"
( cd "$nonl" && git check-ignore -q ".claude/worktrees/9" ) \
  && : || fail_test "no-newline: worktree leaf ignored after append"

# --- (e) failure path: an unwritable .gitignore degrades to add-failed, ok:true
# Skip under root, which bypasses file permission bits.
if [ "$(id -u)" != "0" ]; then
  ro=$(mk_dispatch_repo)
  printf 'node_modules/\n' > "$ro/.gitignore"
  chmod 0444 "$ro/.gitignore"
  out=$(dispatch_real "$ro" 11)
  assert_eq "$(jqf "$out" .ok)" "true" "unwritable: ok stays true (never ok:false)"
  assert_eq "$(jqf "$out" .gitignore)" "add-failed" "unwritable: reports add-failed"
  chmod 0644 "$ro/.gitignore"   # let cleanup rm it
fi

finish
