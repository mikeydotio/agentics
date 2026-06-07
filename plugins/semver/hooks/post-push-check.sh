#!/usr/bin/env bash
# Semver PostToolUse hook — fires after Bash tool use.
# Detects git push to the configured target branch and triggers
# version bump workflow based on .semver/config.yaml settings.
#
# Input:  JSON on stdin from Claude Code PostToolUse event
# Output: JSON on stdout with systemMessage (or nothing for no-op)

set -uo pipefail

# Read stdin
INPUT="$(cat)" || exit 0

# Extract fields via jq
TOOL_NAME="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)" || exit 0
COMMAND="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0
CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)" || exit 0

# Only care about Bash tool
[[ "$TOOL_NAME" != "Bash" ]] && exit 0

# Only care about git push commands
[[ "$COMMAND" != *"git push"* ]] && exit 0

# Locate .semver/config.yaml
CONFIG_FILE="${CWD}/.semver/config.yaml"
[[ ! -f "$CONFIG_FILE" ]] && exit 0

# --- Parse config ---
get_config() {
  local key="$1" default="$2"
  local val
  val=$(grep "^${key}:" "$CONFIG_FILE" 2>/dev/null | sed "s/^${key}:[[:space:]]*//" | tr -d "'\"")
  printf '%s' "${val:-$default}"
}

TRACKING="$(get_config 'tracking' 'false')"
AUTO_BUMP="$(get_config 'auto_bump' 'false')"
AUTO_BUMP_CONFIRM="$(get_config 'auto_bump_confirm' 'true')"
TARGET_BRANCH="$(get_config 'target_branch' 'main')"
VERSION_PREFIX="$(get_config 'version_prefix' 'v')"
GIT_TAGGING="$(get_config 'git_tagging' 'true')"

# Tracking off -> silent exit
[[ "$TRACKING" != "true" ]] && exit 0

# Suppress auto-bump during forge execution — forge manages its own commit flow
FORGE_STATE="${CWD}/.forge/state.json"
if [[ -f "$FORGE_STATE" ]]; then
  FORGE_STATUS="$(jq -r '.status // empty' "$FORGE_STATE" 2>/dev/null)"
  [[ "$FORGE_STATUS" == "running" ]] && exit 0
fi

# Check if push was to the target branch
PUSH_TO_TARGET=false

# Match: "git push origin main", "git push origin main:main", "git push -u origin main"
if printf '%s' "$COMMAND" | grep -qE "git push[[:space:]]+.*\b${TARGET_BRANCH}\b"; then
  PUSH_TO_TARGET=true
fi

# Match: bare "git push" or "git push -u origin" (pushes current branch)
if [[ "$PUSH_TO_TARGET" == "false" ]]; then
  if printf '%s' "$COMMAND" | grep -qE "^git push[[:space:]]*$|^git push[[:space:]]+-"; then
    CURRENT_BRANCH="$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
    if [[ "$CURRENT_BRANCH" == "$TARGET_BRANCH" ]]; then
      PUSH_TO_TARGET=true
    fi
  fi
fi

[[ "$PUSH_TO_TARGET" == "false" ]] && exit 0

# --- Gather version info ---
VERSION_FILE="${CWD}/VERSION"
CURRENT_VERSION="unknown"
[[ -f "$VERSION_FILE" ]] && CURRENT_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"

# Use VERSION-commit as primary anchor (not tags)
LAST_BUMP_COMMIT="$(git -C "$CWD" log -1 --format=%H -- VERSION 2>/dev/null || echo "")"
if [[ -n "$LAST_BUMP_COMMIT" ]]; then
  COMMIT_COUNT="$(git -C "$CWD" rev-list "${LAST_BUMP_COMMIT}..HEAD" --count 2>/dev/null || echo "unknown")"
  SINCE_MSG="${COMMIT_COUNT} commit(s) since last version change"
else
  COMMIT_COUNT="$(git -C "$CWD" rev-list HEAD --count 2>/dev/null || echo "unknown")"
  SINCE_MSG="${COMMIT_COUNT} commit(s) total (no version set yet)"
fi

# Deterministic bump recommendation from conventional commits (cheap: reads
# commit subjects only, never diffs). Replaces asking the agent to "analyze the
# git log" — saves tokens and avoids pulling an unbounded log into context.
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RECO_JSON="$(cd "$CWD" 2>/dev/null && python3 "${PLUGIN_ROOT}/bin/semver-cli" recommend 2>/dev/null || true)"
RECO=""; RECO_RATIONALE=""
if [[ -n "$RECO_JSON" ]]; then
  RECO="$(printf '%s' "$RECO_JSON" | jq -r '.recommended // empty' 2>/dev/null || true)"
  RECO_RATIONALE="$(printf '%s' "$RECO_JSON" | jq -r '.rationale // empty' 2>/dev/null || true)"
fi
if [[ -n "$RECO" ]]; then
  REC_PHRASE="Recommended bump: ${RECO} (${RECO_RATIONALE})."
  REC_LEVEL="$RECO"
else
  REC_PHRASE="Review the changes to choose a bump level."
  REC_LEVEL="<major|minor|patch>"
fi

# --- Build output based on config state ---
emit_message() {
  local msg="$1"
  jq -n --arg msg "$msg" '{"systemMessage":$msg}'
}

if [[ "$AUTO_BUMP" != "true" ]]; then
  # Nudge mode
  emit_message "[semver] Push to ${TARGET_BRANCH} detected. Current version: ${CURRENT_VERSION}. ${SINCE_MSG}. ${REC_PHRASE} Run /semver bump ${REC_LEVEL} to create a new version release."
elif [[ "$AUTO_BUMP_CONFIRM" == "true" ]]; then
  # Auto-bump with confirmation
  emit_message "[semver] Auto-bump: push to ${TARGET_BRANCH} detected. Current version: ${CURRENT_VERSION}. ${SINCE_MSG}. ${REC_PHRASE} Confirm with the user, then run /semver bump ${REC_LEVEL}."
else
  # Auto-bump without confirmation
  emit_message "[semver] Auto-bump: push to ${TARGET_BRANCH} detected. Current version: ${CURRENT_VERSION}. ${SINCE_MSG}. ${REC_PHRASE} Run /semver bump ${REC_LEVEL} now — no user confirmation needed."
fi

exit 0
