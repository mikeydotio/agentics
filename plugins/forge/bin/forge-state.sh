#!/usr/bin/env bash
# forge-state.sh — the single source of truth for forge's pipeline state
# machine. Detects `state`/`dispatch` from artifact presence + storyhook,
# plus (agentics#33) a `category` classification and derived `auto_advance`
# boolean: `category` names the same internal branch that already produces
# `dispatch`, so callers no longer have to re-derive "is this a safe
# pass-through, or does it need human/side-effecting handling?" by
# string-matching `dispatch` themselves. Both are pure telemetry today —
# nothing acts on them — laying the groundwork to measure whether further
# automation (deferred, see the issue) is actually worth building.
#
# Usage: forge-state.sh [forge-dir] [--record-transition]
#   forge-dir            positional, defaults to .forge (unchanged).
#   --record-transition  opt-in: append a `predicted` line (category,
#                         dispatch, transition_id) to .freshen/transitions.log
#                         via freshen's existing transition-log.sh helper.
#                         Order-independent relative to the positional arg.
#                         Best-effort — a logging failure never changes this
#                         script's exit code or stdout JSON.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FORGE_DIR=".forge"
RECORD_TRANSITION=false
for arg in "$@"; do
  case "$arg" in
    --record-transition) RECORD_TRANSITION=true ;;
    *) FORGE_DIR="$arg" ;;
  esac
done

# Best-effort transition logging (agentics#33) — reuses freshen's own
# lightweight audit log (F047) rather than inventing a second log format.
# Sourced unconditionally (cheap) but only ever called under
# --record-transition. Mirrors forge-step-exit.sh's identical sourcing idiom
# exactly, including the declare -f guard so a missing/partial freshen
# install can never abort this script under `set -e`.
_TRANSITION_LOG_LIB="$SCRIPT_DIR/../../freshen/lib/transition-log.sh"
# shellcheck source=plugins/freshen/lib/transition-log.sh
[ -f "$_TRANSITION_LOG_LIB" ] && . "$_TRANSITION_LOG_LIB" || true
log_predicted_transition() {
  declare -f freshen_log_transition >/dev/null 2>&1 && freshen_log_transition "$1" || true
}

# --- Artifact presence ---
#
# F102: presence used to mean file EXISTENCE only, so a truncated or
# zero-byte artifact (exactly what a freshen `/clear` mid-write, or a
# Stop-hook timeout, can leave behind) silently advanced the state machine —
# worse than a missing file, since missing at least re-runs the step. A file
# only counts as "present" once it also passes a minimal-shape check:
#   - .md  files: non-empty AND has a top-level H1 (`^# `) somewhere in it
#   - .json files: non-empty AND parses as valid JSON
#   - anything else: non-empty is the only requirement
# This is deliberately cheap (no schema validation) — just enough to reject
# an empty or mid-write file, which is the concrete failure mode F102 named.
artifact_exists() {
  local f="$FORGE_DIR/$1"
  [ -s "$f" ] || return 1
  case "$1" in
    *.md)
      grep -qE '^# ' "$f" 2>/dev/null
      ;;
    *.json)
      jq -e . "$f" >/dev/null 2>&1
      ;;
    *)
      return 0
      ;;
  esac
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
    if artifact_exists "$a"; then
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
    count=$(find "$FORGE_DIR/fix-cycles" -maxdepth 1 -type d -name 'cycle-*' | wc -l | tr -d ' ')
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

# `story decompose` auto-creates a synthetic "parent"/project story from
# PLAN.md's `## Task Breakdown` heading (see references/story-decomposition.md)
# and records its ID as `project_story` in plan-mapping.json. storyhook's
# `story next` permanently excludes ANY story with children from ever being
# offered (a `has_children` filter in storyhook's own app.rs, out of scope to
# change — see HARD CONSTRAINT in the hardening plan). So once every real task
# story reaches `done`, the project story is the only story left `todo` —
# forever, since nothing ever hands it back to `story next` to move it along.
# Read it here so check_storyhook can exclude it from the "are all stories
# done" computation below; a completely separate, best-effort close of the
# project story (for `story list`/`story summary` hygiene, not correctness)
# happens at the execute loop's Complete step via
# forge-close-project-story.sh — see references/execution-loop-complete.md. This read
# is intentionally side-effect-free: forge-state.sh is invoked from many
# non-execute contexts (hooks, `/forge status`) and must stay a pure detector.
read_project_story() {
  project_story=""
  local mapping_file="$FORGE_DIR/plan-mapping.json"
  if [ -f "$mapping_file" ] && jq -e . "$mapping_file" >/dev/null 2>&1; then
    project_story=$(jq -r '.project_story // ""' "$mapping_file")
  fi
}

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
      read_project_story
      # Real shape is double-nested: .stories[].story.state / .story.title —
      # NOT .stories[].state / .title. Exclude project_story (if recorded) —
      # see read_project_story above for why it can never reach `done` via
      # the normal `story next` path a leaf task story does.
      #
      # Count with jq's `length` (as forge-close-project-story.sh does for
      # its own analogous count), NOT a `states=$(... ) | grep -c` shell
      # pipeline: when project_story is the only story in the whole list
      # (a decompose run whose wave has zero checkbox items), excluding it
      # leaves an empty selection, and `echo "" | grep -cv '^done$'` counts
      # the one blank line `echo` still emits as a non-done entry — wedging
      # stories_all_done false forever. jq's `length` on an empty array is
      # unambiguously 0.
      local non_done
      if [ -n "$project_story" ]; then
        non_done=$(echo "$story_json" | jq --arg ps "$project_story" \
          '[.stories[]? | select(.story.id != $ps and .story.state != "done")] | length')
      else
        non_done=$(echo "$story_json" | jq \
          '[.stories[]? | select(.story.state != "done")] | length')
      fi
      if [ "$non_done" -eq 0 ]; then
        stories_all_done=true
      fi
      # If every remaining (non-done) story is blocked, execute is
      # permanently wedged with nothing left for `story next` to hand back —
      # surface a dedicated state so the pipeline pauses for the user instead
      # of silently re-dispatching execute forever.
      if [ "$non_done" -gt 0 ]; then
        local non_done_non_blocked
        if [ -n "$project_story" ]; then
          non_done_non_blocked=$(echo "$story_json" | jq --arg ps "$project_story" \
            '[.stories[]? | select(.story.id != $ps and .story.state != "done" and .story.state != "blocked")] | length')
        else
          non_done_non_blocked=$(echo "$story_json" | jq \
            '[.stories[]? | select(.story.state != "done" and .story.state != "blocked")] | length')
        fi
        if [ "$non_done_non_blocked" -eq 0 ]; then
          stories_blocked_only=true
        fi
      fi
      # Check for ESCALATE stories that are not done.
      #
      # F006: this used to grep a case-insensitive TITLE SUBSTRING
      # ("ESCALATE" anywhere in .story.title), which is both over-inclusive
      # (a legitimate story titled e.g. "Implement alert escalation policy"
      # would wedge the pipeline in pause_escalate) and under-inclusive (it
      # depended entirely on triage's title-prefix convention, with no
      # queryable field backing it). Detect the structured `story_type`
      # field instead — triage now sets `story_type: "escalate"` via
      # `story new --type escalate` / `story set --type escalate` (see
      # skills/triage/SKILL.md Step 4 and skills/forge/SKILL.md's Blocked
      # Stories Pause), a real, settable, queryable field on the story
      # (confirmed against storyhook/src/{cli.rs,domain.rs} — always
      # serialized, defaults to null when unset, never skipped). The
      # "ESCALATE:" title prefix is kept purely as a human-readable
      # convention; it is no longer what detection keys on.
      local escalate_not_done
      escalate_not_done=$(echo "$story_json" | jq '[.stories[] | select(.story.story_type == "escalate" and .story.state != "done")] | length')
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
  # agentics#33: category is the router's own classification of `dispatch`,
  # set alongside it at every branch below rather than re-derived by a
  # caller string-matching `dispatch` (or, worse, by a second external
  # mapping table that could drift from this function the way forge's
  # storyhook docs once drifted from the real CLI — see
  # forge-contract-check.sh). Exactly one of these values per branch:
  #   pass_through     - dispatch ends " --orchestrated" and names one of
  #                       the 11 pipeline skills directly; no side effect,
  #                       no human input required to advance.
  #   fix_loop         - dispatch is the literal string "plan --orchestrated"
  #                       (byte-identical to a plain design->plan pass-
  #                       through) but state=="fix_loop" makes this the
  #                       ONLY entry point that may run plan with FIX items,
  #                       gated behind forge-fix-archive.sh's mandatory,
  #                       unconditional cycle-counter increment (F003).
  #   blocked_review, escalate_review, deploy_gate, report_complete
  #                     - genuine human-input or terminal states; SKILL.md
  #                       owns all judgment here, unconditionally.
  local category=""

  if artifact_exists "COMPLETION.md"; then
    state="complete"
    # Explicit machine-readable token instead of an empty dispatch —
    # the router no longer has to infer behavior from the state name alone.
    dispatch="report_complete"
    category="report_complete"
  elif artifact_exists "DEPLOY-APPROVAL.md"; then
    state="deploy"
    dispatch="deploy --orchestrated"
    category="pass_through"
  elif artifact_exists "DOCUMENTATION.md"; then
    if [ "$has_escalate_pending" = "true" ]; then
      state="pause_escalate"
      dispatch="escalate_review"
      category="escalate_review"
    else
      state="pause_deploy"
      dispatch="deploy_gate"
      category="deploy_gate"
    fi
  elif artifact_exists "TRIAGE.md"; then
    local fix_cycle
    fix_cycle=$(count_fix_cycles)
    if has_fix_items && [ "$fix_cycle" -lt "$effective_max" ]; then
      state="fix_loop"
      dispatch="plan --orchestrated"
      category="fix_loop"
    else
      state="document"
      dispatch="document --orchestrated"
      category="pass_through"
    fi
  elif artifact_exists "REVIEW-REPORT.md" && artifact_exists "VALIDATE-REPORT.md"; then
    state="triage"
    dispatch="triage --orchestrated"
    category="pass_through"
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
      category="pass_through"
    elif [ "$review_done" = "false" ] && [ "$validate_done" = "true" ]; then
      dispatch="review --orchestrated"
      category="pass_through"
    else
      dispatch="review_validate --orchestrated"
      category="pass_through"
    fi
  elif [ "$stories_exist" = "true" ] && [ "$stories_blocked_only" = "true" ]; then
    state="blocked"
    dispatch="blocked_review"
    category="blocked_review"
  elif artifact_exists "plan-mapping.json" && [ "$stories_all_done" != "true" ]; then
    state="execute"
    dispatch="execute --orchestrated"
    category="pass_through"
  elif artifact_exists "PLAN.md" && ! artifact_exists "plan-mapping.json"; then
    state="decompose"
    dispatch="decompose --orchestrated"
    category="pass_through"
  elif artifact_exists "DESIGN.md" && ! artifact_exists "PLAN.md"; then
    state="plan"
    dispatch="plan --orchestrated"
    category="pass_through"
  elif artifact_exists "research/SUMMARY.md" && ! artifact_exists "DESIGN.md"; then
    state="design"
    dispatch="design --orchestrated"
    category="pass_through"
  elif artifact_exists "IDEA.md" && ! artifact_exists "research/SUMMARY.md"; then
    state="research"
    dispatch="research --orchestrated"
    category="pass_through"
  else
    state="interrogate"
    dispatch="interrogate --orchestrated"
    category="pass_through"
  fi

  # Fail-closed default: every branch above sets category explicitly, so
  # this is unreachable today (the final `else` above is exhaustive) — pure
  # defense-in-depth against a future branch being added without its
  # category. Deliberately NOT "pass_through": an unrecognized branch must
  # never look safe to auto-advance by default.
  [ -n "$category" ] || category="unknown"

  echo "$state"
  echo "$dispatch"
  echo "$category"
}

# --- Main ---

read_config
check_storyhook
read_state_json

result=$(detect_state)
state=$(echo "$result" | sed -n '1p')
dispatch=$(echo "$result" | sed -n '2p')
category=$(echo "$result" | sed -n '3p')
fix_cycle=$(count_fix_cycles)

# auto_advance is a pure derived view of category (one predicate, one
# owner) — never recomputed independently, so it can't drift from it.
if [ "$category" = "pass_through" ]; then
  auto_advance=true
else
  auto_advance=false
fi

# transition_id: a diagnostic correlator (not a security boundary) so a
# --record-transition "predicted" line here can later be matched against
# forge-step-exit.sh's "actual" line by forge-transition-report.sh, even
# across crashes/interleaved concurrent sessions. PID + bash's own RANDOM
# builtin is sufficient collision resistance for that purpose and, unlike
# `date +%N`, is portable to BSD/macOS date (F074-class portability — see
# CLAUDE.md).
transition_id="$$-$RANDOM"

detect_handoff "$state"

artifacts=$(build_artifacts)

if [ "$RECORD_TRANSITION" = "true" ]; then
  log_predicted_transition "predicted category=${category} dispatch=\"${dispatch}\" transition_id=${transition_id}"
fi

jq -n \
  --arg state "$state" \
  --arg dispatch "$dispatch" \
  --arg category "$category" \
  --argjson auto_advance "$auto_advance" \
  --arg transition_id "$transition_id" \
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
    category: $category,
    auto_advance: $auto_advance,
    transition_id: $transition_id,
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
