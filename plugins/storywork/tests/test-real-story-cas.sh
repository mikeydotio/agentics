#!/usr/bin/env bash
# Real-`story`-CLI coverage for story.sh's claim step (cmd_dispatch), closing
# a gap the Task A2 review flagged: every other test in this suite drives
# story.sh through tests/fakes/story, a hand-scripted stand-in whose JSON
# shapes were checked once by hand against a real binary but have no
# automated backstop against drifting. This file runs story.sh against the
# REAL `story` CLI (skipped if not on PATH -- mirrors this project's
# live-tier-skip convention; storyhook is local/offline, so unlike `gh` this
# has no network/quota cost and can run in the regular hermetic tier), proving:
#
#   R1. story.sh's `show`/`move --if-state` JSON parsing matches a real,
#       freshly-`story init`'d project's actual output shape -- not the
#       fake's assumptions about that shape.
#   R2. storyhook's project lock genuinely serializes concurrent claims: N
#       real `story.sh dispatch` processes racing the SAME real story
#       produce exactly one winner, not a scripted approximation of one
#       (mirrors conductor's own tests/test_retention.py::
#       TestConcurrentAppendsRealProcesses -- real OS processes racing a
#       real lock is the only thing that can prove this property).
source "$(dirname "$0")/lib.sh"

if ! command -v story >/dev/null 2>&1; then
  echo "SKIP: real story CLI not on PATH"
  exit 0
fi

# Resolve the real binary's ABSOLUTE path before anything below prepends
# $FAKE_TMUX_DIR to PATH -- that directory also contains a fake `story` (used
# by every other test in this suite), so a bare STORY_BIN=story would
# silently resolve to the FAKE once PATH is reordered, defeating the entire
# point of this file. An absolute path is immune to PATH search order.
REAL_STORY="$(command -v story)"

# mk_real_story_repo — a real storyhook project (`story init`) layered on a
# dispatch-ready git repo (mk_dispatch_repo's shape: local bare origin,
# fetchable, so cmd_dispatch's origin/<default> resolution works for real).
mk_real_story_repo() {
  local dir
  dir=$(mk_dispatch_repo)
  ( cd "$dir" && story project new --prefix TST >/dev/null )
  printf '%s' "$dir"
}

# new_real_story <repo-dir> <title> — create a real story, echo its id.
new_real_story() {
  local dir="$1" title="$2"
  ( cd "$dir" && story new "$title" --json 2>/dev/null ) | jq -r '.story.story.id'
}

# real_story_state <repo-dir> <id> — echo the story's current state, read
# fresh via the real CLI (ground truth, never inferred from story.sh's JSON).
real_story_state() {
  local dir="$1" id="$2"
  ( cd "$dir" && story show "$id" --json 2>/dev/null ) | jq -r '.story.story.state // ""'
}

dispatch_real_cli() {
  local dir="$1" id="$2"
  ( cd "$dir" \
      && PATH="$FAKE_TMUX_DIR:$PATH" STORY_BIN="$REAL_STORY" \
         TMUX="fake,0,0" TMUX_PANE="%0" \
         STORY_READY_DELAY=0 STORY_READY_FALLBACK_DELAY=0 \
         STORY_CONFIRM_DELAY=0 STORY_PASTE_SETTLE_DELAY=0 \
         FAKE_TMUX_CAPTURE=marker \
         bash "$SCRIPT" dispatch "$id" 2>&1 )
}

# ==============================================================================
# Case R1: a single real dispatch against a real, freshly-created story.
# ==============================================================================
repo_r1=$(mk_real_story_repo)
id_r1=$(new_real_story "$repo_r1" "Real CAS test story")
[ -n "$id_r1" ] && [ "$id_r1" != "null" ] || fail_test "R1: failed to create a real story (got id [$id_r1])"

out_r1=$(dispatch_real_cli "$repo_r1" "$id_r1")
assert_eq "$(jqf "$out_r1" .ok)" "true" "R1: ok:true against the real story CLI"
assert_eq "$(jqf "$out_r1" .claimed)" "true" "R1: claimed:true (a real transition happened)"

state_r1="$(real_story_state "$repo_r1" "$id_r1")"
assert_eq "$state_r1" "in-progress" "R1: the real story is actually in-progress after dispatch"

# Case R1b: a story that is ALREADY in-progress before story.sh ever sees it
# (as if a caller -- conductor's storyx.claim_ready -- pre-claimed it) must
# skip the move entirely. A FRESH repo/story is required here: reusing R1's
# story would collide with the worktree R1 already created (a real, correct
# "already dispatched" refusal, not the claim-skip path this case tests).
repo_r1b=$(mk_real_story_repo)
id_r1b=$(new_real_story "$repo_r1b" "Real pre-claimed test story")
[ -n "$id_r1b" ] && [ "$id_r1b" != "null" ] || fail_test "R1b: failed to create a real story (got id [$id_r1b])"
( cd "$repo_r1b" && story move "$id_r1b" in-progress >/dev/null 2>&1 )

out_r1b=$(dispatch_real_cli "$repo_r1b" "$id_r1b")
assert_eq "$(jqf "$out_r1b" .ok)" "true" "R1b: ok:true when already in-progress"
assert_eq "$(jqf "$out_r1b" .claimed)" "false" "R1b: claimed:false -- no redundant move against the real CLI"

# ==============================================================================
# Case R2: real concurrency — N story.sh dispatch processes racing the SAME
# real story. Only the eventual winner ever reaches a real tmux call (every
# loser refuses at the claim step, before any worktree/window side effect),
# so this is safe under the fake tmux's shared, non-isolated state model
# despite running concurrently.
# ==============================================================================
repo_r2=$(mk_real_story_repo)
id_r2=$(new_real_story "$repo_r2" "Real concurrency test story")
[ -n "$id_r2" ] && [ "$id_r2" != "null" ] || fail_test "R2: failed to create a real story (got id [$id_r2])"

N=5
outdir=$(mktemp -d /tmp/storywork-concurrency.XXXXXX)
_TMP_REPOS+=("$outdir")
pids=()
for i in $(seq 1 "$N"); do
  ( dispatch_real_cli "$repo_r2" "$id_r2" > "$outdir/$i.json" 2>"$outdir/$i.err" ) &
  pids+=("$!")
done
for pid in "${pids[@]}"; do wait "$pid"; done

ok_count=0
conflict_count=0
for i in $(seq 1 "$N"); do
  raw=$(cat "$outdir/$i.json")
  ok=$(jqf "$raw" .ok)
  if [ "$ok" = "true" ]; then
    ok_count=$((ok_count + 1))
  else
    reason=$(jqf "$raw" .reason)
    [ "$reason" = "claim-conflict" ] && conflict_count=$((conflict_count + 1))
  fi
done
assert_eq "$ok_count" "1" "R2: exactly one of $N concurrent real dispatches wins the claim"
assert_eq "$conflict_count" "$((N - 1))" \
  "R2: the other $((N - 1)) refuse with a real claim-conflict, not a silent double-claim or a generic error"

state_r2="$(real_story_state "$repo_r2" "$id_r2")"
assert_eq "$state_r2" "in-progress" "R2: the real story lands in-progress exactly once, not corrupted by the race"

# ==============================================================================
# Case R3 (AGE-12): the PREMISE of missing_claim_state_vocabulary's parse, held
# against the real CLI.
#
# That helper decides whether to reclassify a failed claim by reading `story
# state list --json` and parsing `.message` — an UNSTRUCTURED prose blob. Its
# two load-bearing assumptions are therefore upstream's to break: that the
# message names each state, and that a state's slug is the first
# whitespace-delimited token of its line. `tests/fakes/story` encodes both, so
# without this case the whole classifier could be verified entirely against
# the fake's copy of an assumption that had already stopped being true.
#
# The BROKEN vocabulary is deliberately NOT constructed here. storyhook 2.0.0
# enforces the four-state invariant (SH-125): `state remove in-progress` is
# refused, so the only ways to build one are direct store surgery or a legacy
# store — neither of which belongs in a committed regression test. What is
# checkable against a live CLI is the parse's premise on a HEALTHY project,
# and that is exactly what would silently rot.
# ==============================================================================
repo_r3=$(mk_real_story_repo)
list_r3=$( cd "$repo_r3" && story state list --json 2>/dev/null )
msg_r3=$(jqf "$list_r3" '.message // ""')
assert_contains "$msg_r3" "in-progress" \
  "R3: the real \`story state list --json\` message names the claim state (the loose-containment gate's premise)"
slugs_r3=$(printf '%s\n' "$msg_r3" | awk 'NF { printf "%s%s", (n++ ? ", " : ""), $1 }')
assert_contains "$slugs_r3" "in-progress" \
  "R3: the slug is the first whitespace-delimited token of its line (the line-parse's premise)"
assert_contains "$slugs_r3" "todo" \
  "R3: the same parse recovers the other states, so the observed-vocabulary clause is real output, not a fixture"

finish
