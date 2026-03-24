#!/usr/bin/env bash
# Semver SessionStart hook — injects version context at session start.
# Reads .semver/config.yaml and VERSION from the project directory.
# Outputs nothing (no-op) if semver is not active in this project.
#
# Input:  JSON on stdin from Claude Code SessionStart event
# Output: JSON on stdout with systemMessage (or nothing for no-op)

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

# Check for config
CONFIG_FILE="${PROJECT_DIR}/.semver/config.yaml"
[[ ! -f "$CONFIG_FILE" ]] && exit 0

# Parse config
get_config() {
  local key="$1" default="$2"
  local val
  val=$(grep "^${key}:" "$CONFIG_FILE" 2>/dev/null | sed "s/^${key}:[[:space:]]*//" | tr -d "'\"")
  printf '%s' "${val:-$default}"
}

TRACKING="$(get_config 'tracking' 'false')"
[[ "$TRACKING" != "true" ]] && exit 0

AUTO_BUMP="$(get_config 'auto_bump' 'false')"
VERSION_PREFIX="$(get_config 'version_prefix' 'v')"
TARGET_BRANCH="$(get_config 'target_branch' 'main')"

# Read current version
VERSION_FILE="${PROJECT_DIR}/VERSION"
CURRENT_VERSION="not set"
[[ -f "$VERSION_FILE" ]] && CURRENT_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"

# Count commits since last tag
LAST_TAG="$(git -C "$PROJECT_DIR" describe --tags --abbrev=0 2>/dev/null || echo "")"
if [[ -n "$LAST_TAG" ]]; then
  COMMIT_COUNT="$(git -C "$PROJECT_DIR" rev-list "${LAST_TAG}..HEAD" --count 2>/dev/null || echo "0")"
  TAG_INFO="${COMMIT_COUNT} commit(s) since ${LAST_TAG}"
else
  TAG_INFO="no version tags yet"
fi

# Build status line
AUTO_BUMP_STATUS="off"
[[ "$AUTO_BUMP" == "true" ]] && AUTO_BUMP_STATUS="on (target: ${TARGET_BRANCH})"

MSG="[semver] Version: ${CURRENT_VERSION} | ${TAG_INFO} | Auto-bump: ${AUTO_BUMP_STATUS}"

# Escape for JSON
MSG="$(printf '%s' "$MSG" | sed 's/"/\\"/g')"
printf '{"systemMessage":"%s"}\n' "$MSG"

exit 0
