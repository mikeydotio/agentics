#!/usr/bin/env bash
# Shared Codex hook adapter helpers. The core transition implementation remains
# host-neutral; adapters translate Codex's hook wire format and environment.

CODEX_HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_PLUGIN_DIR="${PLUGIN_ROOT:-$(cd "$CODEX_HOOK_DIR/../.." && pwd)}"

codex_run_shared_hook() {
  local hook_name="$1" input="$2"
  printf '%s' "$input" | CLAUDE_PLUGIN_ROOT="$CODEX_PLUGIN_DIR" bash "$CODEX_PLUGIN_DIR/hooks/$hook_name"
}

codex_emit_session_start() {
  local output="$1"
  [[ -z "$output" ]] && return 0

  if ! command -v jq >/dev/null 2>&1; then
    echo "freshen Codex hook adapter: jq unavailable; emitting SessionStart context as text" >&2
    printf '%s\n' "$output"
    return 0
  fi

  if printf '%s' "$output" | jq -e 'type == "object"' >/dev/null 2>&1; then
    if printf '%s' "$output" | jq -e '.hookSpecificOutput != null' >/dev/null 2>&1; then
      printf '%s' "$output" | jq -c '.'
      return 0
    fi
    local context
    context="$(printf '%s' "$output" | jq -r '.additionalContext // .systemMessage // empty')"
    [[ -z "$context" ]] && return 0
    jq -cn --arg context "$context" \
      '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$context}}'
    return 0
  fi

  jq -cn --arg context "$output" \
    '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$context}}'
}
