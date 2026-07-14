#!/usr/bin/env bash
# issue #87: `issue capture <n>` — a READ-ONLY peek at the live tmux window for a
# dispatched issue. It dumps that window's rendered transcript (tmux capture-pane
# -S) so you can confirm what the worktree session received — e.g. that a
# multi-line prompt landed as ONE submitted message, the #87 live-confirmation.
#
# Driven against the stateful fake tmux: FAKE_TMUX_PANES seeds the window->pane
# table `list-panes -a` returns; FAKE_TMUX_TRANSCRIPT seeds what `capture-pane -S`
# returns. mk_repo's origin resolves to fake/repo, so issue N's window is "rep-N".
source "$(dirname "$0")/lib.sh"

FAKE_DIR="$TESTS_DIR/fakes"

# run_capture <repo-dir> <issue> [extra env KEY=VAL ...] — run `issue capture`
# with the fake tmux on PATH and a dummy $TMUX. Echoes the emitted JSON.
run_capture() {
  local dir="$1" n="$2"; shift 2
  ( cd "$dir" \
      && PATH="$FAKE_DIR:$PATH" TMUX="fake,0,0" TMUX_PANE="%0" \
         env "$@" bash "$SCRIPT" capture "$n" 2>&1 )
}

# --- dry-run: reports the single read-only command, opens nothing -------------
repo=$(mk_repo)
out=$(run_capture "$repo" 42 ISSUE_DRY_RUN=1)
assert_eq "$(jqf "$out" .ok)" "true" "dryrun: ok:true"
assert_eq "$(jqf "$out" .dry_run)" "true" "dryrun: dry_run flag"
assert_eq "$(jqf "$out" .window_name)" "rep-42" "dryrun: window is <repo-prefix>-<n>"
assert_contains "$(jqf "$out" '.commands|join("\n")')" \
  "capture-pane -p -t <pane-of rep-42> -S -200" "dryrun: lists the read-only capture command"

# --- happy path: resolves the target window's active pane, dumps its transcript
# Seed a decoy + the target window, and a transcript showing a multi-line prompt
# submitted as ONE message (the #87 live-confirmation shape).
tx=$(printf '> issue-do handoff\nml-first\nml-middle\nml-last\n\n* Working on it')
out=$(run_capture "$repo" 42 \
      "FAKE_TMUX_PANES=$(printf 'other-9\t1\t%%10\nrep-42\t1\t%%77')" \
      "FAKE_TMUX_TRANSCRIPT=$tx")
assert_eq "$(jqf "$out" .ok)" "true" "happy: ok:true"
assert_eq "$(jqf "$out" .window_name)" "rep-42" "happy: window_name"
assert_eq "$(jqf "$out" .pane)" "%77" "happy: resolved the target window's active pane"
assert_contains "$(jqf "$out" .transcript)" "ml-first" "happy: transcript carries the FIRST prompt line"
assert_contains "$(jqf "$out" .transcript)" "ml-last" "happy: transcript carries the LAST line — multi-line landed as one message"
assert_contains "$(jqf "$out" .display)" "ml-middle" "happy: display renders the transcript"

# --- window not dispatched: honest ok:false -----------------------------------
out=$(run_capture "$repo" 42 "FAKE_TMUX_PANES=")
assert_eq "$(jqf "$out" .ok)" "false" "missing: ok:false when no window matches"
assert_contains "$(jqf "$out" .display)" "no live tmux window" "missing: clear display"

# --- bad issue number -> usage ------------------------------------------------
out=$(run_capture "$repo" abc)
assert_eq "$(jqf "$out" .ok)" "false" "badnum: ok:false"
assert_contains "$(jqf "$out" .display)" "usage" "badnum: usage display"

# --- no tmux -> hard precondition (unset ambient $TMUX explicitly) -------------
out=$( cd "$repo" && PATH="$FAKE_DIR:$PATH" env -u TMUX -u TMUX_PANE bash "$SCRIPT" capture 42 2>&1 )
assert_eq "$(jqf "$out" .ok)" "false" "notmux: ok:false without \$TMUX"
assert_contains "$(jqf "$out" .display)" "requires tmux" "notmux: clear display"

finish
