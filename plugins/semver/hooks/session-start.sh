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

GIT_TAGGING="$(get_config 'git_tagging' 'true')"

# Read current version
VERSION_FILE="${PROJECT_DIR}/VERSION"
CURRENT_VERSION="not set"
[[ -f "$VERSION_FILE" ]] && CURRENT_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"

# Derive project name from directory basename
PROJECT_NAME="$(basename "$PROJECT_DIR")"

# Build minimal status line: "<Project>: <version>"
MSG="${PROJECT_NAME} version: ${CURRENT_VERSION}"

# Append desync warning only if git_tagging is on and there's an issue
if [[ "$GIT_TAGGING" == "true" ]]; then
  LAST_TAG="$(git -C "$PROJECT_DIR" describe --tags --abbrev=0 2>/dev/null || echo "")"
  if [[ -n "$LAST_TAG" ]]; then
    if [[ "$CURRENT_VERSION" != "$LAST_TAG" ]]; then
      MSG="${MSG} [!DESYNC] VERSION says ${CURRENT_VERSION} but latest tag is ${LAST_TAG} — run /semver validate"
    fi
  elif [[ "$CURRENT_VERSION" != "not set" ]]; then
    TAG_CHECK="$(git -C "$PROJECT_DIR" tag -l "$CURRENT_VERSION" 2>/dev/null || echo "")"
    if [[ -z "$TAG_CHECK" ]]; then
      MSG="${MSG} [!NO_TAG] No git tag found for ${CURRENT_VERSION} — run /semver validate"
    fi
  fi
fi

# Escape for JSON
MSG="$(printf '%s' "$MSG" | sed 's/"/\\"/g')"
printf '{"systemMessage":"%s"}\n' "$MSG"

exit 0
