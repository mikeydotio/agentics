#!/usr/bin/env bash
# Route the shared hook manifest to the native host implementation. Codex sets
# PLUGIN_ROOT; Claude Code does not. Missing adapters fail open with a visible
# diagnostic so a packaging mistake cannot block a session.
set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$HOOKS_DIR/.." && pwd)"
RESOLVE_ONLY=0

if [[ "${1:-}" == "--resolve" ]]; then
  RESOLVE_ONLY=1
  shift
fi

HOOK_NAME="${1:-}"
if [[ -z "$HOOK_NAME" || "$HOOK_NAME" == */* || ! "$HOOK_NAME" =~ ^[A-Za-z0-9._-]+\.sh$ ]]; then
  echo "freshen hook dispatcher: invalid hook name '${HOOK_NAME}'" >&2
  exit 0
fi

if [[ -n "${PLUGIN_ROOT+x}" ]]; then
  HOST="codex"
  TARGET="$HOOKS_DIR/codex/$HOOK_NAME"
else
  HOST="claude"
  TARGET="$HOOKS_DIR/$HOOK_NAME"
fi

if [[ "$RESOLVE_ONLY" -eq 1 ]]; then
  printf '%s:%s\n' "$HOST" "$TARGET"
  exit 0
fi

if [[ ! -f "$TARGET" ]]; then
  echo "freshen hook dispatcher: ${HOST} adapter missing: ${TARGET}" >&2
  exit 0
fi

export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$PLUGIN_DIR}"
exec bash "$TARGET"
