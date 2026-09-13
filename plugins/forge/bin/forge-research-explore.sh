#!/usr/bin/env bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# forge-research-explore — optional governed-explorer seam for the research step
#
# When `.forge/config.json` has `"governed_explorer": true`, run one greenlight
# plan explorer for a codebase-oriented research track: a headless Sonnet
# `claude -p` session in a disposable worktree, governed by the greenlight
# PreToolUse gate. Its findings are written to
# `.forge/research/codebase-<topic>.md`, where the research step's existing
# synthesis (which folds in every `.forge/research/*.md`) picks them up for free.
#
# Off by default and fail-soft: if the flag is unset, or the greenlight launcher
# is unavailable, this is a no-op and the research step proceeds with its
# domain-researcher agents as usual.
#
# Usage:
#   forge-research-explore.sh --topic <slug> --task "<question>" [--forge-dir <dir>]
#     [--host claude|codex] [--timeout <seconds>]
# Host defaults to Claude; Codex experiments have a 300-second default deadline.
#
# Output (stdout, JSON):
#   {"enabled":false,"ran":false}
#   {"enabled":true,"ran":true,"topic":"architecture","out":".forge/research/codebase-architecture.md","launcher":{…}}
#   {"enabled":true,"ran":false,"error":"launcher not found: …"}
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGINS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"   # plugins/forge/bin → plugins
LAUNCHER="${GREENLIGHT_EXPLORE_BIN:-$PLUGINS_DIR/greenlight/bin/greenlight-explore.sh}"

TOPIC=""; TASK=""; FORGE_DIR=".forge"; HOST=claude; EXPLORER_TIMEOUT=300
while [ "$#" -gt 0 ]; do
  case "$1" in
    --topic|--task|--forge-dir|--host|--timeout)
      [ "$#" -ge 2 ] || { printf 'forge-research-explore: %s requires a value\n' "$1" >&2; exit 2; }
      ;;
  esac
  case "$1" in
    --host) HOST="${2:-}"; shift 2 ;;
    --timeout) EXPLORER_TIMEOUT="${2:-}"; shift 2 ;;
    --topic)     TOPIC="${2:-}"; shift 2 ;;
    --task)      TASK="${2:-}"; shift 2 ;;
    --forge-dir) FORGE_DIR="${2:-.forge}"; shift 2 ;;
    *) printf 'forge-research-explore: unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done

case "$HOST" in claude|codex) ;; *) echo "forge: invalid host: $HOST" >&2; exit 2 ;; esac

[ -n "$TOPIC" ] || { printf 'forge-research-explore: --topic is required\n' >&2; exit 2; }
[ -n "$TASK" ]  || { printf 'forge-research-explore: --task is required\n' >&2; exit 2; }

# ── Gate: off unless explicitly enabled ──
enabled="$(jq -r '.governed_explorer // false' "$FORGE_DIR/config.json" 2>/dev/null || echo false)"
if [ "$enabled" != "true" ]; then
  jq -n '{enabled:false, ran:false}'
  exit 0
fi

# ── Launcher must be present; otherwise degrade gracefully ──
if [ "$HOST" = claude ] && [ ! -x "$LAUNCHER" ] && [ ! -f "$LAUNCHER" ]; then
  jq -n --arg e "launcher not found: $LAUNCHER" '{enabled:true, ran:false, error:$e}'
  exit 0
fi

# ── Resolve output path (sanitized topic) and run the explorer ──
slug="$(printf '%s' "$TOPIC" | tr '[:upper:] ' '[:lower:]-' | tr -cd '[:alnum:]-' | sed 's/-\{2,\}/-/g; s/^-//; s/-$//' | cut -c1-40)"
[ -n "$slug" ] || slug="codebase"
mkdir -p "$FORGE_DIR/research" 2>/dev/null || true
OUT="$FORGE_DIR/research/codebase-${slug}.md"

if [ "$HOST" = codex ]; then
  command -v python3 >/dev/null 2>&1 || {
    jq -n '{enabled:true, ran:false, error:"python3 is required for Codex exploration"}'
    exit 0
  }
  launcher_json="$(python3 "$SCRIPT_DIR/forge-codex-explore.py" --task "$TASK" --out "$OUT" --timeout "$EXPLORER_TIMEOUT")" || {
    jq -n '{enabled:true, ran:false, error:"Codex explorer launcher failed; see stderr"}'
    exit 0
  }
else
  launcher_json="$(bash "$LAUNCHER" run --task "$TASK" --name "$slug" --out "$OUT" 2>/dev/null)"
fi
ran="$(printf '%s' "$launcher_json" | jq -r '.ok // false' 2>/dev/null || echo false)"
[ -n "$launcher_json" ] || launcher_json='{}'

jq -n \
  --arg topic "$slug" \
  --arg out "$OUT" \
  --argjson ran "$( [ "$ran" = "true" ] && echo true || echo false )" \
  --argjson launcher "$launcher_json" \
  '{enabled:true, ran:$ran, topic:$topic, out:$out, launcher:$launcher}'
exit 0
