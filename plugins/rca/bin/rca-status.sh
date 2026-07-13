#!/usr/bin/env bash
# rca-status.sh — report the state of every RCA investigation under .rca/.
#
# Usage:
#   rca-status.sh [--rca-dir .rca] [--slug <slug>]
#
# Output: one JSON object on stdout:
#   {ok, count, investigations:[{slug,state,dispatch,tier,issue,summary,
#                                worktree_live,option:{label,description}}], display}
# Each investigation's `state`/`dispatch` is computed by the FIRST missing
# artifact in the ladder (see resolve_state). `option` is a ready-made
# AskUserQuestion choice; EVERY state — including corrupt/unexpected — yields a
# label and description, so nothing is ever unset under `set -u`.
#
# A missing .rca dir is not an error: {ok:true,count:0,...}.
# Errors: no_jq.
set -euo pipefail

command -v jq >/dev/null 2>&1 || { printf '{"ok":false,"error":"no_jq","detail":"jq is required"}\n'; exit 1; }

RCA_DIR=".rca"
ONLY_SLUG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --rca-dir) RCA_DIR="${2:-.rca}"; shift 2 ;;
    --slug)    ONLY_SLUG="${2:-}"; shift 2 ;;
    *)         jq -n --arg a "$1" '{ok:false, error:"bad_args", detail:("unexpected argument: "+$a)}'; exit 1 ;;
  esac
done

# summary_of <dir> — first non-heading non-empty line of GRID.md, else
# meta.description, else "(no description)". Truncated to 120 chars.
summary_of() {
  local dir="$1" s=""
  if [ -f "$dir/GRID.md" ]; then
    s=$(grep -v '^#' "$dir/GRID.md" 2>/dev/null | grep -v '^---' | grep -v '^[[:space:]]*$' | head -1 | cut -c1-120 || true)
  fi
  if [ -z "$s" ] && [ -f "$dir/meta.json" ]; then
    s=$(jq -r '.description // ""' "$dir/meta.json" 2>/dev/null | cut -c1-120 || true)
  fi
  [ -n "$s" ] || s="(no description)"
  printf '%s' "$s"
}

# resolve_state <dir> <tier> — echo "<state>\t<dispatch>" for the first missing
# artifact rung. `tier` is meta.tier ("" when not yet reproduced).
resolve_state() {
  local dir="$1" tier="$2"
  if [ ! -f "$dir/GRID.md" ]; then                       printf 'intake_incomplete\tintake'; return; fi
  if [ ! -f "$dir/REPRO.md" ] && [ ! -f "$dir/OVERRIDE.md" ]; then printf 'needs_repro\treproduce'; return; fi
  if [ -z "$tier" ]; then                                printf 'needs_tier\treproduce'; return; fi
  if [ "$tier" = "full" ] && [ ! -f "$dir/ORIGIN.md" ]; then printf 'needs_locate\tlocate'; return; fi
  if [ -f "$dir/INCONCLUSIVE.md" ]; then                 printf 'inconclusive\tdiagnose'; return; fi
  if [ ! -f "$dir/DIAGNOSIS.md" ]; then                  printf 'needs_diagnosis\tdiagnose'; return; fi
  if [ ! -f "$dir/REPORT.md" ] || [ ! -f "$dir/REMEDIATION.md" ]; then printf 'needs_report\treport'; return; fi
  if [ ! -f "$dir/APPROVAL.md" ]; then                   printf 'awaiting_caller\treport'; return; fi
  if grep -qi 'fix' "$dir/APPROVAL.md" 2>/dev/null && [ ! -f "$dir/FIX.md" ]; then printf 'needs_fix\tfix'; return; fi
  if [ ! -f "$dir/POSTMORTEM.md" ]; then                 printf 'needs_postmortem\tpostmortem'; return; fi
  printf 'complete\tnone'
}

# option_for <state> <slug> <summary> — echo "<label>\t<description>". A
# defensive default guarantees both are always set (v1's set -u crash fix).
option_for() {
  local state="$1" slug="$2" summary="$3" verb desc
  case "$state" in
    complete|awaiting_caller) verb="Review";   desc="$summary" ;;
    corrupt)                  verb="Clean up"; desc="Corrupt — no valid meta.json" ;;
    inconclusive)             verb="Resume";   desc="Inconclusive — needs another diagnosis pass" ;;
    intake_incomplete|needs_repro|needs_tier|needs_locate|needs_diagnosis|needs_report|needs_fix|needs_postmortem)
                              verb="Resume";   desc="$summary" ;;
    *)                        verb="Clean up"; desc="$summary" ;;
  esac
  printf '%s %s\t%s' "$verb" "$slug" "$desc"
}

# Missing .rca dir → empty result (not an error).
if [ ! -d "$RCA_DIR" ]; then
  jq -n '{ok:true, count:0, investigations:[], display:"[rca] no investigations found."}'
  exit 0
fi

items="[]"
display="[rca] investigations:"
count=0

while IFS= read -r -d '' dir; do
  slug=$(basename "$dir")
  [ -n "$ONLY_SLUG" ] && [ "$slug" != "$ONLY_SLUG" ] && continue

  worktree_live=false
  [ -f "$dir/worktree.json" ] && worktree_live=true

  tier=""
  issue_json="null"
  if [ ! -f "$dir/meta.json" ] || ! jq -e . "$dir/meta.json" >/dev/null 2>&1; then
    state="corrupt"; dispatch="cleanup"
  else
    tier=$(jq -r '.tier // ""' "$dir/meta.json" 2>/dev/null || true)
    issue_json=$(jq -c '.issue // null' "$dir/meta.json" 2>/dev/null || printf 'null')
    sd=$(resolve_state "$dir" "$tier")
    state="${sd%%$'\t'*}"; dispatch="${sd#*$'\t'}"
  fi

  summary=$(summary_of "$dir")
  opt=$(option_for "$state" "$slug" "$summary")
  label="${opt%%$'\t'*}"; odesc="${opt#*$'\t'}"

  items=$(printf '%s' "$items" | jq \
    --arg slug "$slug" --arg state "$state" --arg dispatch "$dispatch" \
    --arg tier "$tier" --argjson issue "$issue_json" --arg summary "$summary" \
    --argjson wl "$worktree_live" --arg label "$label" --arg odesc "$odesc" '
    . + [{slug:$slug, state:$state, dispatch:$dispatch, tier:$tier, issue:$issue,
          summary:$summary, worktree_live:$wl, option:{label:$label, description:$odesc}}]')

  display="$display
  [$state] $slug — $summary"
  count=$((count + 1))
done < <(find "$RCA_DIR" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | sort -z)

jq -n --argjson items "$items" --arg display "$display" --argjson count "$count" \
  '{ok:true, count:$count, investigations:$items,
    display:(if $count==0 then "[rca] no investigations found." else $display end)}'
