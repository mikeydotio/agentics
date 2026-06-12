#!/usr/bin/env bash
# Atlas SessionStart hook — injects map staleness context at session start.
# Outputs nothing (no-op) if the project has no atlas map.
#
# The map INDEX itself reaches context via the @docs/atlas/INDEX.md import in
# the project's CLAUDE.md (works for everyone, plugin installed or not). This
# hook adds only the dynamic part: the staleness tier line, and at tier 3 an
# explicit instruction to disregard the imported INDEX.
#
# Input:  JSON on stdin from Claude Code SessionStart event
# Output: JSON on stdout with additionalContext (or nothing for no-op)

set -uo pipefail

# Locate project directory
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-}"

# If CLAUDE_PROJECT_DIR not set, try to get cwd from stdin
if [[ -z "$PROJECT_DIR" ]]; then
  INPUT="$(cat)" || exit 0
  PROJECT_DIR="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)" || exit 0
else
  # Consume stdin even if we don't need it (avoid broken pipe)
  cat > /dev/null 2>&1 || true
fi

[[ -z "$PROJECT_DIR" ]] && exit 0

# Bail fast when this project has no atlas map
[[ ! -f "${PROJECT_DIR}/docs/atlas/INDEX.md" ]] && exit 0

# Hard dependencies; stay silent rather than break session start
command -v python3 >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI="${SCRIPT_DIR}/../bin/atlas-cli"
[[ ! -f "$CLI" ]] && exit 0

STATUS="$(python3 "$CLI" --project-dir "$PROJECT_DIR" status --for-hook 2>/dev/null)" || exit 0

TIER="$(printf '%s' "$STATUS" | jq -r '.tier // 0' 2>/dev/null)" || exit 0
MSG="$(printf '%s' "$STATUS" | jq -r '.message // empty' 2>/dev/null)" || exit 0

# Tier 0: the map is current — the imported INDEX speaks for itself.
[[ "$TIER" == "0" || -z "$MSG" ]] && exit 0

# Output via jq for safe JSON encoding
jq -n --arg msg "$MSG" '{"additionalContext":$msg}'

exit 0
