#!/usr/bin/env bash
# forge-status.sh — Generate pipeline status dashboard
# Usage: forge-status.sh [forge-dir]
set -euo pipefail

FORGE_DIR="${1:-.forge}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ARTIFACT_NAMES=(
  "IDEA.md"
  "research/SUMMARY.md"
  "DESIGN.md"
  "PLAN.md"
  "plan-mapping.json"
  "REVIEW-REPORT.md"
  "VALIDATE-REPORT.md"
  "TRIAGE.md"
  "DOCUMENTATION.md"
  "DEPLOY-APPROVAL.md"
  "COMPLETION.md"
)

# --- Config reading ---

read_config_json() {
  local config_file="$FORGE_DIR/config.json"
  if [ -f "$config_file" ]; then
    jq '{yolo: (.yolo // false), max_fix_cycles: (.max_fix_cycles // 3), max_fix_cycles_yolo: (.max_fix_cycles_yolo // 10)}' "$config_file"
  else
    jq -n '{yolo: false, max_fix_cycles: 3, max_fix_cycles_yolo: 10}'
  fi
}

# --- Fix cycle count ---

count_fix_cycles() {
  local count=0
  if [ -d "$FORGE_DIR/fix-cycles" ]; then
    count=$(find "$FORGE_DIR/fix-cycles" -maxdepth 1 -type d -name 'cycle-*' | wc -l | tr -d ' ')
  fi
  echo "$count"
}

# --- Recent handoffs ---

list_handoffs() {
  if [ -d "$FORGE_DIR/handoffs" ]; then
    { ls -t "$FORGE_DIR/handoffs/"*.md 2>/dev/null || true; } | head -3 | while read -r f; do
      basename "$f"
    done
  fi
}

# --- Execution progress (from state.json) ---

read_execution_state() {
  local state_file="$FORGE_DIR/state.json"
  if [ -f "$state_file" ]; then
    jq '{status: (.status // "unknown"), sessions_completed: (.sessions_completed // 0), stories_attempted: (.stories_attempted // 0), stories_this_session: (.stories_this_session // 0)}' "$state_file"
  else
    echo ""
  fi
}

# --- Storyhook integration ---

get_story_counts() {
  if command -v story >/dev/null 2>&1; then
    local story_json
    story_json=$(story list --all --json 2>/dev/null) || { echo ""; return; }
    local total done_count in_progress pending
    total=$(echo "$story_json" | jq '.stories | length')
    # Real shape is double-nested: .stories[].story.state — NOT .stories[].state
    # (the same nesting bug as forge-state.sh's check_storyhook — fixed here too).
    done_count=$(echo "$story_json" | jq '[.stories[] | select(.story.state == "done")] | length')
    in_progress=$(echo "$story_json" | jq '[.stories[] | select(.story.state == "in-progress")] | length')
    # "todo" is the real default open state; "pending"/"ready" are not real
    # storyhook states (there is no such state — see storyhook-contract.md).
    pending=$(echo "$story_json" | jq '[.stories[] | select(.story.state == "todo")] | length')
    jq -n \
      --argjson total "$total" \
      --argjson done "$done_count" \
      --argjson in_progress "$in_progress" \
      --argjson pending "$pending" \
      '{total: $total, done: $done, in_progress: $in_progress, pending: $pending}'
  else
    echo ""
  fi
}

# --- Build display ---

build_display() {
  local state="$1" config_json="$2" artifacts_json="$3" fix_cycles="$4"

  local yolo
  yolo=$(echo "$config_json" | jq -r '.yolo')
  local mode="normal"
  if [ "$yolo" = "true" ]; then mode="yolo"; fi

  local display=""
  display+="## Forge Pipeline Status\n\n"
  display+="**Current step**: ${state}\n"
  display+="**Mode**: ${mode}\n\n"

  # Artifacts section
  display+="### Artifacts\n"
  for a in "${ARTIFACT_NAMES[@]}"; do
    local exists
    exists=$(echo "$artifacts_json" | jq -r --arg k "$a" '.[$k]')
    if [ "$exists" = "true" ]; then
      display+="- ${a}: exists\n"
    else
      display+="- ${a}: missing\n"
    fi
  done

  # Execution progress (only in execution-related states)
  local exec_state
  exec_state=$(read_execution_state)
  if [ -n "$exec_state" ]; then
    display+="\n### Execution Progress\n"
    local sessions stories_attempted stories_session
    sessions=$(echo "$exec_state" | jq -r '.sessions_completed')
    stories_attempted=$(echo "$exec_state" | jq -r '.stories_attempted')
    stories_session=$(echo "$exec_state" | jq -r '.stories_this_session')
    display+="Sessions completed: ${sessions}\n"
    display+="Stories attempted: ${stories_attempted}\n"
    display+="Stories this session: ${stories_session}\n"

    local story_counts
    story_counts=$(get_story_counts)
    if [ -n "$story_counts" ]; then
      local done_c ip_c pend_c
      done_c=$(echo "$story_counts" | jq -r '.done')
      ip_c=$(echo "$story_counts" | jq -r '.in_progress')
      pend_c=$(echo "$story_counts" | jq -r '.pending')
      display+="Stories: ${done_c} done, ${ip_c} in-progress, ${pend_c} pending\n"
    fi
  fi

  # Fix cycles
  local max_cycles
  if [ "$yolo" = "true" ]; then
    max_cycles=$(echo "$config_json" | jq -r '.max_fix_cycles_yolo')
  else
    max_cycles=$(echo "$config_json" | jq -r '.max_fix_cycles')
  fi
  display+="\n### Fix Cycles\n"
  display+="Current: ${fix_cycles} / ${max_cycles}\n"
  if [ "$fix_cycles" -gt 0 ] && [ -d "$FORGE_DIR/fix-cycles" ]; then
    for d in "$FORGE_DIR/fix-cycles"/cycle-*; do
      [ -d "$d" ] || continue
      local cycle_name
      cycle_name=$(basename "$d")
      local cycle_files
      cycle_files=$(ls "$d" 2>/dev/null | tr '\n' ', ' | sed 's/,$//')
      display+="- ${cycle_name}: ${cycle_files}\n"
    done
  fi

  # Recent handoffs
  display+="\n### Recent Handoffs\n"
  local handoffs
  handoffs=$(list_handoffs)
  if [ -n "$handoffs" ]; then
    while IFS= read -r h; do
      display+="- ${h}\n"
    done <<< "$handoffs"
  else
    display+="(none)\n"
  fi

  printf '%s' "$display"
}

# --- Main ---
#
# State detection is NOT re-derived here. forge-state.sh is the single
# source of truth for the pipeline state machine (it also consults storyhook,
# which this script's own former detect_state() never did) — this script
# only renders a dashboard around what forge-state.sh reports, so `/forge
# status` can never show a state that contradicts what `/forge continue`
# will actually dispatch to.
state_json=$(bash "$SCRIPT_DIR/forge-state.sh" "$FORGE_DIR")
state=$(echo "$state_json" | jq -r '.state')
artifacts_json=$(echo "$state_json" | jq -c '.artifacts')

config_json=$(read_config_json)
fix_cycles=$(count_fix_cycles)
display=$(build_display "$state" "$config_json" "$artifacts_json" "$fix_cycles")

jq -n \
  --arg state "$state" \
  --arg display "$display" \
  --argjson artifacts "$artifacts_json" \
  --argjson config "$config_json" \
  --argjson fix_cycles "$fix_cycles" \
  --argjson ok true \
  '{
    ok: $ok,
    state: $state,
    display: $display,
    artifacts: $artifacts,
    config: $config,
    fix_cycles: $fix_cycles
  }'
