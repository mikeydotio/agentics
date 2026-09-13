#!/usr/bin/env bash
# Install Council and its Agents dependency from a disposable Codex marketplace.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COUNCIL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AGENTS_ROOT="$(cd "$COUNCIL_ROOT/../agents" && pwd)"

for command_name in codex jq python3; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'ERROR: %s is required; Council packaging was not verified\n' "$command_name" >&2
    exit 1
  }
done

SMOKE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/council-codex-install.XXXXXX")"
MARKET_ROOT="$SMOKE_ROOT/marketplace"
SMOKE_CODEX_HOME="$SMOKE_ROOT/codex-home"
mkdir -p "$MARKET_ROOT/.agents/plugins" "$MARKET_ROOT/plugins" "$SMOKE_CODEX_HOME"
trap 'rm -rf "$SMOKE_ROOT"' EXIT

cp -R "$COUNCIL_ROOT" "$MARKET_ROOT/plugins/council"
cp -R "$AGENTS_ROOT" "$MARKET_ROOT/plugins/agents"
jq -n '
  {
    name: "age89-council",
    interface: {displayName: "Council Codex Smoke"},
    plugins: [
      {
        name: "agents",
        source: {source: "local", path: "./plugins/agents"},
        policy: {installation: "AVAILABLE", authentication: "ON_INSTALL"},
        category: "Productivity"
      },
      {
        name: "council",
        source: {source: "local", path: "./plugins/council"},
        policy: {installation: "AVAILABLE", authentication: "ON_INSTALL"},
        category: "Productivity"
      }
    ]
  }
' > "$MARKET_ROOT/.agents/plugins/marketplace.json"

CODEX_HOME="$SMOKE_CODEX_HOME" codex plugin marketplace add "$MARKET_ROOT" --json >/dev/null
CODEX_HOME="$SMOKE_CODEX_HOME" codex plugin add agents@age89-council --json >/dev/null
CODEX_HOME="$SMOKE_CODEX_HOME" codex plugin add council@age89-council --json >/dev/null
CODEX_HOME="$SMOKE_CODEX_HOME" codex plugin list --json > "$SMOKE_ROOT/installed.json"

jq -e '[.installed[] | select(.enabled == true) | .name] | sort == ["agents", "council"]' \
  "$SMOKE_ROOT/installed.json" >/dev/null

INSTALLED_MANIFEST="$(find "$SMOKE_CODEX_HOME" -path '*/council/*/.codex-plugin/plugin.json' -type f -print -quit)"
[ -n "$INSTALLED_MANIFEST" ]
INSTALLED_ROOT="$(cd "$(dirname "$INSTALLED_MANIFEST")/.." && pwd)"

[ -f "$INSTALLED_ROOT/skills/council-vote/SKILL.md" ]
[ -f "$INSTALLED_ROOT/codex/skills/council-vote/SKILL.md" ]
[ -f "$INSTALLED_ROOT/claude/skills/council-vote/SKILL.md" ]
[ -f "$INSTALLED_ROOT/codex/references/orchestration.md" ]

RESOLVED_AGENTS="$(CODEX_HOME="$SMOKE_CODEX_HOME" bash "$INSTALLED_ROOT/bin/resolve-agents-root.sh")"
[ -f "$RESOLVED_AGENTS/bin/resolve-agent.sh" ]
[ "$(bash "$RESOLVED_AGENTS/bin/resolve-agent.sh" --list | wc -l | tr -d ' ')" = "28" ]

# Execute the installed payload, not the source helper or a fake implementation.
export PYTHONDONTWRITEBYTECODE=1
for host_name in claude codex; do
  council_dir="$SMOKE_ROOT/state smoke $host_name"
  jq -n --arg host "$host_name" '{question:"Which migration?",chair:"packaging-smoke",
    host:$host,archetypes:["architect","database","challenger"]}' \
    | python3 -W error "$INSTALLED_ROOT/bin/council-state.py" init "$council_dir" \
    > "$SMOKE_ROOT/state-init.json"
  jq -e '.ok and .state.status == "ready" and (.state.seats | length == 3)' \
    "$SMOKE_ROOT/state-init.json" >/dev/null
  jq '{revision:.state.revision,phase:"research"}' "$SMOKE_ROOT/state-init.json" \
    | python3 -W error "$INSTALLED_ROOT/bin/council-state.py" begin-phase "$council_dir" \
    > "$SMOKE_ROOT/state-phase.json"
  jq -e '.ok and .state.status == "running" and
    (.state.hard_deadline - .state.phase_started == 1500) and
    ([.actions[] | select(.kind == "dispatch")] | length == 3)' \
    "$SMOKE_ROOT/state-phase.json" >/dev/null
  jq '{revision:.state.revision,outcome:"abort",reason:"packaging smoke complete"}' \
    "$SMOKE_ROOT/state-phase.json" \
    | python3 -W error "$INSTALLED_ROOT/bin/council-state.py" finish "$council_dir" \
    > "$SMOKE_ROOT/state-final.json"
  jq -e '.ok and .state.status == "aborted"' "$SMOKE_ROOT/state-final.json" >/dev/null
  [ -s "$council_dir/ABORT.md" ]
  [ -s "$council_dir/STATE.json" ]
  [ ! -e "$council_dir/DECISION.md" ]
done

printf 'PASS: installed Council helper executes for both hosts with its 28-role Agents dependency\n'
