#!/usr/bin/env bash
# STORY_TARGET_SESSION (daemon-caller seam): when set, dispatch opens its new
# window in the NAMED tmux session (`tmux new-window -t "<session>:"`) instead
# of the caller's current one, and the $TMUX/$TMUX_PANE hard preconditions are
# skipped — the caller is a daemon outside tmux. Unset, behavior is unchanged:
# no -t flag on new-window, and dispatch still hard-requires a tmux context.
# Mirrors plugins/issue/tests/test-target-session.sh, adapted to story ids and
# the STORY_* namespace (story.sh's own ENV VAR NAMESPACE header note).
source "$(dirname "$0")/lib.sh"

FAKE_DIR="$TESTS_DIR/fakes"

# --- Case 1: dry-run reflects the -t <session>: flag on its new-window command -
repo=$(mk_repo)
out=$(cd "$repo" && STORY_DRY_RUN=1 STORY_TARGET_SESSION=moshtail \
      FAKE_STORY_STATE=todo bash "$SCRIPT" dispatch SH-7 2>&1)
assert_eq "$(jqf "$out" .ok)" "true" "target dry-run: ok:true"
assert_eq "$(jqf "$out" '[.commands[]|select(startswith("tmux new-window"))][0] | contains("-t moshtail:")')" "true" \
  "target dry-run: new-window command carries -t moshtail:"
# Lock the flag's position: -t precedes -d, matching the real new-window
# invocation (the dry-run command string and the real args must stay in sync).
assert_contains "$(jqf "$out" '[.commands[]|select(startswith("tmux new-window"))][0]')" "new-window -t moshtail: -d -c" \
  "target dry-run: -t moshtail: precedes -d, in sync with the real invocation"

# --- Case 2: non-dry-run OUTSIDE tmux succeeds when the target session is set --
# Mirrors test-dispatch.sh's real-dispatch harness but with TMUX/TMUX_PANE
# explicitly UNSET via env -u: the daemon caller runs outside tmux, so the
# $TMUX/$TMUX_PANE hard preconditions must be skipped and dispatch still
# completes ok:true. Needs the hermetic local-origin fixture (mk_dispatch_repo),
# not mk_repo's unfetchable fake origin, since dispatch runs a real fetch.
repo=$(mk_dispatch_repo)
out=$( cd "$repo" \
    && PATH="$FAKE_DIR:$PATH" \
       STORY_TARGET_SESSION=moshtail \
       FAKE_STORY_STATE=in-progress \
       FAKE_TMUX_CAPTURE=marker \
       STORY_READY_DELAY=0 STORY_READY_FALLBACK_DELAY=0 \
       STORY_CONFIRM_DELAY=0 STORY_PASTE_SETTLE_DELAY=0 \
       STORY_READY_ATTEMPTS=8 STORY_READY_STABLE_POLLS=2 \
       env -u TMUX -u TMUX_PANE \
       bash "$SCRIPT" dispatch SH-7 2>&1 )
assert_eq "$(jqf "$out" .ok)" "true" "target real: ok:true outside tmux"
assert_eq "$(jqf "$out" .prompt_confirmed)" "true" "target real: prompt still confirmed"

# Guard: WITHOUT the var, the same outside-tmux dispatch still hard-fails — the
# precondition skip is strictly conditional on STORY_TARGET_SESSION.
out=$( cd "$repo" \
    && PATH="$FAKE_DIR:$PATH" FAKE_STORY_STATE=in-progress FAKE_TMUX_CAPTURE=marker \
       env -u TMUX -u TMUX_PANE \
       bash "$SCRIPT" dispatch SH-7 2>&1 )
assert_eq "$(jqf "$out" .ok)" "false" "no-target guard: outside tmux still ok:false"
assert_contains "$(jqf "$out" .display)" "requires tmux" \
  "no-target guard: display names the tmux requirement"

# --- Case 3: default (var unset) dry-run has NO -t flag (unchanged behavior) ---
repo=$(mk_repo)
out=$(cd "$repo" && STORY_DRY_RUN=1 FAKE_STORY_STATE=todo bash "$SCRIPT" dispatch SH-7 2>&1)
assert_eq "$(jqf "$out" '[.commands[]|select(startswith("tmux new-window"))][0] | contains("-t ")')" "false" \
  "default dry-run: new-window command has no -t flag"

finish
