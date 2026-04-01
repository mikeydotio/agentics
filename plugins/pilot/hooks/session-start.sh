#!/usr/bin/env bash
# Pilot SessionStart hook — injects recovery context when pilot is active.
# Reads .pilot/state.json and optionally .pilot/handoff.md.
# Outputs nothing (no-op) if pilot is not active in this project.
#
# Input:  JSON on stdin from Claude Code SessionStart event
# Output: JSON on stdout with additionalContext (or nothing for no-op)
#
# CRITICAL: Uses jq for all JSON construction — never printf with string escaping.

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

# Read status
STATUS="$(jq -r '.status // empty' "$STATE_FILE" 2>/dev/null)" || exit 0
[[ -z "$STATUS" ]] && exit 0

# Only inject context for running or paused pilot
if [[ "$STATUS" != "running" && "$STATUS" != "paused" ]]; then
  exit 0
fi

# Build context message
STORIES_ATTEMPTED="$(jq -r '.stories_attempted // 0' "$STATE_FILE" 2>/dev/null)"
TOTAL_RETRIES="$(jq -r '.total_retries // 0' "$STATE_FILE" 2>/dev/null)"
SESSIONS_COMPLETED="$(jq -r '.sessions_completed // 0' "$STATE_FILE" 2>/dev/null)"

CTX="Work is ${STATUS}. Sessions: ${SESSIONS_COMPLETED}, Stories attempted: ${STORIES_ATTEMPTED}, Retries: ${TOTAL_RETRIES}."

# Append most recent handoff context if available
HANDOFF_DIR="${PROJECT_DIR}/.pilot/handoffs"
if [[ -d "$HANDOFF_DIR" ]]; then
  HANDOFF_FILE="$(ls -t "$HANDOFF_DIR"/handoff-*.md 2>/dev/null | head -1)"
  if [[ -n "$HANDOFF_FILE" ]] && [[ -f "$HANDOFF_FILE" ]]; then
    HANDOFF_CONTENT="$(cat "$HANDOFF_FILE" 2>/dev/null)"
    if [[ -n "$HANDOFF_CONTENT" ]]; then
      CTX="${CTX} Last handoff ($(basename "$HANDOFF_FILE")): ${HANDOFF_CONTENT}"
    fi
  fi
fi

# Use jq for safe JSON construction (handles quotes, backticks, newlines in handoff content)
jq -n --arg ctx "$CTX" '{"additionalContext": $ctx}'

exit 0
