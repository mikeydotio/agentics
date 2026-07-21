#!/usr/bin/env bash
# story.sh dispatch — the claim-then-handoff contract.
#
# storyhook's `move` has NO idempotency guard of its own: a self-transition
# (moving a story to the state it is already in) still appends a new
# StoryStateChanged event and fires the state_change hook. Phase 2's
# storyx.claim_ready (conductor) will CAS-move a story to in-progress BEFORE
# ever invoking `story.sh dispatch <id>` — so cmd_dispatch must read the
# story's CURRENT state first and only attempt its own CAS move when a real
# transition is still needed, never blindly repeating one a caller already
# performed. Both branches are exercised explicitly below (not assumed).
#
# Also proves the {ok, window_name, pane} JSON shape `issue.sh dispatch`
# emits today is unchanged for story.sh — conductor's dispatch.py parses only
# those fields (plus `display` on failure), so this is the actual contract,
# not incidental.
source "$(dirname "$0")/lib.sh"

# dispatch_real <repo-dir> <story-id> — run a real (non-dry-run) dispatch
# against <repo-dir> with the fake tmux/story wired in, and echo the emitted
# JSON. Caller sets FAKE_STORY_* env vars before invoking.
dispatch_real() {
  local dir="$1" id="$2"
  ( cd "$dir" \
      && PATH="$FAKE_TMUX_DIR:$PATH" \
         TMUX="fake,0,0" TMUX_PANE="%0" \
         STORY_READY_DELAY=0 STORY_READY_FALLBACK_DELAY=0 \
         STORY_CONFIRM_DELAY=0 STORY_PASTE_SETTLE_DELAY=0 \
         FAKE_TMUX_CAPTURE=marker \
         bash "$SCRIPT" dispatch "$id" 2>&1 )
}

# dispatch_dry <repo-dir> <story-id> — dry-run dispatch (no tmux needed).
dispatch_dry() {
  local dir="$1" id="$2"
  ( cd "$dir" && STORY_DRY_RUN=1 bash "$SCRIPT" dispatch "$id" 2>&1 )
}

# expected_wname <repo-dir> <story-id> — the window/worktree name story.sh's
# resolve_wname derives: first 3 alnum chars of the repo dir's basename,
# lowercased, + "-<id>". Computed independently here (not hardcoded) so the
# test doesn't assume a fixed mktemp suffix.
expected_wname() {
  local repo="$1" id="$2" prefix
  prefix=$(basename "$repo" | tr -cd '[:alnum:]' | cut -c1-3 | tr '[:upper:]' '[:lower:]')
  printf '%s-%s' "$prefix" "$id"
}

# ==============================================================================
# Case 1: NOT yet claimed (state=todo) — dispatch must claim it via the CAS
# move, then create the worktree/window and hand off.
# ==============================================================================
repo1=$(mk_dispatch_repo)
wname1=$(expected_wname "$repo1" "SH-1")
log1=$(mktemp /tmp/storywork-log.XXXXXX)

out1=$(FAKE_STORY_STATE=todo FAKE_STORY_LOG="$log1" dispatch_real "$repo1" SH-1)
assert_eq "$(jqf "$out1" .ok)" "true" "case1: ok:true"
assert_eq "$(jqf "$out1" .claimed)" "true" "case1: claimed:true (a real transition happened)"
assert_eq "$(jqf "$out1" .window_name)" "$wname1" "case1: window_name matches resolve_wname"
[ -n "$(jqf "$out1" .pane)" ] && [ "$(jqf "$out1" .pane)" != "null" ] \
  || fail_test "case1: pane must be non-empty"
assert_contains "$(cat "$log1")" "move SH-1 in-progress --if-state todo" \
  "case1: the CAS move was actually attempted"
[ -d "$repo1/.claude/worktrees/$wname1" ] || fail_test "case1: worktree directory missing"
( cd "$repo1" && git show-ref --verify --quiet "refs/heads/worktree-$wname1" ) \
  || fail_test "case1: worktree branch missing"

# ==============================================================================
# Case 2: ALREADY in-progress (as if a caller — conductor's storyx.claim_ready
# — pre-claimed it). cmd_dispatch must NOT repeat the move: storyhook's move
# has no self-transition guard, so a redundant call here would be a spurious
# state-change event + hook fire on every conductor-driven dispatch forever.
# ==============================================================================
repo2=$(mk_dispatch_repo)
wname2=$(expected_wname "$repo2" "SH-2")
log2=$(mktemp /tmp/storywork-log.XXXXXX)

out2=$(FAKE_STORY_STATE=in-progress FAKE_STORY_LOG="$log2" dispatch_real "$repo2" SH-2)
assert_eq "$(jqf "$out2" .ok)" "true" "case2: ok:true"
assert_eq "$(jqf "$out2" .claimed)" "false" "case2: claimed:false (no transition was needed)"
assert_eq "$(jqf "$out2" .window_name)" "$wname2" "case2: window_name matches resolve_wname"
[ -n "$(jqf "$out2" .pane)" ] && [ "$(jqf "$out2" .pane)" != "null" ] \
  || fail_test "case2: pane must be non-empty"
assert_not_contains "$(cat "$log2")" "move" \
  "case2: no redundant story-move call was made"
[ -d "$repo2/.claude/worktrees/$wname2" ] || fail_test "case2: worktree directory missing"

# ==============================================================================
# Case 3: closed guard — a CLOSED superstate refuses dispatch before any side
# effect, mirroring issue.sh's CLOSED precondition. STORY_ALLOW_CLOSED=1 opts
# back in, exactly like ISSUE_ALLOW_CLOSED.
# ==============================================================================
repo3=$(mk_dispatch_repo)
wname3=$(expected_wname "$repo3" "SH-3")

out3=$(FAKE_STORY_STATE=todo FAKE_STORY_SUPERSTATE=CLOSED dispatch_real "$repo3" SH-3)
assert_eq "$(jqf "$out3" .ok)" "false" "case3: ok:false when closed"
assert_contains "$(jqf "$out3" .display)" "closed" "case3: display names the closed guard"
[ -e "$repo3/.claude/worktrees/$wname3" ] \
  && fail_test "case3: no worktree should be created when the guard refuses" || :

out3b=$(FAKE_STORY_STATE=todo FAKE_STORY_SUPERSTATE=CLOSED STORY_ALLOW_CLOSED=1 \
        dispatch_real "$repo3" SH-3)
assert_eq "$(jqf "$out3b" .ok)" "true" "case3b: STORY_ALLOW_CLOSED=1 overrides the guard"

# ==============================================================================
# Case 4: claim conflict — the story changed state between story.sh's own
# `show` read and its `move` attempt (a genuine concurrent-claim race). Must
# refuse distinguishably (not a generic fail) and create NOTHING.
# ==============================================================================
repo4=$(mk_dispatch_repo)
wname4=$(expected_wname "$repo4" "SH-4")

out4=$(FAKE_STORY_STATE=todo FAKE_STORY_MOVE_CONFLICT=1 dispatch_real "$repo4" SH-4)
assert_eq "$(jqf "$out4" .ok)" "false" "case4: ok:false on a claim conflict"
assert_eq "$(jqf "$out4" .reason)" "claim-conflict" "case4: reason is machine-distinguishable"
[ -e "$repo4/.claude/worktrees/$wname4" ] \
  && fail_test "case4: no worktree should be created on a lost claim race" || :
( cd "$repo4" && git show-ref --verify --quiet "refs/heads/worktree-$wname4" ) \
  && fail_test "case4: no worktree branch should be created on a lost claim race" || :

# ==============================================================================
# Case 5: the same two claim branches, mirrored under STORY_DRY_RUN=1 — reads
# are still real (issue.sh's own asymmetry), so the planned `commands` array
# must include the move only when a real transition is needed.
# ==============================================================================
repo5=$(mk_repo)

dry_needed=$(FAKE_STORY_STATE=todo dispatch_dry "$repo5" SH-5)
assert_eq "$(jqf "$dry_needed" .ok)" "true" "case5a: dry-run ok:true"
assert_eq "$(jqf "$dry_needed" .dry_run)" "true" "case5a: dry_run:true"
assert_contains "$(jqf "$dry_needed" '.commands | join("\n")')" "move SH-5 in-progress --if-state todo" \
  "case5a: planned commands include the CAS move when a transition is needed"

dry_skip=$(FAKE_STORY_STATE=in-progress dispatch_dry "$repo5" SH-6)
assert_eq "$(jqf "$dry_skip" .ok)" "true" "case5b: dry-run ok:true"
assert_not_contains "$(jqf "$dry_skip" '.commands | join("\n")')" "move" \
  "case5b: planned commands exclude the move when already in-progress"

# ==============================================================================
# Case 6: `story show` itself fails (story not found). Must refuse before any
# side effect with a message naming the story, not a generic crash.
# ==============================================================================
repo6=$(mk_dispatch_repo)
wname6=$(expected_wname "$repo6" "SH-6")

out6=$(FAKE_STORY_SHOW_FAIL=1 dispatch_real "$repo6" SH-6)
assert_eq "$(jqf "$out6" .ok)" "false" "case6: ok:false when story show fails"
assert_contains "$(jqf "$out6" .display)" "not found" "case6: display names the not-found failure"
[ -e "$repo6/.claude/worktrees/$wname6" ] \
  && fail_test "case6: no worktree should be created when story show fails" || :

# ==============================================================================
# Case 7: `story show` succeeds but `story move` fails with a GENERIC error
# (distinct from a claim conflict — e.g. a storyhook-side outage). Must
# refuse, not silently proceed as if claimed.
# ==============================================================================
repo7=$(mk_dispatch_repo)
wname7=$(expected_wname "$repo7" "SH-7")

out7=$(FAKE_STORY_STATE=todo FAKE_STORY_MOVE_FAIL=1 dispatch_real "$repo7" SH-7)
assert_eq "$(jqf "$out7" .ok)" "false" "case7: ok:false when story move fails"
assert_contains "$(jqf "$out7" .display)" "story move" "case7: display names the move failure"
[ -e "$repo7/.claude/worktrees/$wname7" ] \
  && fail_test "case7: no worktree should be created when story move fails" || :

# ==============================================================================
# Case 8: CLAIM ROLLBACK — the claim (a real todo -> in-progress transition)
# succeeds, but a LATER hard failure (a worktree/branch collision: something
# already dispatched for this id and was never completed) means the story
# must NOT be left stranded at `in-progress` with no worktree/window. A
# best-effort CAS move back to the pre-claim state is attempted and the
# outcome is named in the failure message either way.
# ==============================================================================
repo8=$(mk_dispatch_repo)
wname8=$(expected_wname "$repo8" "SH-8")
log8=$(mktemp /tmp/storywork-log.XXXXXX)
( cd "$repo8" \
    && git branch "worktree-$wname8" \
    && git worktree add -q --detach ".claude/worktrees/$wname8" ) >/dev/null 2>&1

out8=$(FAKE_STORY_STATE=todo FAKE_STORY_LOG="$log8" dispatch_real "$repo8" SH-8)
assert_eq "$(jqf "$out8" .ok)" "false" "case8: ok:false on a post-claim worktree/branch collision"
assert_contains "$(jqf "$out8" .display)" "already exists" "case8: display names the collision"
assert_contains "$(cat "$log8")" "move SH-8 in-progress --if-state todo" \
  "case8: the CAS claim move was actually attempted"
assert_contains "$(cat "$log8")" "move SH-8 todo --if-state in-progress" \
  "case8: a rollback move to the pre-claim state was attempted"
assert_contains "$(jqf "$out8" .display)" "Rolled the claim back" \
  "case8: display confirms the rollback succeeded"

# ---- Case 8b: the rollback attempt ITSELF fails — never silent about it. ----
repo8b=$(mk_dispatch_repo)
wname8b=$(expected_wname "$repo8b" "SH-8B")
( cd "$repo8b" \
    && git branch "worktree-$wname8b" \
    && git worktree add -q --detach ".claude/worktrees/$wname8b" ) >/dev/null 2>&1

out8b=$(FAKE_STORY_STATE=todo FAKE_STORY_ROLLBACK_FAIL=1 dispatch_real "$repo8b" SH-8B)
assert_eq "$(jqf "$out8b" .ok)" "false" "case8b: ok:false on the same collision"
assert_contains "$(jqf "$out8b" .display)" "stranded" \
  "case8b: display explicitly names the stranded claim when rollback also fails"

# ==============================================================================
# Case 9: CLAIM ROLLBACK on a `git worktree add` failure — the worktree
# CONTAINER path is a plain file (not a directory), so the pre-check at Step 7
# passes (nothing exists at the exact worktree path yet) but the underlying
# `git worktree add` call itself fails.
# ==============================================================================
repo9=$(mk_dispatch_repo)
wname9=$(expected_wname "$repo9" "SH-9")
log9=$(mktemp /tmp/storywork-log.XXXXXX)
( cd "$repo9" && mkdir -p .claude && : > .claude/worktrees ) >/dev/null 2>&1

out9=$(FAKE_STORY_STATE=todo FAKE_STORY_LOG="$log9" dispatch_real "$repo9" SH-9)
assert_eq "$(jqf "$out9" .ok)" "false" "case9: ok:false when git worktree add fails"
assert_contains "$(jqf "$out9" .display)" "failed to create worktree" "case9: display names the worktree-add failure"
assert_contains "$(cat "$log9")" "move SH-9 in-progress --if-state todo" \
  "case9: the CAS claim move was actually attempted"
assert_contains "$(cat "$log9")" "move SH-9 todo --if-state in-progress" \
  "case9: a rollback move was attempted after the worktree-add failure"

# ==============================================================================
# Case 10: CLAIM ROLLBACK on a `tmux new-window` failure — the fake tmux's
# FAKE_TMUX_NEW_WINDOW_FAIL knob simulates a dead/unreachable tmux server.
# ==============================================================================
repo10=$(mk_dispatch_repo)
wname10=$(expected_wname "$repo10" "SH-10")
log10=$(mktemp /tmp/storywork-log.XXXXXX)

out10=$( cd "$repo10" \
    && PATH="$FAKE_TMUX_DIR:$PATH" \
       TMUX="fake,0,0" TMUX_PANE="%0" \
       STORY_READY_DELAY=0 STORY_READY_FALLBACK_DELAY=0 \
       STORY_CONFIRM_DELAY=0 STORY_PASTE_SETTLE_DELAY=0 \
       FAKE_TMUX_CAPTURE=marker FAKE_TMUX_NEW_WINDOW_FAIL=1 \
       FAKE_STORY_STATE=todo FAKE_STORY_LOG="$log10" \
       bash "$SCRIPT" dispatch SH-10 2>&1 )
assert_eq "$(jqf "$out10" .ok)" "false" "case10: ok:false when tmux new-window fails"
assert_contains "$(jqf "$out10" .display)" "failed to open a new tmux window" "case10: display names the tmux failure"
assert_contains "$(cat "$log10")" "move SH-10 in-progress --if-state todo" \
  "case10: the CAS claim move was actually attempted"
assert_contains "$(cat "$log10")" "move SH-10 todo --if-state in-progress" \
  "case10: a rollback move was attempted after the tmux new-window failure"
( cd "$repo10" && git show-ref --verify --quiet "refs/heads/worktree-$wname10" ) \
  && fail_test "case10: the worktree branch should have been rolled back by the existing tmux-failure cleanup" || :

finish
