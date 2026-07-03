#!/usr/bin/env bash
# forge-loop-state.sh — deterministic .forge/state.json bookkeeping for the
# execute loop (WS4/F031, F003, F037, F093, F097, F098).
#
# Every per-iteration counter mutation and threshold comparison that
# references/execution-loop.md used to describe as prose arithmetic (hand-run
# by the model, once per story) lives here instead. The model calls a
# subcommand and branches on the returned JSON — it never edits state.json's
# counters directly.
#
# Usage:
#   forge-loop-state.sh attempt [--forge-dir <dir>]
#   forge-loop-state.sh done [--forge-dir <dir>]
#   forge-loop-state.sh retry --story-id <id> [--forge-dir <dir>]
#   forge-loop-state.sh runaway-check [--forge-dir <dir>]
#   forge-loop-state.sh storyhook-failure --result ok|fail [--forge-dir <dir>]
#   forge-loop-state.sh architect-check --wave-boundary true|false [--forge-dir <dir>]
#
# All subcommands read `.forge/config.json` (falling back to the documented
# defaults in `skills/forge/SKILL.md`'s Settings section when a field or the
# whole file is absent) and read-modify-write `.forge/state.json` atomically
# (write to a `.tmp` sibling, then `mv` — same idiom as forge-step-exit.sh and
# hooks/session-stop.sh). A missing/malformed state.json is treated as `{}`
# (all counters default to 0) rather than an error — the execute loop's Fresh
# Start step is what actually creates state.json; every subcommand here is
# still safe to call before that has happened.
#
# Output: always one JSON object with `ok` + `display` + subcommand-specific
# fields (see each subcommand below). Always exits 0 — callers branch on the
# JSON, matching every other bin/ script's convention.
set -euo pipefail

SUBCOMMAND="${1:-}"
[ $# -gt 0 ] && shift || true

FORGE_DIR=".forge"
STORY_ID=""
RESULT=""
WAVE_BOUNDARY="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --forge-dir)      FORGE_DIR="$2"; shift 2 ;;
    --forge-dir=*)    FORGE_DIR="${1#*=}"; shift ;;
    --story-id)       STORY_ID="$2"; shift 2 ;;
    --story-id=*)     STORY_ID="${1#*=}"; shift ;;
    --result)         RESULT="$2"; shift 2 ;;
    --result=*)       RESULT="${1#*=}"; shift ;;
    --wave-boundary)  WAVE_BOUNDARY="$2"; shift 2 ;;
    --wave-boundary=*) WAVE_BOUNDARY="${1#*=}"; shift ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

CONFIG_FILE="$FORGE_DIR/config.json"
STATE_FILE="$FORGE_DIR/state.json"

# --- Config reading (documented defaults from skills/forge/SKILL.md) ---
#
# max_total_retries defaults to 100, not the smaller number some earlier
# drafts used (F097): with max_retries=4 per story and up to max_sessions=200
# 1-story-per-session sessions in a full run, a realistic multi-wave plan of
# dozens to ~100 stories at a normal ~30-50% first-attempt retry rate
# accumulates total_retries well into the tens before completing — a cap in
# the low tens would false-halt healthy runs partway through (see
# skills/forge/SKILL.md's Settings section for the full rationale). This
# script's fallback default MUST match the documented default there; if you
# change one, change both.
read_config() {
  if [ -f "$CONFIG_FILE" ]; then
    max_stories_per_session=$(jq -r '.max_stories_per_session // 1' "$CONFIG_FILE")
    max_retries=$(jq -r '.max_retries // 4' "$CONFIG_FILE")
    max_sessions=$(jq -r '.max_sessions // 200' "$CONFIG_FILE")
    max_total_retries=$(jq -r '.max_total_retries // 100' "$CONFIG_FILE")
  else
    max_stories_per_session=1
    max_retries=4
    max_sessions=200
    max_total_retries=100
  fi
}

# --- state.json read/write ---

read_state() {
  if [ -f "$STATE_FILE" ] && jq -e . "$STATE_FILE" >/dev/null 2>&1; then
    cat "$STATE_FILE"
  else
    echo '{}'
  fi
}

# Atomic read-modify-write: forwards all arguments to `jq` (so callers can
# pass --arg/--argjson before the trailing filter string), writes the result
# to a `.tmp` sibling then `mv`s it into place (same idiom as
# forge-step-exit.sh / hooks/session-stop.sh), and echoes the new content back
# so the caller can pull fields from it without a second disk read.
write_state() {
  local current new
  current="$(read_state)"
  mkdir -p "$FORGE_DIR"
  new="$(echo "$current" | jq "$@")"
  echo "$new" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
  echo "$new"
}

read_config

case "$SUBCOMMAND" in
  # --- attempt: a story reached evaluation (pass or fail) ---
  attempt)
    new_state="$(write_state '
      .stories_attempted = ((.stories_attempted // 0) + 1)
      | .updated_at = (now | todate)
    ')"
    stories_attempted="$(echo "$new_state" | jq -r '.stories_attempted')"
    jq -n \
      --argjson ok true \
      --argjson stories_attempted "$stories_attempted" \
      --arg display "[forge] loop-state: stories_attempted=$stories_attempted" \
      '{ok: $ok, stories_attempted: $stories_attempted, display: $display}'
    ;;

  # --- done: a story reached `done` this session ---
  done)
    new_state="$(write_state '
      .stories_this_session = ((.stories_this_session // 0) + 1)
      | .updated_at = (now | todate)
    ')"
    stories_this_session="$(echo "$new_state" | jq -r '.stories_this_session')"
    session_limit_hit="false"
    if [ "$stories_this_session" -ge "$max_stories_per_session" ]; then
      session_limit_hit="true"
    fi
    jq -n \
      --argjson ok true \
      --argjson stories_this_session "$stories_this_session" \
      --argjson max_stories_per_session "$max_stories_per_session" \
      --argjson session_limit_hit "$session_limit_hit" \
      --arg display "[forge] loop-state: stories_this_session=$stories_this_session/$max_stories_per_session (limit_hit=$session_limit_hit)" \
      '{ok: $ok, stories_this_session: $stories_this_session, max_stories_per_session: $max_stories_per_session, session_limit_hit: $session_limit_hit, display: $display}'
    ;;

  # --- retry: a story's generate/evaluate attempt failed ---
  retry)
    [ -n "$STORY_ID" ] || { echo "Error: --story-id is required for retry" >&2; exit 1; }
    new_state="$(write_state --arg sid "$STORY_ID" '
      .retry_counts = (.retry_counts // {})
      | .retry_counts[$sid] = ((.retry_counts[$sid] // 0) + 1)
      | .total_retries = ((.total_retries // 0) + 1)
      | .updated_at = (now | todate)
    ')"
    retry_count="$(echo "$new_state" | jq -r --arg sid "$STORY_ID" '.retry_counts[$sid]')"
    total_retries="$(echo "$new_state" | jq -r '.total_retries')"
    action="retry"
    if [ "$retry_count" -ge "$max_retries" ]; then
      action="block"
    fi
    jq -n \
      --argjson ok true \
      --arg story_id "$STORY_ID" \
      --argjson retry_count "$retry_count" \
      --argjson max_retries "$max_retries" \
      --argjson total_retries "$total_retries" \
      --arg action "$action" \
      --arg display "[forge] loop-state: $STORY_ID retry_count=$retry_count/$max_retries -> $action (total_retries=$total_retries)" \
      '{ok: $ok, story_id: $story_id, retry_count: $retry_count, max_retries: $max_retries, total_retries: $total_retries, action: $action, display: $display}'
    ;;

  # --- runaway-check: read-only guard against the two global safeguards ---
  # Also reports the current storyhook_consecutive_failures value (see the
  # storyhook-failure subcommand below, which is what mutates it) so a single
  # call at the top of the loop can evaluate all three halt conditions
  # execution-loop.md's Step 0/0a used to check separately in prose.
  runaway-check)
    state="$(read_state)"
    sessions_completed="$(echo "$state" | jq -r '.sessions_completed // 0')"
    total_retries="$(echo "$state" | jq -r '.total_retries // 0')"
    storyhook_consecutive_failures="$(echo "$state" | jq -r '.storyhook_consecutive_failures // 0')"

    halt="false"
    reason=""
    if [ "$sessions_completed" -ge "$max_sessions" ]; then
      halt="true"
      reason="max_sessions reached ($sessions_completed/$max_sessions)"
    elif [ "$total_retries" -ge "$max_total_retries" ]; then
      halt="true"
      reason="max_total_retries reached ($total_retries/$max_total_retries)"
    elif [ "$storyhook_consecutive_failures" -ge 3 ]; then
      halt="true"
      reason="storyhook unavailable — 3 consecutive failures"
    fi

    display="[forge] loop-state: runaway-check halt=$halt"
    [ -n "$reason" ] && display="$display ($reason)"

    jq -n \
      --argjson ok true \
      --argjson halt "$halt" \
      --arg reason "$reason" \
      --argjson sessions_completed "$sessions_completed" \
      --argjson max_sessions "$max_sessions" \
      --argjson total_retries "$total_retries" \
      --argjson max_total_retries "$max_total_retries" \
      --argjson storyhook_consecutive_failures "$storyhook_consecutive_failures" \
      --arg display "$display" \
      '{ok: $ok, halt: $halt, reason: $reason, sessions_completed: $sessions_completed,
        max_sessions: $max_sessions, total_retries: $total_retries,
        max_total_retries: $max_total_retries,
        storyhook_consecutive_failures: $storyhook_consecutive_failures, display: $display}'
    ;;

  # --- storyhook-failure: persist the consecutive-failure counter (F093) ---
  # Without this, the counter lived only in conversation-turn memory
  # (execution-loop.md's old Step 0/1 prose), which the mandatory
  # "re-read state.json fresh from disk every iteration" rule (Hard Rule 6)
  # silently discarded on every single iteration -- the breaker could never
  # actually trip. Persisting it here makes it survive exactly that re-read.
  storyhook-failure)
    case "$RESULT" in
      ok|fail) ;;
      *) echo "Error: --result must be 'ok' or 'fail'" >&2; exit 1 ;;
    esac
    if [ "$RESULT" = "fail" ]; then
      new_state="$(write_state '
        .storyhook_consecutive_failures = ((.storyhook_consecutive_failures // 0) + 1)
        | .updated_at = (now | todate)
      ')"
    else
      new_state="$(write_state '
        .storyhook_consecutive_failures = 0
        | .updated_at = (now | todate)
      ')"
    fi
    count="$(echo "$new_state" | jq -r '.storyhook_consecutive_failures')"
    halt="false"
    [ "$count" -ge 3 ] && halt="true"
    jq -n \
      --argjson ok true \
      --argjson storyhook_consecutive_failures "$count" \
      --argjson halt "$halt" \
      --arg display "[forge] loop-state: storyhook_consecutive_failures=$count (halt=$halt)" \
      '{ok: $ok, storyhook_consecutive_failures: $storyhook_consecutive_failures, halt: $halt, display: $display}'
    ;;

  # --- architect-check: persist stories_since_last_architect_review (F098) ---
  # Same problem as storyhook-failure above: execution-loop.md's old Step 7
  # tracked this "in-memory, not persisted" by its own admission, but
  # max_stories_per_session defaults to 1 -- context clears between every
  # single story, so an in-memory counter can never accumulate to its own
  # ">= 3" trigger. Persisting it here is what makes the trigger reachable.
  architect-check)
    case "$WAVE_BOUNDARY" in
      true|false) ;;
      *) echo "Error: --wave-boundary must be 'true' or 'false'" >&2; exit 1 ;;
    esac
    state="$(read_state)"
    current="$(echo "$state" | jq -r '.stories_since_last_architect_review // 0')"
    next=$((current + 1))
    trigger="false"
    if [ "$WAVE_BOUNDARY" = "true" ] || [ "$next" -ge 3 ]; then
      trigger="true"
    fi
    if [ "$trigger" = "true" ]; then
      new_state="$(write_state '
        .stories_since_last_architect_review = 0
        | .updated_at = (now | todate)
      ')"
    else
      new_state="$(write_state --argjson n "$next" '
        .stories_since_last_architect_review = $n
        | .updated_at = (now | todate)
      ')"
    fi
    stories_since="$(echo "$new_state" | jq -r '.stories_since_last_architect_review')"
    jq -n \
      --argjson ok true \
      --argjson trigger "$trigger" \
      --argjson stories_since_last_architect_review "$stories_since" \
      --arg display "[forge] loop-state: architect-check trigger=$trigger (stories_since=$stories_since)" \
      '{ok: $ok, trigger: $trigger, stories_since_last_architect_review: $stories_since_last_architect_review, display: $display}'
    ;;

  *)
    jq -n --arg display "[forge] loop-state: unknown subcommand '$SUBCOMMAND' (expected attempt|done|retry|runaway-check|storyhook-failure|architect-check)" \
      '{ok: false, display: $display}'
    exit 1
    ;;
esac
