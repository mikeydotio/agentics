#!/usr/bin/env bash
# Locate the separately installed Agents plugin without assuming a source checkout.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COUNCIL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

valid_agents_root() {
  local candidate="$1"
  [ -d "$candidate/agents" ] \
    && [ -f "$candidate/bin/resolve-agent.sh" ] \
    && [ -f "$candidate/references/agent-catalog.md" ]
}

emit_if_valid() {
  local candidate="$1"
  if valid_agents_root "$candidate"; then
    (cd "$candidate" && pwd -P)
    return 0
  fi
  return 1
}

if [ -n "${AGENTS_PLUGIN_ROOT:-}" ]; then
  emit_if_valid "$AGENTS_PLUGIN_ROOT" || {
    printf 'council: AGENTS_PLUGIN_ROOT is not a valid Agents plugin: %s\n' "$AGENTS_PLUGIN_ROOT" >&2
    exit 2
  }
  exit 0
fi

# Source checkouts and Claude's side-by-side plugin cache use this shape.
if emit_if_valid "$COUNCIL_ROOT/../agents"; then
  exit 0
fi

# Codex caches each marketplace plugin under <market>/<name>/<version>.
codex_home="${CODEX_HOME:-${HOME:?}/.codex}"
if [ -d "$codex_home/plugins/cache" ]; then
  while IFS= read -r manifest; do
    candidate="$(cd "$(dirname "$manifest")/.." && pwd -P)"
    if emit_if_valid "$candidate"; then
      exit 0
    fi
  done < <(find "$codex_home/plugins/cache" -path '*/agents/*/.codex-plugin/plugin.json' -type f -print 2>/dev/null | sort -r)
fi

# Local marketplaces expose the original source path through the Codex registry.
if command -v codex >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  registry_json="$(codex plugin list --json 2>/dev/null || true)"
  if jq -e . >/dev/null 2>&1 <<<"$registry_json"; then
    while IFS= read -r candidate; do
      [ -n "$candidate" ] || continue
      if emit_if_valid "$candidate"; then
        exit 0
      fi
    done < <(jq -r '.installed[]? | select(.name == "agents" and .installed == true and .enabled == true) | .source.path // empty' <<<"$registry_json")
  fi
fi

printf '%s\n' 'council: the Agents plugin is required but no enabled installation could be resolved' >&2
printf '%s\n' 'Install and enable Agents from the same marketplace, then start a new Codex session.' >&2
exit 1
