#!/usr/bin/env bash
# issue #82: `/issue do` must reliably RECEIVE the handoff prompt into the new
# window's input box and SUBMIT it — even when the TUI intermittently absorbs the
# Enter that immediately follows a bulk paste (bracketed-paste race), and without
# ever re-pasting (which would duplicate the prompt) or falsely reporting success
# when nothing landed.
#
# These drive a REAL (non-dry-run) dispatch headlessly against the state-driven
# fake tmux (tests/fakes/tmux), which now models the input box: `send-keys -l`
# fills it, `send-keys Enter` submits it, FAKE_TMUX_ENTER_ABSORB=N absorbs the
# next N prompt Enters (the #82 race), and FAKE_TMUX_DROP_PASTE=1 drops a paste.
# Every paste is logged to $STATE/pastes.log so we can prove the prompt was
# pasted exactly once (no duplicate on the submit retry) or the bounded re-paste
# count on a genuinely dropped paste.
#
# Mirrors test-readiness.sh's real-dispatch harness (fake tmux/gh on PATH, dummy
# $TMUX/$TMUX_PANE, labeling disabled, all poll/settle delays zeroed) but pins a
# short, distinctive ISSUE_PROMPT so paste occurrences are trivial to count, and
# points FAKE_TMUX_STATE at a per-case temp dir so the box + pastes.log can be
# inspected after the run.
source "$(dirname "$0")/lib.sh"

FAKE_DIR="$TESTS_DIR/fakes"

# dispatch_autosubmit <repo> <issue> <state-dir> [extra env KEY=VAL ...] — run a
# real dispatch with the fake tmux in its stateful `marker` (ready) mode and a
# deterministic one-line prompt "autosubmit-probe-<n>". Echoes the emitted JSON.
dispatch_autosubmit() {
  local dir="$1" n="$2" state="$3"; shift 3
  ( cd "$dir" \
      && PATH="$FAKE_DIR:$PATH" \
         TMUX="fake,0,0" TMUX_PANE="%0" \
         ISSUE_LABEL="" \
         FAKE_TMUX_CAPTURE="marker" \
         FAKE_TMUX_STATE="$state" \
         ISSUE_PROMPT='autosubmit-probe-<n>' \
         ISSUE_READY_DELAY=0 ISSUE_READY_FALLBACK_DELAY=0 \
         ISSUE_CONFIRM_DELAY=0 ISSUE_PASTE_SETTLE_DELAY=0 \
         ISSUE_READY_ATTEMPTS=8 ISSUE_READY_STABLE_POLLS=2 \
         env "$@" \
         bash "$SCRIPT" dispatch "$n" 2>&1 )
}

# count_pastes <state-dir> <pattern> — how many times <pattern> was pasted.
count_pastes() {
  local f="$1/pastes.log"
  [ -f "$f" ] || { printf '0'; return; }
  grep -c "$2" "$f" 2>/dev/null
}

# box_content <state-dir> — the current (post-run) input-box contents ('' if the
# box was submitted/cleared).
box_content() { cat "$1/input" 2>/dev/null || printf ''; }

# prompt_submits <state-dir> — how many PROMPT-phase submits the fake recorded
# (issue #87). A prompt delivered as one bracketed paste submits exactly once; a
# multi-line prompt sent via `send-keys -l` submits once per embedded newline.
prompt_submits() { cat "$1/prompt_submits" 2>/dev/null || printf '0'; }

# submitted <state-dir> — the content of the LAST prompt submit (the whole
# multi-line prompt when it landed as one block; only its final line when it was
# split at a newline).
submitted() { cat "$1/submitted" 2>/dev/null || printf ''; }

# --- Case 1: happy path — Enter submits first try, single paste ----------------
# absorb=0: the prompt is received and the very first Enter submits it. Guards the
# common path — must stay green before and after the fix.
repo=$(mk_repo)
state=$(mktemp -d /tmp/issue-autosub.XXXXXX)
out=$(dispatch_autosubmit "$repo" 42 "$state")
assert_eq "$(jqf "$out" .ok)" "true" "happy: ok:true"
assert_eq "$(jqf "$out" .prompt_confirmed)" "true" "happy: prompt_confirmed"
assert_eq "$(jqf "$out" 'has("warning")')" "false" "happy: no warning"
assert_eq "$(count_pastes "$state" 'autosubmit-probe-42')" "1" "happy: prompt pasted exactly once"
assert_eq "$(box_content "$state")" "" "happy: input box cleared (submitted)"
rm -rf "$state"

# --- Case 2: absorbed Enter recovered by re-sending ENTER ALONE (no re-paste) ---
# absorb=1: the first prompt Enter is swallowed by the settling paste (the #82
# race). The fix must recover by re-sending Enter — NOT by re-pasting the prompt.
# The old code re-pastes on retry, duplicating the prompt: this asserts EXACTLY
# one paste, so it fails (RED) until the fix lands.
repo=$(mk_repo)
state=$(mktemp -d /tmp/issue-autosub.XXXXXX)
out=$(dispatch_autosubmit "$repo" 43 "$state" FAKE_TMUX_ENTER_ABSORB=1)
assert_eq "$(jqf "$out" .prompt_confirmed)" "true" "absorb1: confirmed after Enter-only retry"
assert_eq "$(jqf "$out" 'has("warning")')" "false" "absorb1: no warning once submitted"
assert_eq "$(count_pastes "$state" 'autosubmit-probe-43')" "1" "absorb1: prompt pasted EXACTLY once (no duplicate on retry)"
assert_eq "$(box_content "$state")" "" "absorb1: input box cleared (submitted)"
rm -rf "$state"

# --- Case 3: dead input → honest give-up, receipt pasted once ------------------
# absorb=99 exhausts every retry: the prompt is received but never submits. The
# fix must report prompt_confirmed:false + a warning, and — since receipt WAS
# confirmed — must NOT re-paste (only re-send Enter). The old code re-pastes on
# each retry (3 pastes with SEND_RETRIES=2): assert one paste (RED until fixed).
repo=$(mk_repo)
state=$(mktemp -d /tmp/issue-autosub.XXXXXX)
out=$(dispatch_autosubmit "$repo" 44 "$state" FAKE_TMUX_ENTER_ABSORB=99 ISSUE_SEND_RETRIES=2)
assert_eq "$(jqf "$out" .prompt_confirmed)" "false" "dead: prompt_confirmed:false (never submitted)"
assert_eq "$(jqf "$out" 'has("warning")')" "true" "dead: warning present"
assert_eq "$(jqf "$out" 'has("pane_tail")')" "true" "dead: pane_tail evidence present"
assert_eq "$(count_pastes "$state" 'autosubmit-probe-44')" "1" "dead: receipt confirmed → prompt pasted ONCE (only Enter retried)"
assert_contains "$(box_content "$state")" "autosubmit-probe-44" "dead: prompt still sits unsubmitted in the box"
rm -rf "$state"

# --- Case 4: dropped paste → receipt never confirms, bounded re-paste ----------
# The paste never reaches the box (a wedged/dropped send). Receipt confirmation
# must fail and the prompt must be RE-PASTED (bounded by SEND_RETRIES), reporting
# prompt_confirmed:false. The old code has no receipt phase and its vacuous
# last-line check reads the footer, so it FALSELY reports prompt_confirmed:true
# after a single (dropped) paste — this case proves that vacuous-confirm hole.
repo=$(mk_repo)
state=$(mktemp -d /tmp/issue-autosub.XXXXXX)
out=$(dispatch_autosubmit "$repo" 45 "$state" FAKE_TMUX_DROP_PASTE=1 ISSUE_SEND_RETRIES=2)
assert_eq "$(jqf "$out" .prompt_confirmed)" "false" "drop: prompt_confirmed:false (paste never landed)"
assert_eq "$(jqf "$out" 'has("warning")')" "true" "drop: warning present"
assert_eq "$(count_pastes "$state" 'autosubmit-probe-45')" "3" "drop: prompt re-pasted SEND_RETRIES+1 = 3 times"
rm -rf "$state"

# --- Case 5: a MULTI-LINE prompt must land as ONE submission (issue #87) --------
# `send-keys -l` sends an embedded newline as a literal Enter, so a multi-line
# ISSUE_PROMPT would be SUBMITTED at its first newline (the rest typed into a fresh
# prompt). The fix delivers the prompt as one bracketed paste (load-buffer +
# paste-buffer -p), so every line lands together and a single trailing Enter
# submits the whole thing. This asserts EXACTLY one prompt submit whose content
# holds both the first and last lines: RED with `send-keys -l` (splits →
# prompt_submits==3, submitted holds only the last line), GREEN with the buffer
# paste. dispatch_autosubmit's `env "$@"` overrides its fixed one-line probe.
repo=$(mk_repo)
state=$(mktemp -d /tmp/issue-autosub.XXXXXX)
out=$(dispatch_autosubmit "$repo" 46 "$state" \
      "ISSUE_PROMPT=$(printf 'ml-first-<n>\nml-middle\nml-last-<n>')")
assert_eq "$(jqf "$out" .ok)" "true" "multiline: ok:true"
assert_eq "$(jqf "$out" .prompt_confirmed)" "true" "multiline: prompt_confirmed"
assert_eq "$(jqf "$out" 'has("warning")')" "false" "multiline: no warning"
assert_eq "$(prompt_submits "$state")" "1" "multiline: submitted exactly ONCE (no premature submit at a newline)"
assert_contains "$(submitted "$state")" "ml-first-46" "multiline: the submission holds the FIRST line"
assert_contains "$(submitted "$state")" "ml-last-46" "multiline: the submission holds the LAST line"
assert_eq "$(box_content "$state")" "" "multiline: input box cleared (submitted)"
assert_eq "$(count_pastes "$state" 'ml-first-46')" "1" "multiline: prompt delivered exactly once"
rm -rf "$state"

finish
