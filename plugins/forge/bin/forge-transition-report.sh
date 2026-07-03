#!/usr/bin/env bash
# forge-transition-report.sh — read-only correlator over
# .freshen/transitions.log's "predicted"/"actual" lines (agentics#33).
#
# Parses the log forge-state.sh --record-transition (predicted lines) and
# forge-step-exit.sh --transition-id (actual lines) already write, and
# correlates pairs by transition_id -- never by line position, which a
# crashed pane or two interleaved concurrent sessions would silently
# corrupt. Reports three buckets:
#
#   matched            - predicted+actual pairs found for the same
#                         transition_id. Flagged mismatch=true only when
#                         the predicted dispatch is step-shaped (ends
#                         " --orchestrated") and the actual step doesn't
#                         match it. Human-gate dispatches (blocked_review/
#                         escalate_review/deploy_gate/report_complete) have
#                         no step name to compare against and are never
#                         flagged; fix_loop's dispatch is legitimately
#                         "plan --orchestrated" (SKILL.md's Fix Loop
#                         Handling dispatches to plan with FIX items), so an
#                         actual step of "plan" there is correct, not a
#                         misroute.
#   orphaned_predicted  - a "predicted" line with no matching "actual" --
#                         evidence of a crashed or wedged pane/session that
#                         never reached step-exit.
#   orphaned_actual     - an "actual" line with transition_id=none (an
#                         older/manual forge-step-exit.sh call that never
#                         threaded a transition_id through), or with a real
#                         id that doesn't match any predicted line (e.g. the
#                         predicted line aged out of the log's 500-line
#                         cap).
#
# Never mutates state, never touches tmux, never fails the process over a
# malformed/missing log -- purely diagnostic text/jq parsing over a static
# log file. Not wired into any automated decision; this is the measurement
# mechanism the agentics#33 design doc recommends building before deciding
# whether further automation (a resolve-next helper, a supervisor) is
# actually worth its added complexity.
#
# Usage: forge-transition-report.sh [log-file]
#   log-file defaults to .freshen/transitions.log (relative to cwd, matching
#   every other freshen state file).
set -euo pipefail

LOG_FILE="${1:-.freshen/transitions.log}"

if [ ! -f "$LOG_FILE" ]; then
  jq -n --arg log "$LOG_FILE" \
    '{ok: false, error: "log_not_found", display: ("[forge] transition-report: no log at " + $log)}'
  exit 0
fi

records=()

while IFS= read -r line; do
  if [[ "$line" =~ ^[0-9-]+T[0-9:]+Z\ predicted\ category=([^\ ]+)\ dispatch=\"([^\"]*)\"\ transition_id=([^\ ]+)$ ]]; then
    records+=("$(jq -n -c \
      --arg type "predicted" \
      --arg category "${BASH_REMATCH[1]}" \
      --arg dispatch "${BASH_REMATCH[2]}" \
      --arg transition_id "${BASH_REMATCH[3]}" \
      '{type: $type, category: $category, dispatch: $dispatch, transition_id: $transition_id}')")
  elif [[ "$line" =~ ^[0-9-]+T[0-9:]+Z\ actual\ step=([^\ ]+)\ transition_id=([^\ ]+)$ ]]; then
    records+=("$(jq -n -c \
      --arg type "actual" \
      --arg step "${BASH_REMATCH[1]}" \
      --arg transition_id "${BASH_REMATCH[2]}" \
      '{type: $type, step: $step, transition_id: $transition_id}')")
  fi
done < "$LOG_FILE"

if [ ${#records[@]} -eq 0 ]; then
  records_json="[]"
else
  records_json=$(printf '%s\n' "${records[@]}" | jq -s -c '.')
fi

echo "$records_json" | jq '
  def expected_step:
    if (.dispatch | endswith(" --orchestrated")) then (.dispatch | split(" ")[0]) else null end;

  (map(select(.type == "predicted"))) as $predicted
  | (map(select(.type == "actual"))) as $actual
  | ($predicted | INDEX(.transition_id)) as $predicted_by_id
  | ($actual | map(select(.transition_id == "none")) | map({step})) as $orphaned_actual_none
  | ($actual | map(select(.transition_id != "none"))) as $actual_real
  | ($actual_real
      | map(select($predicted_by_id[.transition_id] != null))
      | map(. as $a | $predicted_by_id[$a.transition_id] as $p |
          {
            transition_id: $a.transition_id,
            category: $p.category,
            dispatch: $p.dispatch,
            step: $a.step,
            mismatch: (($p | expected_step) != null and ($p | expected_step) != $a.step)
          })
    ) as $matched
  | ($actual_real
      | map(select($predicted_by_id[.transition_id] == null))
      | map({transition_id, step})
    ) as $orphaned_actual_unmatched
  | ($orphaned_actual_unmatched + $orphaned_actual_none) as $orphaned_actual
  | ($predicted
      | map(select(.transition_id | IN($actual_real[].transition_id) | not))
      | map({transition_id, category, dispatch})
    ) as $orphaned_predicted
  | {
      ok: true,
      matched: $matched,
      orphaned_predicted: $orphaned_predicted,
      orphaned_actual: $orphaned_actual,
      counts: {
        matched: ($matched | length),
        mismatched: ($matched | map(select(.mismatch)) | length),
        orphaned_predicted: ($orphaned_predicted | length),
        orphaned_actual: ($orphaned_actual | length)
      },
      display: ("[forge] transition-report: "
        + ($matched | length | tostring) + " matched ("
        + ($matched | map(select(.mismatch)) | length | tostring) + " mismatched), "
        + ($orphaned_predicted | length | tostring) + " orphaned predicted, "
        + ($orphaned_actual | length | tostring) + " orphaned actual")
    }
'
