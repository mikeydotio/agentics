#!/usr/bin/env bash
# Forge SessionStart hook — injects recovery context when forge is active.
# Reads .forge/state.json and optionally the newest .forge/handoffs/handoff-*.md.
# Outputs nothing (no-op) if forge is not active in this project.
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

# Check for forge state
STATE_FILE="${PROJECT_DIR}/.forge/state.json"
[[ ! -f "$STATE_FILE" ]] && exit 0

# Verify jq is available
if ! command -v jq &>/dev/null; then
  exit 0
fi

# Read all fields in one jq call (including pre-computed resume context if available)
RESUME_JSON="$(jq -r '{
  status: .status,
  sessions: (.sessions_completed // 0),
  stories: (.stories_attempted // 0),
  retries: (.total_retries // 0),
  resume: (.resume // null)
}' "$STATE_FILE" 2>/dev/null)" || exit 0

STATUS="$(printf '%s' "$RESUME_JSON" | jq -r '.status // empty')"
[[ -z "$STATUS" ]] && exit 0
[[ "$STATUS" != "running" && "$STATUS" != "paused" ]] && exit 0

SESSIONS="$(printf '%s' "$RESUME_JSON" | jq -r '.sessions')"
STORIES="$(printf '%s' "$RESUME_JSON" | jq -r '.stories')"
RETRIES="$(printf '%s' "$RESUME_JSON" | jq -r '.retries')"
RESUME_SUM="$(printf '%s' "$RESUME_JSON" | jq -r '.resume.summary // empty')"
RESUME_CMD="$(printf '%s' "$RESUME_JSON" | jq -r '.resume.command // empty')"
RESUME_HF="$(printf '%s' "$RESUME_JSON" | jq -r '.resume.handoff_file // empty')"

CTX="Forge ${STATUS}. Sessions: ${SESSIONS}, Stories: ${STORIES}, Retries: ${RETRIES}."

if [[ -n "$RESUME_SUM" ]]; then
  # Pre-computed path — stop hook or orchestrator wrote resume context
  CTX="${CTX} ${RESUME_SUM}"
  [[ -n "$RESUME_CMD" ]] && CTX="${CTX} Resume: ${RESUME_CMD}."
  [[ -n "$RESUME_HF" ]] && CTX="${CTX} Handoff: .forge/${RESUME_HF}"
else
  # Backward compat — old state.json without resume object
  # Only emit handoff filename, never content
  HANDOFF_DIR="${PROJECT_DIR}/.forge/handoffs"
  if [[ -d "$HANDOFF_DIR" ]]; then
    HANDOFF_FILE="$(ls -t "$HANDOFF_DIR"/handoff-*.md 2>/dev/null | head -1)"
    [[ -n "$HANDOFF_FILE" ]] && CTX="${CTX} Handoff: $(basename "$HANDOFF_FILE")"
  fi
fi

jq -n --arg ctx "$CTX" '{"additionalContext": $ctx}'

exit 0
