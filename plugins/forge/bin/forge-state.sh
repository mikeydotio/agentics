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

# --- state.json presence (fresh-start vs. resume discriminator) ---
#
# execute/SKILL.md needs a deterministic signal for "fresh start from decompose"
# (no prior execute session, state.json absent) vs. "resume after crash/pause"
# (state.json present — a session has already run the loop at least once).
# Exposed as state_json_exists/state_json_status so the skill branches on a
# fact, not on model inference.

read_state_json() {
  state_json_exists=false
  state_json_status=""
  local state_file="$FORGE_DIR/state.json"
  if [ -f "$state_file" ] && jq -e . "$state_file" >/dev/null 2>&1; then
    state_json_exists=true
    state_json_status=$(jq -r '.status // ""' "$state_file")
  fi
}

# --- Expected handoff per state ---
#
# Maps the detected state to the handoff file(s) that MUST already exist for
# that state to be entered cleanly (i.e., the handoff written by whichever
# step just finished). Multiple required files are comma-separated (e.g.
# triage needs both review's and validate's handoffs).
expected_handoff_for_state() {
  local st="$1"
  case "$st" in
    interrogate) echo "" ;;
    research) echo "handoff-interrogate.md" ;;
    design) echo "handoff-research.md" ;;
    plan) echo "handoff-design.md" ;;
    decompose) echo "handoff-plan.md" ;;
    execute|blocked)
      # Fresh start reads decompose's handoff; a resume reads execute's own
      # (see read_state_json — state_json_exists distinguishes these).
      if [ "$state_json_exists" = "true" ]; then
        echo "handoff-execute.md"
      else
        echo "handoff-decompose.md"
      fi
      ;;
    review_validate|review|validate) echo "handoff-execute.md" ;;
    triage) echo "handoff-review.md,handoff-validate.md" ;;
    fix_loop|document) echo "handoff-triage.md" ;;
    pause_deploy|pause_escalate|deploy) echo "handoff-document.md" ;;
    complete) echo "" ;;
    *) echo "" ;;
  esac
}

# --- Handoff detection ---
#
# has_handoff/latest_handoff are a general "is there anything in handoffs/"
# signal (kept for backward compatibility with existing consumers/tests).
# expected_handoff/expected_handoff_present are the authoritative safety
# check: they name the SPECIFIC handoff(s) required for the detected state
# and whether they're actually present — mtime ordering of unrelated files
# can't hide a genuinely missing handoff behind this check.
detect_handoff() {
  local st="$1"
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

  expected_handoff=$(expected_handoff_for_state "$st")
  expected_handoff_present=true
  if [ -n "$expected_handoff" ]; then
    local old_ifs="$IFS"
    local f
    IFS=','
    for f in $expected_handoff; do
      [ -f "$FORGE_DIR/handoffs/$f" ] || expected_handoff_present=false
    done
    IFS="$old_ifs"
  fi
}

# --- Storyhook integration ---

check_storyhook() {
  storyhook_available=false
  stories_all_done=false
  stories_exist=false
  stories_blocked_only=false
  has_escalate_pending=false

  if command -v story >/dev/null 2>&1; then
    local story_json
    story_json=$(story list --json 2>/dev/null) || return 0
    storyhook_available=true

    local story_count
    story_count=$(echo "$story_json" | jq '.stories | length')
    if [ "$story_count" -gt 0 ]; then
      stories_exist=true
      # Real shape is double-nested: .stories[].story.state / .story.title —
      # NOT .stories[].state / .title.
      local states
      states=$(echo "$story_json" | jq -r '.stories[]?.story.state' | sort -u)
      local non_done
      non_done=$(echo "$states" | grep -cv '^done$' || true)
      if [ "$non_done" -eq 0 ]; then
        stories_all_done=true
      fi
      # If every remaining (non-done) story is blocked, execute is
      # permanently wedged with nothing left for `story next` to hand back —
      # surface a dedicated state so the pipeline pauses for the user instead
      # of silently re-dispatching execute forever.
      if [ "$non_done" -gt 0 ]; then
        local non_done_non_blocked
        non_done_non_blocked=$(echo "$states" | grep -v '^done$' | grep -cv '^blocked$' || true)
        if [ "$non_done_non_blocked" -eq 0 ]; then
          stories_blocked_only=true
        fi
      fi
      # Check for ESCALATE stories that are not done
      local escalate_not_done
      escalate_not_done=$(echo "$story_json" | jq '[.stories[] | select(.story.title != null and (.story.title | test("ESCALATE"; "i")) and .story.state != "done")] | length')
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
    # Explicit machine-readable token instead of an empty dispatch —
    # the router no longer has to infer behavior from the state name alone.
    dispatch="report_complete"
  elif artifact_exists "DEPLOY-APPROVAL.md"; then
    state="deploy"
    dispatch="deploy --orchestrated"
  elif artifact_exists "DOCUMENTATION.md"; then
    if [ "$has_escalate_pending" = "true" ]; then
      state="pause_escalate"
      dispatch="escalate_review"
    else
      state="pause_deploy"
      dispatch="deploy_gate"
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
    # Review and validate must never be dispatched such that one
    # can finish, find the other's report absent, and STOP without queuing
    # freshen (the old "whoever finishes second queues" dance deadlocks).
    # forge-state.sh now names exactly what's needed: both (a single combined
    # dispatch spawning both agent sets in one message) or whichever ONE
    # report is still missing.
    state="review_validate"
    local review_done="false" validate_done="false"
    artifact_exists "REVIEW-REPORT.md" && review_done="true"
    artifact_exists "VALIDATE-REPORT.md" && validate_done="true"
    if [ "$review_done" = "true" ] && [ "$validate_done" = "false" ]; then
      dispatch="validate --orchestrated"
    elif [ "$review_done" = "false" ] && [ "$validate_done" = "true" ]; then
      dispatch="review --orchestrated"
    else
      dispatch="review_validate --orchestrated"
    fi
  elif [ "$stories_exist" = "true" ] && [ "$stories_blocked_only" = "true" ]; then
    state="blocked"
    dispatch="blocked_review"
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
check_storyhook
read_state_json

result=$(detect_state)
state=$(echo "$result" | sed -n '1p')
dispatch=$(echo "$result" | sed -n '2p')
fix_cycle=$(count_fix_cycles)

detect_handoff "$state"

artifacts=$(build_artifacts)

jq -n \
  --arg state "$state" \
  --arg dispatch "$dispatch" \
  --argjson fix_cycle "$fix_cycle" \
  --argjson max_fix_cycles "$effective_max" \
  --argjson yolo "$yolo" \
  --argjson has_handoff "$has_handoff" \
  --arg latest_handoff "$latest_handoff" \
  --arg expected_handoff "$expected_handoff" \
  --argjson expected_handoff_present "$expected_handoff_present" \
  --argjson artifacts "$artifacts" \
  --argjson storyhook_available "$storyhook_available" \
  --argjson stories_blocked_only "$stories_blocked_only" \
  --argjson state_json_exists "$state_json_exists" \
  --arg state_json_status "$state_json_status" \
  '{
    state: $state,
    dispatch: $dispatch,
    fix_cycle: $fix_cycle,
    max_fix_cycles: $max_fix_cycles,
    yolo: $yolo,
    has_handoff: $has_handoff,
    latest_handoff: $latest_handoff,
    expected_handoff: $expected_handoff,
    expected_handoff_present: $expected_handoff_present,
    artifacts: $artifacts,
    storyhook_available: $storyhook_available,
    stories_blocked_only: $stories_blocked_only,
    state_json_exists: $state_json_exists,
    state_json_status: $state_json_status
  }'
