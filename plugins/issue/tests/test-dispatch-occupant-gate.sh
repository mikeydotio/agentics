#!/usr/bin/env bash
# AGE-83, porting storyhook's SH-226: `dispatch` must refuse a pane that
# cannot be proved to be Claude, and type NOTHING into it. test-readiness.sh
# already flips the modal/busy/churn content-tier failures from warn-and-type
# to refuse-and-roll-back; this file drives the SH-226 field cause directly
# (a launch that never became claude/node at all) plus the escape hatch.
source "$(dirname "$0")/lib.sh"

FAKE_DIR="$TESTS_DIR/fakes"

# dispatch_run <n> <extra env...> — run a real dispatch of issue <n> against
# the fake tmux, leaving its JSON in $out. Not called in a command
# substitution: $repo and $FAKE_TMUX_STATE have to survive the call so the
# assertions can inspect the fake's own state and the repo's branches
# afterwards.
dispatch_run() {
  local n="$1"; shift
  repo=$(mk_dispatch_repo)
  out=$(cd "$repo" \
      && PATH="$FAKE_DIR:$PATH" \
         TMUX="fake,0,0" TMUX_PANE="%0" \
         ISSUE_LABEL="" \
         ISSUE_READY_DELAY=0 \
         ISSUE_CONFIRM_DELAY=0 ISSUE_PASTE_SETTLE_DELAY=0 \
         ISSUE_READY_ATTEMPTS=8 ISSUE_READY_STABLE_POLLS=2 \
         env "$@" \
         bash "$SCRIPT" dispatch "$n" 2>&1)
}

submits() { cat "$FAKE_TMUX_STATE/prompt_submits" 2>/dev/null || echo 0; }

# --- the field cause: a launch that never became claude/node ----------------
# FAKE_TMUX_LAUNCH_MANGLE=1 models SH-226's own field failure: something ate
# the launch keystroke, so the pane's occupant stays a shell. wait_ready's
# content tiers may still match the selected fixture, but pane_runs must
# refuse the occupant regardless — this is the fact SH-226 exists to check.
dispatch_run 50 FAKE_TMUX_LAUNCH_MANGLE=1 FAKE_TMUX_CAPTURE=structural
assert_eq "$(jqf "$out" .ok)" "false" "field cause: a pane that never became claude is refused"
assert_eq "$(jqf "$out" .reason)" "pane-not-ready" "field cause: refusal names the pane"
assert_eq "$(jqf "$out" .pane_command)" "zsh" "field cause: reports the actual occupant (a shell)"
assert_eq "$(jqf "$out" .wait_ready_reason)" "wrong-process" \
  "field cause: the content tier matched, but the occupant did not — 'wrong-process', not 'timeout'"
assert_eq "$(submits "$FAKE_TMUX_STATE")" "0" "field cause: NOTHING was typed into that pane"
assert_contains "$(jqf "$out" .display)" "Nothing was typed" "field cause: display says nothing was typed"

# --- rollback: the worktree and branch are removed on refusal ---------------
wt_leaf=$(jqf "$out" .window_name)
assert_eq "$([ -d "$repo/.claude/worktrees/$wt_leaf" ] && echo yes || echo no)" "no" \
  "field cause: the worktree directory was rolled back"
assert_eq "$(git -C "$repo" show-ref --verify --quiet "refs/heads/worktree-$wt_leaf" && echo yes || echo no)" "no" \
  "field cause: the worktree branch was rolled back"

# --- the window is left standing as evidence ---------------------------------
assert_contains "$(jqf "$out" .display)" "left open" "field cause: the window itself is NOT torn down"
assert_eq "$(jqf "$out" 'has("pane_tail")')" "true" "field cause: pane_tail evidence rides the refusal"
assert_contains "$(jqf "$out" .pane_tail)" "command not found" \
  "field cause: pane_tail carries the shell's own command-not-found line"

# --- the escape hatch: '.' restores the pre-fix behaviour --------------------
# ISSUE_READY_PROCESS_PATTERN='.' matches any occupant name, including a
# mangled launch's fallback shell — the documented override for an
# environment where Claude reports an unexpected name.
dispatch_run 51 FAKE_TMUX_LAUNCH_MANGLE=1 FAKE_TMUX_CAPTURE=structural \
  ISSUE_READY_PROCESS_PATTERN='.'
assert_eq "$(jqf "$out" .ok)" "true" "escape hatch: '.' lets a shell-occupied pane through"
assert_eq "$(jqf "$out" .readiness_confirmed)" "true" "escape hatch: readiness reads confirmed"

finish
