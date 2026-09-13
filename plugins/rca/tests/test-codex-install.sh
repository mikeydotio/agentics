#!/usr/bin/env bash
# Exercise real Codex installation using an isolated, local marketplace and home.
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RCA_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
AGENTS_ROOT="$(cd "$RCA_ROOT/../agents" && pwd)"

for name in codex jq python3; do
  command -v "$name" >/dev/null 2>&1 || { printf 'ERROR: %s is required\n' "$name" >&2; exit 1; }
done
SMOKE_ROOT="$(mktemp -d '/private/tmp/rca codex install.XXXXXX')"
trap 'rm -rf "$SMOKE_ROOT"' EXIT
MARKET_ROOT="$SMOKE_ROOT/marketplace"
SMOKE_CODEX_HOME="$SMOKE_ROOT/codex-home"
mkdir -p "$MARKET_ROOT/.agents/plugins" "$MARKET_ROOT/plugins" "$SMOKE_CODEX_HOME"
cp -R "$RCA_ROOT" "$MARKET_ROOT/plugins/rca"
cp -R "$AGENTS_ROOT" "$MARKET_ROOT/plugins/agents"
jq -n '{name:"age93-smoke", interface:{displayName:"RCA smoke"}, plugins:
  ["agents", "rca"] | map({name:., source:{source:"local",path:("./plugins/"+.)},
   policy:{installation:"AVAILABLE",authentication:"ON_INSTALL"},category:"Productivity"})
}' > "$MARKET_ROOT/.agents/plugins/marketplace.json"
CODEX_HOME="$SMOKE_CODEX_HOME" codex plugin marketplace add "$MARKET_ROOT" --json > "$SMOKE_ROOT/market.json"
CODEX_HOME="$SMOKE_CODEX_HOME" codex plugin add agents@age93-smoke --json > "$SMOKE_ROOT/agents.json"
CODEX_HOME="$SMOKE_CODEX_HOME" codex plugin add rca@age93-smoke --json > "$SMOKE_ROOT/rca.json"
CODEX_HOME="$SMOKE_CODEX_HOME" codex plugin list --json > "$SMOKE_ROOT/installed.json"
jq -e '[.installed[] | select(.installed and .enabled) | .name] | sort == ["agents","rca"]' \
  "$SMOKE_ROOT/installed.json" >/dev/null
INSTALLED_MANIFEST="$(find "$SMOKE_CODEX_HOME" -path '*/rca/*/.codex-plugin/plugin.json' -type f -print -quit)"
[ -n "$INSTALLED_MANIFEST" ] || { echo 'ERROR: RCA installed manifest missing' >&2; exit 1; }
INSTALLED_ROOT="$(cd "$(dirname "$INSTALLED_MANIFEST")/.." && pwd)"
DELIVERY_TEST_BIN="$INSTALLED_ROOT/bin" python3 -B -W error "$RCA_ROOT/../agents/tests/test_delivery.py"


# Run contracts from the installed copy, so relative-to-source assumptions fail.
python3 -B -m unittest discover -s "$INSTALLED_ROOT/tests" -p codex_contract_test.py -v
RESOLVED_AGENTS="$(unset AGENTS_PLUGIN_ROOT; CODEX_HOME="$SMOKE_CODEX_HOME" bash "$INSTALLED_ROOT/bin/resolve-agents-root.sh")"
for role in qa-engineer investigator evidence-collector experimenter hypothesis-challenger \
            software-architect software-engineer technical-writer; do
  role_path="$(bash "$RESOLVED_AGENTS/bin/resolve-agent.sh" "$role")"
  [ -f "$role_path" ] || { printf 'ERROR: missing role %s\n' "$role" >&2; exit 1; }
done
mkdir "$SMOKE_ROOT/project"
(
  cd "$SMOKE_ROOT/project"
  unset CLAUDE_PLUGIN_ROOT PLUGIN_ROOT
  bash "$INSTALLED_ROOT/bin/rca-status.sh" > "$SMOKE_ROOT/status.json"
  bash "$INSTALLED_ROOT/bin/rca-repro.sh" run --cmd 'printf known-failure >&2; exit 1' --runs 1 \
    > "$SMOKE_ROOT/repro.json"
)
jq -e '.ok and .count == 0' "$SMOKE_ROOT/status.json" >/dev/null
jq -e '.ok and .failure_rate == 1 and (.last_failure_tail | contains("known-failure"))' \
  "$SMOKE_ROOT/repro.json" >/dev/null
printf '%s\n' 'PASS: installed RCA skills, resources, eight roles, status, and reproduction'
