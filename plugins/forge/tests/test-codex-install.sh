#!/usr/bin/env bash
# Exercise real Codex installation using an isolated, local marketplace and home.
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORGE_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
AGENTS_ROOT="$(cd "$FORGE_ROOT/../agents" && pwd)"

for name in codex jq python3; do
  command -v "$name" >/dev/null 2>&1 || { printf 'ERROR: %s is required\n' "$name" >&2; exit 1; }
done
SMOKE_ROOT="$(mktemp -d '/private/tmp/forge codex install.XXXXXX')"
trap 'rm -rf "$SMOKE_ROOT"' EXIT
MARKET_ROOT="$SMOKE_ROOT/marketplace"
SMOKE_CODEX_HOME="$SMOKE_ROOT/codex-home"
mkdir -p "$MARKET_ROOT/.agents/plugins" "$MARKET_ROOT/plugins" "$SMOKE_CODEX_HOME"
cp -R "$FORGE_ROOT" "$MARKET_ROOT/plugins/forge"
cp -R "$AGENTS_ROOT" "$MARKET_ROOT/plugins/agents"
cp -R "$FORGE_ROOT/../freshen" "$MARKET_ROOT/plugins/freshen"
cp -R "$FORGE_ROOT/../hook-guard" "$MARKET_ROOT/plugins/hook-guard"
jq -n '{name:"age94-smoke", interface:{displayName:"Forge smoke"}, plugins:
  ["agents", "forge", "freshen", "hook-guard"] | map({name:., source:{source:"local",path:("./plugins/"+.)},
   policy:{installation:"AVAILABLE",authentication:"ON_INSTALL"},category:"Productivity"})
}' > "$MARKET_ROOT/.agents/plugins/marketplace.json"
CODEX_HOME="$SMOKE_CODEX_HOME" codex plugin marketplace add "$MARKET_ROOT" --json > "$SMOKE_ROOT/market.json"
CODEX_HOME="$SMOKE_CODEX_HOME" codex plugin add agents@age94-smoke --json > "$SMOKE_ROOT/agents.json"
CODEX_HOME="$SMOKE_CODEX_HOME" codex plugin add forge@age94-smoke --json > "$SMOKE_ROOT/forge.json"
CODEX_HOME="$SMOKE_CODEX_HOME" codex plugin add freshen@age94-smoke --json > "$SMOKE_ROOT/freshen.json"
CODEX_HOME="$SMOKE_CODEX_HOME" codex plugin add hook-guard@age94-smoke --json > "$SMOKE_ROOT/guard.json"
CODEX_HOME="$SMOKE_CODEX_HOME" codex plugin list --json > "$SMOKE_ROOT/installed.json"
jq -e '[.installed[] | select(.installed and .enabled) | .name] | sort == ["agents","forge","freshen","hook-guard"]' \
  "$SMOKE_ROOT/installed.json" >/dev/null
INSTALLED_MANIFEST="$(find "$SMOKE_CODEX_HOME" -path '*/forge/*/.codex-plugin/plugin.json' -type f -print -quit)"
[ -n "$INSTALLED_MANIFEST" ] || { echo 'ERROR: Forge installed manifest missing' >&2; exit 1; }
INSTALLED_ROOT="$(cd "$(dirname "$INSTALLED_MANIFEST")/.." && pwd)"

# Run contracts from the installed copy, so relative-to-source assumptions fail.
python3 -B -m unittest discover -s "$INSTALLED_ROOT/tests" -p codex_contract_test.py -v
RESOLVED_AGENTS="$(unset AGENTS_PLUGIN_ROOT; CODEX_HOME="$SMOKE_CODEX_HOME" bash "$INSTALLED_ROOT/bin/resolve-dependency.sh" agents)"
for role in domain-researcher software-architect software-engineer qa-engineer project-manager skeptic technical-writer generator evaluator reviewer validator triager ux-designer-cli ux-designer-web ux-designer-mobile security-researcher accessibility-engineer; do
  role_path="$(bash "$RESOLVED_AGENTS/bin/resolve-agent.sh" "$role")"
  [ -f "$role_path" ] || { printf 'ERROR: missing role %s\n' "$role" >&2; exit 1; }
done
for dependency in freshen hook-guard; do
  CODEX_HOME="$SMOKE_CODEX_HOME" bash "$INSTALLED_ROOT/bin/resolve-dependency.sh" "$dependency"
done
mkdir "$SMOKE_ROOT/project"
(
  cd "$SMOKE_ROOT/project"
  unset CLAUDE_PLUGIN_ROOT PLUGIN_ROOT
  bash "$INSTALLED_ROOT/bin/forge-status.sh" > "$SMOKE_ROOT/status.json"
  mkdir .forge
  printf '{"status":"paused","resume":{"command":"/forge resume","summary":"Installed smoke"}}\n' > .forge/state.json
  command="$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$INSTALLED_ROOT/hooks/hooks.json")"
  jq -n --arg cwd "$PWD" '{cwd:$cwd,hook_event_name:"SessionStart"}' | \
    PLUGIN_ROOT="$INSTALLED_ROOT" bash -c "$command" > "$SMOKE_ROOT/context.json"
)
jq -e '.hookSpecificOutput.hookEventName == "SessionStart" and (.hookSpecificOutput.additionalContext | contains("$forge:forge resume"))' "$SMOKE_ROOT/context.json" >/dev/null
printf '%s\n' 'PASS: installed Forge skills, resources, roles, dependencies, status and native hook command'
