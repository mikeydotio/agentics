#!/usr/bin/env bash
# Resolve a canonical plugin dependency for Codex without selecting stale caches.
# Usage: resolve-dependency.sh agents|freshen|hook-guard
# stdout: absolute plugin root on success; diagnostics go to stderr.
# Exit 1: dependency unavailable (caller must report missing capability).
# Exit 2: invalid configuration, registry failure, or damaged installed dependency.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORGE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# fail <message> — report a configuration error without a success-shaped path.
fail() { printf 'forge: %s\n' "$1" >&2; exit 2; }

# valid_root <path> — require the canonical resolver, catalog, and role directory.
valid_root() {
  case "$dependency" in
    agents) [ -d "$1/agents" ] && [ -f "$1/bin/resolve-agent.sh" ] && [ -f "$1/references/agent-catalog.md" ] ;;
    freshen) [ -f "$1/codex/bin/freshen.sh" ] && [ -f "$1/hooks/codex/on-stop.sh" ] && [ -f "$1/lib/transition-log.sh" ] ;;
    hook-guard) [ -f "$1/lib/stop-guard.sh" ] ;;
  esac
}

# emit_root <path> — normalize a validated installation, including symlinks.
emit_root() { (cd "$1" && pwd -P); }

[ "$#" -eq 1 ] || fail "usage: resolve-dependency.sh agents|freshen|hook-guard"
dependency="$1"
case "$dependency" in
  agents) override_name=AGENTS_PLUGIN_ROOT ;;
  freshen) override_name=FRESHEN_PLUGIN_ROOT ;;
  hook-guard) override_name=HOOK_GUARD_PLUGIN_ROOT ;;
  *) fail "unknown dependency: $dependency" ;;
esac
if [[ -n "${!override_name+x}" ]]; then
  override="${!override_name}"
  valid_root "$override" || fail "invalid $override_name: $override"
  emit_root "$override"
  exit 0
fi

if valid_root "$FORGE_ROOT/../$dependency"; then
  emit_root "$FORGE_ROOT/../$dependency"
  exit 0
fi

if ! command -v codex >/dev/null 2>&1; then
  printf 'forge: %s unavailable; no checkout sibling or Codex registry CLI\n' "$dependency" >&2
  exit 1
fi
command -v jq >/dev/null 2>&1 || fail "jq is required to read the Codex registry"
registry="$(codex plugin list --json)" || fail "codex plugin list --json failed"
jq -e '
  type == "object" and (.installed | type == "array") and
  all(.installed[];
    type == "object" and (.name | type == "string") and
    (.installed | type == "boolean") and (.enabled | type == "boolean"))
' >/dev/null 2>&1 <<< "$registry" || fail "invalid Codex installed-plugin registry"
records="$(jq --arg name "$dependency" '[.installed[] | select(.name == $name and .installed and .enabled)]' <<< "$registry")"
count="$(jq 'length' <<< "$records")"
if [ "$count" -eq 0 ]; then
  printf 'forge: %s unavailable; no enabled installation\n' "$dependency" >&2
  exit 1
fi
[ "$count" -eq 1 ] || fail "multiple enabled ${dependency} installations; set the dependency override explicitly"

version="$(jq -r '.[0].version // empty' <<< "$records")"
market="$(jq -r '.[0].marketplaceName // empty' <<< "$records")"
plugin_id="$(jq -r '.[0].pluginId // empty' <<< "$records")"
case "$version" in ''|.|..|*[!a-zA-Z0-9._+-]*) fail "invalid installed ${dependency} version" ;; esac
case "$market" in ''|.|..|*[!a-zA-Z0-9._-]*) fail "invalid installed ${dependency} marketplace" ;; esac
[ "$plugin_id" = "$dependency@$market" ] || fail "installed ${dependency} identity disagrees with marketplace"

codex_home="${CODEX_HOME:-${HOME:?}/.codex}"
candidate="$codex_home/plugins/cache/$market/$dependency/$version"
# Installed cache is preferred; local marketplaces may expose only source.path.
if [ ! -d "$candidate" ]; then
  source_type="$(jq -r '.[0].source.source // empty' <<< "$records")"
  [ "$source_type" = local ] || fail "enabled ${dependency} cache is missing: $candidate"
  candidate="$(jq -r '.[0].source.path // empty' <<< "$records")"
  case "$candidate" in /*) ;; *) fail "enabled local ${dependency} path must be absolute" ;; esac
fi
valid_root "$candidate" || fail "enabled ${dependency} installation is damaged: $candidate"
manifest="$candidate/.codex-plugin/plugin.json"
[ -f "$manifest" ] || manifest="$candidate/.claude-plugin/plugin.json"
jq -e --arg name "$dependency" --arg version "$version" '.name == $name and .version == $version' \
  "$manifest" >/dev/null 2>&1 \
  || fail "enabled ${dependency} manifest identity/version mismatch: $candidate"
emit_root "$candidate"
