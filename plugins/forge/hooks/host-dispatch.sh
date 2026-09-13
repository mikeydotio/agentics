#!/usr/bin/env bash
# Select the hook host without trusting a target project's cwd for packaged paths.
set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "${1:-}" in
  session-start.sh|session-stop.sh) ;;
  *) echo "forge: invalid hook entrypoint: ${1:-missing}" >&2; exit 2 ;;
esac
export FORGE_HOST=claude
if [ -n "${PLUGIN_ROOT:-}" ]; then
  export FORGE_HOST=codex
  input="$(cat)"
  project="$(jq -er '.cwd | select(type == "string" and startswith("/"))' <<< "$input")" || {
    echo "forge: Codex hook requires an absolute payload cwd" >&2
    exit 0
  }
  # Compatibility is local to this process; stale Claude aliases cannot select cwd.
  export CLAUDE_PROJECT_DIR="$project"
  CLAUDE_PLUGIN_ROOT="$(cd "$HOOKS_DIR/.." && pwd)"
  export CLAUDE_PLUGIN_ROOT
  exec bash "$HOOKS_DIR/$1" <<< "$input"
fi
exec bash "$HOOKS_DIR/$1"
