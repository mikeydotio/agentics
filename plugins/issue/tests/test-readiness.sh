#!/usr/bin/env bash
# issue #67: the readiness gate must survive Claude-Code footer-copy drift.
# Before the fix, wait_ready() confirmed readiness only when the pane matched a
# single version-specific string ("for shortcuts"); the current build no longer
# renders it, so EVERY dispatch degraded to a false-negative warning. These tests
# drive a REAL (non-dry-run) dispatch headlessly against a state-driven fake tmux
# (tests/fakes/tmux, selected via FAKE_TMUX_CAPTURE) to exercise both readiness
# tiers, the warning + pane_tail evidence path, and the drift-proof.
#
# Mirrors test-gitignore.sh's real-dispatch harness: fake tmux/gh on PATH, dummy
# $TMUX/$TMUX_PANE, labeling disabled, poll delays zeroed, and a small
# READY_ATTEMPTS so the never-ready cases return fast.
source "$(dirname "$0")/lib.sh"

FAKE_DIR="$TESTS_DIR/fakes"

# dispatch_ready <repo> <issue> <capture-mode> [extra env KEY=VAL ...] — run a
# real dispatch with the fake tmux's capture-pane set to <capture-mode>, echo the
# emitted JSON. READY_STABLE_POLLS=2 keeps the structural tier fast (3 identical
# captures); READY_ATTEMPTS=8 bounds the never-ready cases. Extra "$@" KEY=VAL
# pairs are applied via `env` — a variable that expands to `name=value` is NOT
# recognized as a shell assignment prefix, so it must go through env(1).
dispatch_ready() {
  local dir="$1" n="$2" mode="$3"; shift 3
  ( cd "$dir" \
      && PATH="$FAKE_DIR:$PATH" \
         TMUX="fake,0,0" TMUX_PANE="%0" \
         ISSUE_LABEL="" \
         FAKE_TMUX_CAPTURE="$mode" \
         ISSUE_READY_DELAY=0 \
         ISSUE_CONFIRM_DELAY=0 ISSUE_PASTE_SETTLE_DELAY=0 \
         ISSUE_READY_ATTEMPTS=8 ISSUE_READY_STABLE_POLLS=2 \
         env "$@" \
         bash "$SCRIPT" dispatch "$n" 2>&1 )
}

# submits <state-dir> — the prompt-submit counter the fake tracks, 0 if never
# written. Used by the AGE-83 (SH-226) refusal cases below to prove nothing
# was typed into an unconfirmed pane — the launch command itself always types
# (Step 9, before the gate), but a PROMPT submit must never happen.
submits() { cat "$1/prompt_submits" 2>/dev/null || echo 0; }

# --- T1: broadened footer marker (no "for shortcuts") → ready, no warning ------
# The `marker` fake renders a plan-mode idle pane whose footer says
# "plan mode on (shift+tab to cycle)" and does NOT contain "for shortcuts". The
# broadened default READY_PATTERN matches it via "mode on"/"to cycle".
repo=$(mk_dispatch_repo)
out=$(dispatch_ready "$repo" 42 marker)
assert_eq "$(jqf "$out" .ok)" "true" "T1 marker: ok:true"
assert_eq "$(jqf "$out" .readiness_confirmed)" "true" "T1 marker: readiness confirmed via broadened marker"
assert_eq "$(jqf "$out" 'has("warning")')" "false" "T1 marker: NO warning (the #67 regression)"
assert_not_contains "$out" "for shortcuts" "T1 marker: confirmed without the stale 'for shortcuts' string"

# --- T2: fully drifted footer, structural tier (frame + glyph + stabilise) -----
# The `structural` fake has the input-box frame '─' AND the idle glyph '❯' but a
# footer matching NONE of the known markers → readiness must come from the
# structural tier once the static pane stabilises.
repo=$(mk_dispatch_repo)
out=$(dispatch_ready "$repo" 43 structural)
assert_eq "$(jqf "$out" .readiness_confirmed)" "true" "T2 structural: readiness confirmed with no known footer marker"
assert_eq "$(jqf "$out" 'has("warning")')" "false" "T2 structural: NO warning"

# --- T2-guard: framed static MODAL (frame but no idle glyph) → REFUSED (AGE-83) -
# The `modal` fake draws '─' rules (a trust dialog) but has NO '❯' idle glyph.
# The structural tier must refuse to confirm — and since AGE-83 (porting
# storyhook's SH-226), an unconfirmed pane now gets NO text at all: the
# handoff prompt is never typed into a modal, and the gate refuses outright
# rather than warning-and-proceeding.
repo=$(mk_dispatch_repo)
out=$(dispatch_ready "$repo" 44 modal)
assert_eq "$(jqf "$out" .ok)" "false" "T2-guard modal: framed static modal is refused, not warned"
assert_eq "$(jqf "$out" .reason)" "pane-not-ready" "T2-guard modal: refusal names the pane"
assert_eq "$(submits "$FAKE_TMUX_STATE")" "0" "T2-guard modal: NOTHING was typed into that pane"

# --- T5: busy marker ("esc to interrupt") must NOT fast-path confirm -----------
# "esc to interrupt" is a BUSY marker (Claude generating), not idle-ready. It is
# deliberately absent from READY_PATTERN, and the busy fake has no frame/glyph, so
# neither tier should confirm — and AGE-83 refuses rather than warns.
repo=$(mk_dispatch_repo)
out=$(dispatch_ready "$repo" 45 busy)
assert_eq "$(jqf "$out" .ok)" "false" "T5 busy: 'esc to interrupt' is not treated as idle-ready, and is refused"
assert_eq "$(submits "$FAKE_TMUX_STATE")" "0" "T5 busy: NOTHING was typed into that pane"

# --- T3: never-ready churn → refused, nothing typed, evidence attached (AGE-83) -
# The `churn` fake changes content every capture (a counter), with no marker and
# no frame → readiness never confirms. Before AGE-83 this degraded to ok:true
# with a warning and the prompt typed anyway; now it refuses like every other
# unconfirmed case, and the pane_tail evidence rides the refusal's own JSON.
repo=$(mk_dispatch_repo)
state=$(mktemp -d /tmp/issue-churn.XXXXXX)
out=$(dispatch_ready "$repo" 46 churn FAKE_TMUX_STATE="$state")
assert_eq "$(jqf "$out" .ok)" "false" "T3 churn: refused, not warned"
assert_eq "$(jqf "$out" .reason)" "pane-not-ready" "T3 churn: refusal names the pane"
assert_eq "$(submits "$state")" "0" "T3 churn: NOTHING was typed into that pane"
assert_eq "$(jqf "$out" 'has("pane_tail")')" "true" "T3 churn: pane_tail evidence present"
assert_contains "$(jqf "$out" .pane_tail)" "building worktree" "T3 churn: pane_tail carries the captured pane content"
rm -rf "$state"

# --- T4: legacy '? for shortcuts' still confirms (back-compat) -----------------
# The fake's DEFAULT (no FAKE_TMUX_CAPTURE) is the legacy "  ? for shortcuts"
# line — the broadened READY_PATTERN still matches it, so old builds keep working.
repo=$(mk_dispatch_repo)
out=$(dispatch_ready "$repo" 47 legacy)
assert_eq "$(jqf "$out" .readiness_confirmed)" "true" "T4 legacy: '? for shortcuts' still confirms readiness"
assert_eq "$(jqf "$out" 'has("warning")')" "false" "T4 legacy: no warning"

# --- T6: a no-warning (success) dispatch carries NO pane_tail key --------------
# Locks the success payload: pane_tail must be warning-only so the byte-stable
# success JSON can't drift and break the dryrun/gitignore contract assertions.
repo=$(mk_dispatch_repo)
out=$(dispatch_ready "$repo" 48 marker)
assert_eq "$(jqf "$out" 'has("pane_tail")')" "false" "T6 success: no pane_tail on the clean success payload"
assert_eq "$(jqf "$out" 'has("prompt_accepted")')" "true" "T6 success: prompt_accepted field always present"

# --- Drift-proof: readiness survives a fully missing footer marker -------------
# Force READY_PATTERN to match nothing; the `marker` capture still has the frame
# '─' and idle glyph '❯', so the STRUCTURAL tier must carry readiness. This is the
# core #67 guarantee: readiness no longer depends on ANY footer copy.
repo=$(mk_dispatch_repo)
out=$(dispatch_ready "$repo" 49 marker ISSUE_READY_PATTERN='__no_such_marker__')
assert_eq "$(jqf "$out" .readiness_confirmed)" "true" "drift-proof: structural tier confirms with READY_PATTERN matching nothing"
assert_eq "$(jqf "$out" 'has("warning")')" "false" "drift-proof: no warning"

# --- doctor: dry-run lists the scratch-window commands and never touches gh ----
repo=$(mk_repo)
out=$(cd "$repo" && ISSUE_DRY_RUN=1 \
      ISSUE_DOCTOR_LAUNCH_CMD='true --permission-mode plan' \
      bash "$SCRIPT" doctor 2>&1)
assert_eq "$(jqf "$out" .ok)" "true" "doctor dry-run: ok:true"
assert_eq "$(jqf "$out" .dry_run)" "true" "doctor dry-run: dry_run flag"
dcmds="$(jqf "$out" '.commands | join("\n")')"
assert_contains "$dcmds" "new-window -d -n hi-doctor" "doctor dry-run: opens a detached scratch window"
assert_contains "$dcmds" "true --permission-mode plan" "doctor dry-run: launches the (overridden) throwaway command"
assert_contains "$dcmds" "kill-window" "doctor dry-run: tears the scratch window down"
assert_eq "$(jqf "$out" '[.commands[]|select(startswith("gh"))]|length')" "0" "doctor dry-run: no gh side effects"
# issue #87: the doctor real path now also pastes a multi-line probe (via the
# bracketed-paste delivery) and reads the box back, to verify the installed build
# keeps a multi-line paste as one un-submitted block. The dry-run lists that probe.
assert_contains "$dcmds" "tmux load-buffer -b issue-doctor -" "doctor dry-run: lists the probe buffer load"
assert_contains "$dcmds" "tmux paste-buffer -p -d -b issue-doctor -t <pane>" "doctor dry-run: lists the bracketed probe paste"
assert_contains "$dcmds" "tmux capture-pane -p -t <pane>" "doctor dry-run: lists the box read-back"

# --- doctor: DEFAULT launch template pins plan mode + opusplan (#97) -----------
# No override this time, so the doctor's binary precondition resolves `claude`;
# a stand-in on PATH keeps this hermetic (dry-run only `command -v`s it, never runs it).
repo=$(mk_repo)
stub_bin=$(mktemp -d /tmp/issue-doctor-stub.XXXXXX)
ln -s "$(command -v true)" "$stub_bin/claude"
out=$(cd "$repo" && PATH="$stub_bin:$PATH" ISSUE_DRY_RUN=1 bash "$SCRIPT" doctor 2>&1)
rm -rf "$stub_bin"
assert_eq "$(jqf "$out" .ok)" "true" "doctor default: dry-run ok:true"
assert_contains "$(jqf "$out" '.commands | join("\n")')" "claude --permission-mode plan --model opusplan" \
  "doctor default: launch keeps parity with dispatch — plan mode + opusplan model"

# --- doctor: real run reports the matched tier --------------------------------
# marker capture → "marker" tier; structural capture → "structural" tier. The
# stand-in binary is now named `claude` on PATH (AGE-83): since the readiness
# gate ports storyhook's SH-226, wait_ready also requires the occupant's NAME
# to match READY_PROCESS_PATTERN, and a bare `true` occupant would refuse here
# — this suite doesn't yet port SH-239's identity rule (AGE-83's next commit),
# which is what lets a differently-named stand-in through.
doctor_stub=$(mktemp -d /tmp/issue-doctor-tier-stub.XXXXXX)
ln -s "$(command -v true)" "$doctor_stub/claude"
repo=$(mk_repo)
out=$(cd "$repo" && PATH="$doctor_stub:$FAKE_DIR:$PATH" TMUX="fake,0,0" TMUX_PANE="%0" \
      ISSUE_DOCTOR_LAUNCH_CMD='claude --permission-mode plan' FAKE_TMUX_CAPTURE=marker \
      ISSUE_READY_DELAY=0 ISSUE_PASTE_SETTLE_DELAY=0 ISSUE_READY_ATTEMPTS=8 ISSUE_READY_STABLE_POLLS=2 \
      bash "$SCRIPT" doctor 2>&1)
assert_eq "$(jqf "$out" .readiness_confirmed)" "true" "doctor marker: readiness confirmed"
assert_eq "$(jqf "$out" .matched_tier)" "marker" "doctor marker: reports the marker tier"
# issue #87: the multi-line paste probe landed as one block — the FIRST line sits
# on the ❯ input row and all three marker lines are present (bracketed paste kept
# the newlines as text; had it split, only the last line would remain in the box).
assert_eq "$(jqf "$out" .multiline_probe.first_line_held)" "true" "doctor marker: probe's first line held in the box (not submitted)"
assert_eq "$(jqf "$out" .multiline_probe.lines_seen)" "3" "doctor marker: all 3 probe lines received as one block"
assert_eq "$(jqf "$out" .multiline_probe.lines_total)" "3" "doctor marker: probe reports its line total"

out=$(cd "$repo" && PATH="$doctor_stub:$FAKE_DIR:$PATH" TMUX="fake,0,0" TMUX_PANE="%0" \
      ISSUE_DOCTOR_LAUNCH_CMD='claude --permission-mode plan' FAKE_TMUX_CAPTURE=structural \
      ISSUE_READY_DELAY=0 ISSUE_PASTE_SETTLE_DELAY=0 ISSUE_READY_ATTEMPTS=8 ISSUE_READY_STABLE_POLLS=2 \
      bash "$SCRIPT" doctor 2>&1)
assert_eq "$(jqf "$out" .matched_tier)" "structural" "doctor structural: reports the structural tier"
rm -rf "$doctor_stub"

# --- doctor: missing launch binary → ok:false (hard precondition) -------------
repo=$(mk_repo)
out=$(cd "$repo" && ISSUE_DOCTOR_LAUNCH_CMD='/nonexistent/claude x' \
      TMUX="fake,0,0" TMUX_PANE="%0" bash "$SCRIPT" doctor 2>&1)
assert_eq "$(jqf "$out" .ok)" "false" "doctor: missing launch binary → ok:false"
assert_contains "$(jqf "$out" .display)" "not found on PATH" "doctor: clear display on missing binary"

finish
