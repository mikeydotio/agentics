#!/usr/bin/env bash
# Private identity validator; invoked only by the resolver supervisor.
# Not a public entry point; the supervisor owns execution and output.
# stdout: absolute plugin root on success; diagnostics go to stderr.
# Exit 1: dependency unavailable (override-only dispatch is possible).
# Exit 2: invalid configuration, registry failure, or damaged installed dependency.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RCA_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# fail <message> — report a configuration error without a success-shaped path.
fail() { printf 'rca: %s\n' "$1" >&2; exit 2; }

# valid_root <path> — require the canonical resolver, catalog, and role directory.
valid_root() {
  [ -d "$1/agents" ] && [ -f "$1/bin/resolve-agent.sh" ] \
    && [ -f "$1/references/agent-catalog.md" ]
}

# emit_root <path> — normalize a validated installation, including symlinks.
emit_root() { (cd "$1" && pwd -P); }

[ "$#" -eq 1 ] && [ -d "$1" ] || fail "private validator requires its evidence directory"
EVIDENCE_DIR="$1"
printf '%s\n' selection > "$EVIDENCE_DIR/phase"
if [ "${AGENTS_PLUGIN_ROOT+x}" = x ]; then
  valid_root "$AGENTS_PLUGIN_ROOT" || fail "invalid AGENTS_PLUGIN_ROOT: $AGENTS_PLUGIN_ROOT"
  emit_root "$AGENTS_PLUGIN_ROOT"
  exit 0
fi

if valid_root "$RCA_ROOT/../agents"; then
  emit_root "$RCA_ROOT/../agents"
  exit 0
fi

if ! command -v codex >/dev/null 2>&1; then
  printf '%s\n' 'rca: Agents unavailable; no checkout sibling or Codex registry CLI' >&2
  printf '%s\n' unavailable > "$EVIDENCE_DIR/outcome"
  exit 1
fi
command -v jq >/dev/null 2>&1 || fail "jq is required to read the Codex registry"
printf '%s\n' registry > "$EVIDENCE_DIR/phase"
codex plugin list --json > "$EVIDENCE_DIR/registry.json" \
  || fail "codex plugin list --json failed"
printf '%s\n' registry-validation > "$EVIDENCE_DIR/phase"
registry="$(<"$EVIDENCE_DIR/registry.json")"
jq -e '
  type == "object" and (.installed | type == "array") and
  all(.installed[];
    type == "object" and (.name | type == "string") and
    (.installed | type == "boolean") and (.enabled | type == "boolean"))
' >/dev/null 2>&1 <<< "$registry" || fail "invalid Codex installed-plugin registry"
records="$(jq '[.installed[] | select(.name == "agents" and .installed and .enabled)]' <<< "$registry")"
count="$(jq 'length' <<< "$records")"
if [ "$count" -eq 0 ]; then
  printf '%s\n' 'rca: Agents unavailable; no enabled installation (override-only fallback)' >&2
  printf '%s\n' unavailable > "$EVIDENCE_DIR/outcome"
  exit 1
fi
[ "$count" -eq 1 ] || fail "multiple enabled Agents installations; set AGENTS_PLUGIN_ROOT explicitly"

printf '%s\n' identity-validation > "$EVIDENCE_DIR/phase"
version="$(jq -r '.[0].version // empty' <<< "$records")"
market="$(jq -r '.[0].marketplaceName // empty' <<< "$records")"
plugin_id="$(jq -r '.[0].pluginId // empty' <<< "$records")"
case "$version" in ''|.|..|*[!a-zA-Z0-9._+-]*) fail "invalid installed Agents version" ;; esac
case "$market" in ''|.|..|*[!a-zA-Z0-9._-]*) fail "invalid installed Agents marketplace" ;; esac
[ "$plugin_id" = "agents@$market" ] || fail "installed Agents identity disagrees with marketplace"

codex_home="${CODEX_HOME:-${HOME:?}/.codex}"
candidate="$codex_home/plugins/cache/$market/agents/$version"
# Installed cache is preferred; local marketplaces may expose only source.path.
if [ ! -d "$candidate" ]; then
  source_type="$(jq -r '.[0].source.source // empty' <<< "$records")"
  [ "$source_type" = local ] || fail "enabled Agents cache is missing: $candidate"
  candidate="$(jq -r '.[0].source.path // empty' <<< "$records")"
  case "$candidate" in /*) ;; *) fail "enabled local Agents path must be absolute" ;; esac
fi
valid_root "$candidate" || fail "enabled Agents installation is damaged: $candidate"
jq -e --arg version "$version" '.name == "agents" and .version == $version' \
  "$candidate/.codex-plugin/plugin.json" >/dev/null 2>&1 \
  || fail "enabled Agents manifest identity/version mismatch: $candidate"
emit_root "$candidate"
