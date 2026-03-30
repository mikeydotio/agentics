#!/usr/bin/env bash
# Work Stop hook — auto-save handoff, release lock, set status to paused.
# Only acts if pilot is actively running.
#
# Input:  JSON on stdin from Claude Code Stop event
# Output: JSON on stdout (or nothing for no-op)
#
# CRITICAL: Uses jq for all JSON construction.

set -uo pipefail

# Locate project directory
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-}"

if [[ -z "$PROJECT_DIR" ]]; then
  INPUT="$(cat)" || exit 0
  PROJECT_DIR="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)" || exit 0
else
  cat > /dev/null 2>&1 || true
fi

[[ -z "$PROJECT_DIR" ]] && exit 0

# Check for pilot state
STATE_FILE="${PROJECT_DIR}/.pilot/state.json"
[[ ! -f "$STATE_FILE" ]] && exit 0

# Verify jq is available
if ! command -v jq &>/dev/null; then
  exit 0
fi

# Read status — only act if running
STATUS="$(jq -r '.status // empty' "$STATE_FILE" 2>/dev/null)" || exit 0
if [[ "$STATUS" != "running" ]]; then
  exit 0
fi

# Derive session duration from lock
LOCK_FILE="${PROJECT_DIR}/.pilot/lock.json"
DURATION="unknown"
if [[ -f "$LOCK_FILE" ]]; then
  ACQUIRED_AT="$(jq -r '.acquired_at // empty' "$LOCK_FILE" 2>/dev/null)"
  if [[ -n "$ACQUIRED_AT" ]]; then
    START_EPOCH="$(date -d "$ACQUIRED_AT" +%s 2>/dev/null || echo "")"
    NOW_EPOCH="$(date +%s)"
    if [[ -n "$START_EPOCH" ]]; then
      DURATION_SECS=$(( NOW_EPOCH - START_EPOCH ))
      DURATION="${DURATION_SECS}s"
    fi
  fi
fi

# Write handoff
HANDOFF_FILE="${PROJECT_DIR}/.pilot/handoff.md"
STORIES_ATTEMPTED="$(jq -r '.stories_attempted // 0' "$STATE_FILE" 2>/dev/null)"
STORIES_THIS="$(jq -r '.stories_this_session // 0' "$STATE_FILE" 2>/dev/null)"

cat > "$HANDOFF_FILE" <<EOF
# Work Handoff

## Session Summary
- **Duration**: ${DURATION}
- **Stories completed this session**: ${STORIES_THIS}
- **Stories attempted total**: ${STORIES_ATTEMPTED}
- **Status**: Session ended (stop hook)

## What Happened
Session was terminated (Claude Code stop event). Handoff auto-saved by stop hook.

## What's Next
Run \`/pilot resume\` or wait for auto-resume trigger.
EOF

# Generate storyhook handoff if story CLI is available
if command -v story &>/dev/null; then
  STORY_HANDOFF="$(cd "$PROJECT_DIR" && story handoff --since "${DURATION}" 2>/dev/null || true)"
  if [[ -n "$STORY_HANDOFF" ]]; then
    printf '\n## Storyhook Handoff\n%s\n' "$STORY_HANDOFF" >> "$HANDOFF_FILE"
  fi
fi

# Update state to paused
jq '.status = "paused" | .updated_at = (now | todate)' "$STATE_FILE" > "${STATE_FILE}.tmp" && \
  mv "${STATE_FILE}.tmp" "$STATE_FILE"

# Increment sessions_completed
jq '.sessions_completed = (.sessions_completed + 1)' "$STATE_FILE" > "${STATE_FILE}.tmp" && \
  mv "${STATE_FILE}.tmp" "$STATE_FILE"

# Release lock
rm -f "$LOCK_FILE"

exit 0
