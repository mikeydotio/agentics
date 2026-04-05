#!/usr/bin/env bash
set -euo pipefail

FORGE_DIR="${1:-.forge}"

# --- Artifact presence ---

artifact_exists() {
  [ -f "$FORGE_DIR/$1" ]
}

build_artifacts() {
  local artifacts=(
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
  local pairs=()
  for a in "${artifacts[@]}"; do
    if [ -f "$FORGE_DIR/$a" ]; then
      pairs+=("$a" "true")
    else
      pairs+=("$a" "false")
    fi
  done
  jq -n \
    --arg k0  "${pairs[0]}"  --argjson v0  "${pairs[1]}" \
    --arg k1  "${pairs[2]}"  --argjson v1  "${pairs[3]}" \
    --arg k2  "${pairs[4]}"  --argjson v2  "${pairs[5]}" \
    --arg k3  "${pairs[6]}"  --argjson v3  "${pairs[7]}" \
    --arg k4  "${pairs[8]}"  --argjson v4  "${pairs[9]}" \
    --arg k5  "${pairs[10]}" --argjson v5  "${pairs[11]}" \
    --arg k6  "${pairs[12]}" --argjson v6  "${pairs[13]}" \
    --arg k7  "${pairs[14]}" --argjson v7  "${pairs[15]}" \
    --arg k8  "${pairs[16]}" --argjson v8  "${pairs[17]}" \
    --arg k9  "${pairs[18]}" --argjson v9  "${pairs[19]}" \
    --arg k10 "${pairs[20]}" --argjson v10 "${pairs[21]}" \
    '{($k0):$v0, ($k1):$v1, ($k2):$v2, ($k3):$v3, ($k4):$v4, ($k5):$v5, ($k6):$v6, ($k7):$v7, ($k8):$v8, ($k9):$v9, ($k10):$v10}'
}

# --- Config reading ---

read_config() {
  local config_file="$FORGE_DIR/config.json"
  if [ -f "$config_file" ]; then
    yolo=$(jq -r '.yolo // false' "$config_file")
    max_fix_cycles=$(jq -r '.max_fix_cycles // 3' "$config_file")
    max_fix_cycles_yolo=$(jq -r '.max_fix_cycles_yolo // 10' "$config_file")
  else
    yolo=false
    max_fix_cycles=3
    max_fix_cycles_yolo=10
  fi

  if [ "$yolo" = "true" ]; then
    effective_max=$max_fix_cycles_yolo
  else
    effective_max=$max_fix_cycles
  fi
}

# --- Fix cycle count ---

count_fix_cycles() {
  local count=0
  if [ -d "$FORGE_DIR/fix-cycles" ]; then
    count=$(find "$FORGE_DIR/fix-cycles" -maxdepth 1 -type d -name 'cycle-*' | wc -l)
  fi
  echo "$count"
}

# --- TRIAGE.md FIX item detection ---

has_fix_items() {
  if ! [ -f "$FORGE_DIR/TRIAGE.md" ]; then
    return 1
  fi
  # Look for a "## FIX" heading followed by at least one list item before the next heading
  awk '
    /^## FIX/ { in_fix=1; next }
    /^## / { in_fix=0 }
    in_fix && /^- / { found=1; exit }
    END { exit !found }
  ' "$FORGE_DIR/TRIAGE.md"
}

# --- Handoff detection ---

detect_handoff() {
  has_handoff=false
  latest_handoff=""
  if [ -d "$FORGE_DIR/handoffs" ]; then
    local latest
    latest=$(ls -t "$FORGE_DIR/handoffs/"*.md 2>/dev/null | head -1) || true
    if [ -n "$latest" ]; then
      has_handoff=true
      latest_handoff="handoffs/$(basename "$latest")"
    fi
  fi
}

# --- Storyhook integration ---

check_storyhook() {
  storyhook_available=false
  stories_all_done=false
  stories_exist=false
  has_escalate_pending=false

  if command -v story >/dev/null 2>&1; then
    local story_json
    story_json=$(story list --json 2>/dev/null) || return 0
    storyhook_available=true

    local story_count
    story_count=$(echo "$story_json" | jq '.stories | length')
    if [ "$story_count" -gt 0 ]; then
      stories_exist=true
      local states
      states=$(echo "$story_json" | jq -r '.stories[]?.state' | sort -u)
      if [ "$(echo "$states" | grep -cv '^done$' || true)" -eq 0 ]; then
        stories_all_done=true
      fi
      # Check for ESCALATE stories that are not done
      local escalate_not_done
      escalate_not_done=$(echo "$story_json" | jq '[.stories[] | select(.title != null and (.title | test("ESCALATE"; "i")) and .state != "done")] | length')
      if [ "$escalate_not_done" -gt 0 ]; then
        has_escalate_pending=true
      fi
    fi
  fi
}

# --- State detection (bottom-up, first match wins) ---

detect_state() {
  local state=""
  local dispatch=""

  if artifact_exists "COMPLETION.md"; then
    state="complete"
    dispatch=""
  elif artifact_exists "DEPLOY-APPROVAL.md"; then
    state="deploy"
    dispatch="deploy --orchestrated"
  elif artifact_exists "DOCUMENTATION.md"; then
    if [ "$has_escalate_pending" = "true" ]; then
      state="pause_escalate"
      dispatch=""
    else
      state="pause_deploy"
      dispatch=""
    fi
  elif artifact_exists "TRIAGE.md"; then
    local fix_cycle
    fix_cycle=$(count_fix_cycles)
    if has_fix_items && [ "$fix_cycle" -lt "$effective_max" ]; then
      state="fix_loop"
      dispatch="plan --orchestrated"
    else
      state="document"
      dispatch="document --orchestrated"
    fi
  elif artifact_exists "REVIEW-REPORT.md" && artifact_exists "VALIDATE-REPORT.md"; then
    state="triage"
    dispatch="triage --orchestrated"
  elif [ "$stories_exist" = "true" ] && [ "$stories_all_done" = "true" ]; then
    state="review_validate"
    dispatch="review --orchestrated"
  elif artifact_exists "plan-mapping.json" && [ "$stories_all_done" != "true" ]; then
    state="execute"
    dispatch="execute --orchestrated"
  elif artifact_exists "PLAN.md" && ! artifact_exists "plan-mapping.json"; then
    state="decompose"
    dispatch="decompose --orchestrated"
  elif artifact_exists "DESIGN.md" && ! artifact_exists "PLAN.md"; then
    state="plan"
    dispatch="plan --orchestrated"
  elif artifact_exists "research/SUMMARY.md" && ! artifact_exists "DESIGN.md"; then
    state="design"
    dispatch="design --orchestrated"
  elif artifact_exists "IDEA.md" && ! artifact_exists "research/SUMMARY.md"; then
    state="research"
    dispatch="research --orchestrated"
  else
    state="interrogate"
    dispatch="interrogate --orchestrated"
  fi

  echo "$state"
  echo "$dispatch"
}

# --- Main ---

read_config
detect_handoff
check_storyhook

result=$(detect_state)
state=$(echo "$result" | sed -n '1p')
dispatch=$(echo "$result" | sed -n '2p')
fix_cycle=$(count_fix_cycles)

artifacts=$(build_artifacts)

jq -n \
  --arg state "$state" \
  --arg dispatch "$dispatch" \
  --argjson fix_cycle "$fix_cycle" \
  --argjson max_fix_cycles "$effective_max" \
  --argjson yolo "$yolo" \
  --argjson has_handoff "$has_handoff" \
  --arg latest_handoff "$latest_handoff" \
  --argjson artifacts "$artifacts" \
  --argjson storyhook_available "$storyhook_available" \
  '{
    state: $state,
    dispatch: $dispatch,
    fix_cycle: $fix_cycle,
    max_fix_cycles: $max_fix_cycles,
    yolo: $yolo,
    has_handoff: $has_handoff,
    latest_handoff: $latest_handoff,
    artifacts: $artifacts,
    storyhook_available: $storyhook_available
  }'
