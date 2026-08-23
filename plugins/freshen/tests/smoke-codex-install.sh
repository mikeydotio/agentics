#!/usr/bin/env bash
# Install Freshen from a disposable one-plugin Codex marketplace and verify the
# installed copy exposes one skill plus the Codex hook adapters. No model call.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

for command_name in codex jq; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'SKIP: %s is not installed; Codex Freshen packaging smoke not run\n' "$command_name"
    exit 0
  }
done

SMOKE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/freshen-codex-install.XXXXXX")"
MARKET_ROOT="$SMOKE_ROOT/marketplace"
SMOKE_CODEX_HOME="$SMOKE_ROOT/codex-home"
mkdir -p "$MARKET_ROOT/.agents/plugins" "$MARKET_ROOT/plugins" "$SMOKE_CODEX_HOME"
trap 'rm -rf "$SMOKE_ROOT"' EXIT

cp -R "$PLUGIN_DIR" "$MARKET_ROOT/plugins/freshen"
jq -n '
  {
    name: "age87-freshen",
    interface: {displayName: "Freshen Codex Smoke"},
    plugins: [
      {
        name: "freshen",
        source: {source: "local", path: "./plugins/freshen"},
        policy: {installation: "AVAILABLE", authentication: "ON_INSTALL"},
        category: "Productivity"
      }
    ]
  }
' > "$MARKET_ROOT/.agents/plugins/marketplace.json"

CODEX_HOME="$SMOKE_CODEX_HOME" codex plugin marketplace add "$MARKET_ROOT" --json >/dev/null
CODEX_HOME="$SMOKE_CODEX_HOME" codex plugin add freshen@age87-freshen --json >/dev/null
CODEX_HOME="$SMOKE_CODEX_HOME" codex plugin list --json > "$SMOKE_ROOT/installed.json"

jq -e '
  .. | objects
  | select(.name? == "freshen" or .id? == "freshen@age87-freshen")
' "$SMOKE_ROOT/installed.json" >/dev/null

INSTALLED_MANIFEST="$(find "$SMOKE_CODEX_HOME" -path '*/.codex-plugin/plugin.json' -type f -print -quit)"
[ -n "$INSTALLED_MANIFEST" ]
INSTALLED_ROOT="$(cd "$(dirname "$INSTALLED_MANIFEST")/.." && pwd)"

[ "$(find "$INSTALLED_ROOT/skills" -mindepth 2 -maxdepth 2 -name SKILL.md -type f | wc -l | tr -d ' ')" = "1" ]
[ -f "$INSTALLED_ROOT/hooks/hooks.json" ]
[ -f "$INSTALLED_ROOT/hooks/codex/on-stop.sh" ]
[ -f "$INSTALLED_ROOT/hooks/codex/on-clear.sh" ]

# Exercise the installed SessionStart commands with Codex's native plugin-root
# variable only. This catches manifests that never reach host-dispatch.sh
# because they expand the Claude-only CLAUDE_PLUGIN_ROOT in the command shell.
CLEAR_COMMAND="$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$INSTALLED_ROOT/hooks/hooks.json")"
STARTUP_COMMAND="$(jq -r '.hooks.SessionStart[1].hooks[0].command' "$INSTALLED_ROOT/hooks/hooks.json")"
(
  cd "$SMOKE_ROOT"
  env -u CLAUDE_PLUGIN_ROOT PLUGIN_ROOT="$INSTALLED_ROOT" \
    bash -c "$CLEAR_COMMAND" < /dev/null > /dev/null
  env -u CLAUDE_PLUGIN_ROOT PLUGIN_ROOT="$INSTALLED_ROOT" \
    bash -c "$STARTUP_COMMAND" < /dev/null > /dev/null
)

RESOLVED="$(PLUGIN_ROOT="$INSTALLED_ROOT" bash "$INSTALLED_ROOT/hooks/host-dispatch.sh" --resolve on-stop.sh)"
[[ "$RESOLVED" == codex:*'/hooks/codex/on-stop.sh' ]]

printf 'PASS: Codex installed Freshen with one skill and host-native hook adapters\n'
