#!/usr/bin/env bash
# The readiness gate + pane_tail evidence path (session.sh's wait_ready /
# pane_tail, shared with issue.sh — see plugins/issue/tests/test-readiness.sh
# for the full drift-history rationale, issue #67). story.sh's own suite must
# independently prove cmd_dispatch actually WIRES these shared primitives
# correctly: every case in test-dispatch.sh runs with FAKE_TMUX_CAPTURE=marker,
# which always confirms readiness instantly, so readiness_confirmed=false,
# prompt_confirmed=false, the warning-message variants, and the pane_tail
# evidence attachment are otherwise never exercised for story.sh specifically.
#
# Drives REAL (non-dry-run) dispatch headlessly against the state-driven fake
# tmux (tests/fakes/tmux, selected via FAKE_TMUX_CAPTURE), FAKE_STORY_STATE=
# in-progress throughout (these cases are about readiness, not claim
# semantics — already covered by test-dispatch.sh).
source "$(dirname "$0")/lib.sh"

FAKE_DIR="$TESTS_DIR/fakes"

# dispatch_ready <repo> <story-id> <capture-mode> [extra env KEY=VAL ...] — run
# a real dispatch with the fake tmux's capture-pane set to <capture-mode>,
# echo the emitted JSON. STORY_READY_STABLE_POLLS=2 keeps the structural tier
# fast (3 identical captures); STORY_READY_ATTEMPTS=8 bounds the never-ready
# cases.
dispatch_ready() {
  local dir="$1" id="$2" mode="$3"; shift 3
  ( cd "$dir" \
      && PATH="$FAKE_DIR:$PATH" \
         TMUX="fake,0,0" TMUX_PANE="%0" \
         FAKE_STORY_STATE=in-progress \
         FAKE_TMUX_CAPTURE="$mode" \
         STORY_READY_DELAY=0 STORY_READY_FALLBACK_DELAY=0 \
         STORY_CONFIRM_DELAY=0 STORY_PASTE_SETTLE_DELAY=0 \
         STORY_READY_ATTEMPTS=8 STORY_READY_STABLE_POLLS=2 \
         env "$@" \
         bash "$SCRIPT" dispatch "$id" 2>&1 )
}

# --- T1: broadened footer marker (no "for shortcuts") → ready, no warning ------
repo=$(mk_dispatch_repo)
out=$(dispatch_ready "$repo" SH-42 marker)
assert_eq "$(jqf "$out" .ok)" "true" "T1 marker: ok:true"
assert_eq "$(jqf "$out" .readiness_confirmed)" "true" "T1 marker: readiness confirmed via broadened marker"
assert_eq "$(jqf "$out" 'has("warning")')" "false" "T1 marker: NO warning"
assert_not_contains "$out" "for shortcuts" "T1 marker: confirmed without the stale 'for shortcuts' string"

# --- T2: fully drifted footer, structural tier (frame + glyph + stabilise) -----
repo=$(mk_dispatch_repo)
out=$(dispatch_ready "$repo" SH-43 structural)
assert_eq "$(jqf "$out" .readiness_confirmed)" "true" "T2 structural: readiness confirmed with no known footer marker"
assert_eq "$(jqf "$out" 'has("warning")')" "false" "T2 structural: NO warning"

# --- T2-guard: framed static MODAL (frame but no idle glyph) → NOT ready -------
repo=$(mk_dispatch_repo)
out=$(dispatch_ready "$repo" SH-44 modal)
assert_eq "$(jqf "$out" .readiness_confirmed)" "false" "T2-guard modal: framed static modal does NOT confirm readiness"
assert_eq "$(jqf "$out" 'has("warning")')" "true" "T2-guard modal: unconfirmed readiness raises a warning"

# --- T5: busy marker ("esc to interrupt") must NOT fast-path confirm -----------
repo=$(mk_dispatch_repo)
out=$(dispatch_ready "$repo" SH-45 busy)
assert_eq "$(jqf "$out" .readiness_confirmed)" "false" "T5 busy: 'esc to interrupt' is not treated as idle-ready"

# --- T3: never-ready churn → readiness:false, prompt:true, warning + pane_tail --
repo=$(mk_dispatch_repo)
state=$(mktemp -d /tmp/storywork-churn.XXXXXX)
out=$(dispatch_ready "$repo" SH-46 churn FAKE_TMUX_STATE="$state")
rm -rf "$state"
assert_eq "$(jqf "$out" .ok)" "true" "T3 churn: ok:true (window opened)"
assert_eq "$(jqf "$out" .readiness_confirmed)" "false" "T3 churn: readiness NOT confirmed"
assert_eq "$(jqf "$out" .prompt_confirmed)" "true" "T3 churn: prompt still confirmed (left the input line)"
assert_eq "$(jqf "$out" 'has("warning")')" "true" "T3 churn: warning present"
assert_eq "$(jqf "$out" 'has("pane_tail")')" "true" "T3 churn: pane_tail evidence present"
assert_contains "$(jqf "$out" .pane_tail)" "building worktree" "T3 churn: pane_tail carries the captured pane content"

# --- T4: legacy '? for shortcuts' still confirms (back-compat) -----------------
repo=$(mk_dispatch_repo)
out=$(dispatch_ready "$repo" SH-47 legacy)
assert_eq "$(jqf "$out" .readiness_confirmed)" "true" "T4 legacy: '? for shortcuts' still confirms readiness"
assert_eq "$(jqf "$out" 'has("warning")')" "false" "T4 legacy: no warning"

# --- T6: a no-warning (success) dispatch carries NO pane_tail key --------------
repo=$(mk_dispatch_repo)
out=$(dispatch_ready "$repo" SH-48 marker)
assert_eq "$(jqf "$out" 'has("pane_tail")')" "false" "T6 success: no pane_tail on the clean success payload"
assert_eq "$(jqf "$out" 'has("prompt_accepted")')" "true" "T6 success: prompt_accepted field always present"

# --- Drift-proof: readiness survives a fully missing footer marker -------------
repo=$(mk_dispatch_repo)
out=$(dispatch_ready "$repo" SH-49 marker STORY_READY_PATTERN='__no_such_marker__')
assert_eq "$(jqf "$out" .readiness_confirmed)" "true" "drift-proof: structural tier confirms with READY_PATTERN matching nothing"
assert_eq "$(jqf "$out" 'has("warning")')" "false" "drift-proof: no warning"

finish
