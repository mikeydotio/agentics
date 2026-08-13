#!/usr/bin/env bash
# AGE-83: the fake tmux now derives and reports the pane's occupant — the
# fact `pane_runs` (AGE-83's next commit, porting storyhook's SH-226) checks
# before any prompt is typed. This file proves the fake's model directly,
# independent of issue.sh, the way test-fake-tmux-state.sh proves the state
# directory's isolation directly.
#
# issue.sh only ever TYPES its launch (send-keys -l + Enter) — it has no
# exec-launch equivalent to storyhook's SH-230 — so the occupant is always
# derived from the submitted launch line, never from new-window's own
# arguments.
source "$(dirname "$0")/lib.sh"

FAKE_TMUX="$TESTS_DIR/fakes/tmux"

occupant() { "$FAKE_TMUX" display-message -p '#{pane_current_command}'; }
launch() {
  "$FAKE_TMUX" new-window -d -P -F '#{pane_id}' >/dev/null
  "$FAKE_TMUX" send-keys -t %1 -l "$1" >/dev/null
  "$FAKE_TMUX" send-keys -t %1 Enter >/dev/null
}

# --- default derivation: the launch line's own basename ---------------------
launch "claude --permission-mode plan --model opusplan"
assert_eq "$(occupant)" "claude" "a normal launch derives its own basename as the occupant"

# --- a path-qualified launch is reduced to its basename ----------------------
launch "/usr/local/bin/claude --permission-mode plan"
assert_eq "$(occupant)" "claude" "a path-qualified launch derives the basename, not the full path"

# --- the SH-226 field cause: a mangled launch leaves a shell behind ----------
FAKE_TMUX_LAUNCH_MANGLE=1 bash -c '
  "$0" new-window -d -P -F "#{pane_id}" >/dev/null
  "$0" send-keys -t %1 -l "laude --permission-mode plan" >/dev/null
  "$0" send-keys -t %1 Enter >/dev/null
' "$FAKE_TMUX"
assert_eq "$(occupant)" "zsh" "a mangled launch leaves the fallback shell as the occupant, not claude"

# --- FAKE_TMUX_SHELL overrides the fallback shell name -----------------------
FAKE_TMUX_LAUNCH_MANGLE=1 FAKE_TMUX_SHELL=bash bash -c '
  "$0" new-window -d -P -F "#{pane_id}" >/dev/null
  "$0" send-keys -t %1 -l "laude" >/dev/null
  "$0" send-keys -t %1 Enter >/dev/null
' "$FAKE_TMUX"
assert_eq "$(occupant)" "bash" "FAKE_TMUX_SHELL names the fallback shell a mangled launch leaves"

# --- FAKE_TMUX_PANE_COMMAND overrides the occupant absolutely ---------------
launch "claude"
out="$(FAKE_TMUX_PANE_COMMAND=node occupant)"
assert_eq "$out" "node" "FAKE_TMUX_PANE_COMMAND overrides the derived occupant"

# --- new-window resets the occupant for the next launch ----------------------
launch "claude"
assert_eq "$(occupant)" "claude" "first launch derives claude"
FAKE_TMUX_LAUNCH_MANGLE=1 bash -c '
  "$0" new-window -d -P -F "#{pane_id}" >/dev/null
  "$0" send-keys -t %1 -l "laude" >/dev/null
  "$0" send-keys -t %1 Enter >/dev/null
' "$FAKE_TMUX"
assert_eq "$(occupant)" "zsh" "a second new-window in the same state dir replaces the prior occupant, not merges with it"

# --- FAKE_TMUX_FAIL_SEND_KEYS makes send-keys fail, as paste_text expects ----
"$FAKE_TMUX" new-window -d -P -F '#{pane_id}' >/dev/null
if FAKE_TMUX_FAIL_SEND_KEYS=literal "$FAKE_TMUX" send-keys -t %1 -l "claude" >/dev/null 2>&1; then
  fail_test "FAKE_TMUX_FAIL_SEND_KEYS=literal should make a literal send-keys fail"
fi
if FAKE_TMUX_FAIL_SEND_KEYS=enter "$FAKE_TMUX" send-keys -t %1 Enter >/dev/null 2>&1; then
  fail_test "FAKE_TMUX_FAIL_SEND_KEYS=enter should make an Enter send-keys fail"
fi

# --- a mangled launch's pane also carries the field evidence line -----------
state="$(mktemp -d /tmp/issue-occupant-test.XXXXXX)"
_TMP_REPOS+=("$state")
FAKE_TMUX_STATE="$state" FAKE_TMUX_LAUNCH_MANGLE=1 bash -c '
  "$0" new-window -d -P -F "#{pane_id}" >/dev/null
  "$0" send-keys -t %1 -l "laude" >/dev/null
  "$0" send-keys -t %1 Enter >/dev/null
' "$FAKE_TMUX"
cap="$(FAKE_TMUX_STATE="$state" "$FAKE_TMUX" capture-pane -p -t %1)"
assert_contains "$cap" "command not found" "a mangled launch's capture-pane carries the field evidence line"

finish
