#!/usr/bin/env bash
# Resolve a catalog name to its canonical definition without allowing path input.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS_DIR="$(cd "$SCRIPT_DIR/../agents" && pwd)"

list_agents() {
  find "$AGENTS_DIR" -maxdepth 1 -type f -name '*.md' ! -name '_*' -exec basename {} .md \; | sort
}

if [ "${1:-}" = "--list" ] && [ "$#" -eq 1 ]; then
  list_agents
  exit 0
fi

if [ "$#" -ne 1 ]; then
  printf 'Usage: %s <agent-name> | --list\n' "$(basename "$0")" >&2
  exit 2
fi

agent_name="$1"
case "$agent_name" in
  ''|*[!a-z0-9-]*)
    printf 'agents: invalid agent name: %s\n' "$agent_name" >&2
    exit 2
    ;;
esac

agent_file="$AGENTS_DIR/$agent_name.md"
if [ ! -f "$agent_file" ]; then
  printf 'agents: unknown agent: %s\n' "$agent_name" >&2
  printf 'available: %s\n' "$(list_agents | paste -sd, -)" >&2
  exit 1
fi

printf '%s\n' "$agent_file"
