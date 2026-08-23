#!/usr/bin/env bash
# Install Agents from a disposable one-plugin Codex marketplace and verify the
# cached package exposes the dispatcher, Codex implementation, and full catalog.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

for command_name in codex jq; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'SKIP: %s is not installed; Codex Agents packaging smoke not run\n' "$command_name"
    exit 0
  }
done

SMOKE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/agents-codex-install.XXXXXX")"
MARKET_ROOT="$SMOKE_ROOT/marketplace"
SMOKE_CODEX_HOME="$SMOKE_ROOT/codex-home"
mkdir -p "$MARKET_ROOT/.agents/plugins" "$MARKET_ROOT/plugins" "$SMOKE_CODEX_HOME"
trap 'rm -rf "$SMOKE_ROOT"' EXIT

cp -R "$PLUGIN_ROOT" "$MARKET_ROOT/plugins/agents"
jq -n '
  {
    name: "age88-agents",
    interface: {displayName: "Agents Codex Smoke"},
    plugins: [
      {
        name: "agents",
        source: {source: "local", path: "./plugins/agents"},
        policy: {installation: "AVAILABLE", authentication: "ON_INSTALL"},
        category: "Productivity"
      }
    ]
  }
' > "$MARKET_ROOT/.agents/plugins/marketplace.json"

CODEX_HOME="$SMOKE_CODEX_HOME" codex plugin marketplace add "$MARKET_ROOT" --json >/dev/null
CODEX_HOME="$SMOKE_CODEX_HOME" codex plugin add agents@age88-agents --json >/dev/null
CODEX_HOME="$SMOKE_CODEX_HOME" codex plugin list --json > "$SMOKE_ROOT/installed.json"

jq -e '
  .. | objects
  | select(.name? == "agents" or .id? == "agents@age88-agents")
' "$SMOKE_ROOT/installed.json" >/dev/null

INSTALLED_MANIFEST="$(find "$SMOKE_CODEX_HOME" -path '*/.codex-plugin/plugin.json' -type f -print -quit)"
[ -n "$INSTALLED_MANIFEST" ]
INSTALLED_ROOT="$(cd "$(dirname "$INSTALLED_MANIFEST")/.." && pwd)"

[ -f "$INSTALLED_ROOT/skills/agents/SKILL.md" ]
[ -f "$INSTALLED_ROOT/codex/skills/agents/SKILL.md" ]
[ -f "$INSTALLED_ROOT/claude/skills/agents/SKILL.md" ]
[ "$(find "$INSTALLED_ROOT/agents" -maxdepth 1 -type f -name '*.md' ! -name '_*' | wc -l | tr -d ' ')" = "28" ]
[ "$(bash "$INSTALLED_ROOT/bin/resolve-agent.sh" reviewer)" = "$INSTALLED_ROOT/agents/reviewer.md" ]

printf 'PASS: Codex installed Agents with dual-host routing and all 28 specialist roles\n'
