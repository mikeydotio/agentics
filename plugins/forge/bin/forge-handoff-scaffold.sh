#!/usr/bin/env bash
# forge-handoff-scaffold.sh — pre-fill the MECHANICAL fields of a step handoff
# (F039) so the model spends its tokens only on genuine judgment content
# (what happened, why, working context).
#
# Usage: forge-handoff-scaffold.sh --step <name> [--forge-dir .forge]
#
# Call this BEFORE writing `.forge/handoffs/handoff-<step>.md`, then embed the
# returned fields into the corresponding template sections (see
# references/step-handoff.md's Handoff Format):
#   .timestamp                    -> ## Timestamp
#   .artifacts_produced            -> ## Artifacts Produced
#   .pipeline_state.fix_cycle      -> ## Pipeline State: "Fix cycle: N / max"
#   .pipeline_state.max_fix_cycles
#   .pipeline_state.yolo           -> ## Pipeline State: "Yolo mode: true/false"
#
# This script does NOT write the handoff file itself (the model composes the
# full document, judgment sections included) and does NOT compute team
# roster / ESCALATE-pending counts — those need a TEAM.md read or a
# storyhook query whose relevance varies by step, so they stay inline model
# work rather than a one-size-fits-all script field.
#
# Output: {ok, step, timestamp, artifacts_produced, pipeline_state, display}
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

step="" forge_dir=".forge"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --step)      step="$2"; shift 2 ;;
    --step=*)    step="${1#*=}"; shift ;;
    --forge-dir) forge_dir="$2"; shift 2 ;;
    --forge-dir=*) forge_dir="${1#*=}"; shift ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

[ -n "$step" ] || { echo "Error: --step is required" >&2; exit 1; }

timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Artifacts produced: everything changed under $forge_dir not yet part of a
# commit — staged, unstaged, and untracked. This is the mechanical "what did
# this step touch" signal; whether each one matters for the narrative is
# still the model's call.
artifacts_json="$(
  {
    git diff --name-only -- "$forge_dir" 2>/dev/null
    git diff --cached --name-only -- "$forge_dir" 2>/dev/null
    git ls-files --others --exclude-standard -- "$forge_dir" 2>/dev/null
  } | sort -u | jq -R -s 'split("\n") | map(select(length > 0))'
)"

# Pipeline state: fix_cycle/max_fix_cycles/yolo are already computed by
# forge-state.sh (config read + fix-cycle directory count) — reuse that
# rather than re-deriving the same logic here. Best-effort: forge-state.sh
# itself has no external dependencies (no `story` CLI needed for these
# fields), but tolerate its absence gracefully rather than failing the whole
# scaffold over a secondary field.
fix_cycle=0
max_fix_cycles=3
yolo=false
if [ -f "$SCRIPT_DIR/forge-state.sh" ]; then
  state_json="$(bash "$SCRIPT_DIR/forge-state.sh" "$forge_dir" 2>/dev/null || echo '{}')"
  fix_cycle="$(echo "$state_json" | jq -r '.fix_cycle // 0')"
  max_fix_cycles="$(echo "$state_json" | jq -r '.max_fix_cycles // 3')"
  yolo="$(echo "$state_json" | jq -r '.yolo // false')"
fi

artifact_count="$(echo "$artifacts_json" | jq 'length')"
display="[forge] Handoff scaffold for ${step}: ${artifact_count} artifact(s) touched, fix cycle ${fix_cycle}/${max_fix_cycles}, yolo=${yolo}"

jq -n \
  --arg step "$step" \
  --arg timestamp "$timestamp" \
  --argjson artifacts "$artifacts_json" \
  --argjson fix_cycle "$fix_cycle" \
  --argjson max_fix_cycles "$max_fix_cycles" \
  --argjson yolo "$yolo" \
  --arg display "$display" \
  '{
    ok: true,
    step: $step,
    timestamp: $timestamp,
    artifacts_produced: $artifacts,
    pipeline_state: {fix_cycle: $fix_cycle, max_fix_cycles: $max_fix_cycles, yolo: $yolo},
    display: $display
  }'
