#!/usr/bin/env bash
# forge-crash-recover.sh — reset any storyhook story stuck in `in-progress`
# back to `todo` and clean the working tree, in one call
# (WS4/F038). Replaces references/recovery-protocol.md Step 4's manual
# query-and-loop prose.
#
# Uses the real verb-first `story move <id> <state> ["<comment>"]` CLI (WS1)
# — never the dead id-first `story HP-N is todo` form.
#
# Usage: forge-crash-recover.sh [project-dir]
#
# Output (always exit 0 — callers branch on the JSON, not the exit code):
#   {ok, reset_stories, tree_clean, display}
#     ok             - true if the recovery ran to completion (or found
#                       nothing to do). false means it was skipped entirely
#                       (CLI/query failure or verifier ownership) — check
#                       `error`; the working tree is NOT touched in that case.
#     reset_stories  - array of story IDs actually moved back to `todo`.
#     tree_clean     - true once `git checkout .` has run (always attempted
#                       whenever `ok` is true, even with zero stories to
#                       reset — recovery-protocol.md's Step 4 cleans the tree
#                       unconditionally, not just when a stuck story exists).
#     display        - human-readable summary.
set -euo pipefail

PROJECT_DIR="${1:-.}"
cd "$PROJECT_DIR"

emit_skip() {
  jq -n --arg reason "$1" --arg display "[forge] crash-recover: skipped — $1" \
    '{ok: false, reset_stories: [], tree_clean: false, error: $reason, display: $display}'
  exit 0
}

command -v story >/dev/null 2>&1 || emit_skip "story_cli_missing"

story_json="$(story list --json 2>/dev/null)" || emit_skip "story_list_failed"

# The central verifier owns submitted work, including parked queue items.
# Refuse before any state mutation or checkout could disturb its candidate.
if echo "$story_json" | jq -e 'any(.stories[]?; .story.state == "verifying")' >/dev/null; then
  emit_skip "verification_in_progress"
fi

stuck_ids_json="$(echo "$story_json" | jq \
  '[.stories[]? | select(.story.state == "in-progress") | .story.id]')"
stuck_count="$(echo "$stuck_ids_json" | jq 'length')"

reset_ids=()
if [ "$stuck_count" -gt 0 ]; then
  while IFS= read -r id; do
    [ -z "$id" ] && continue
    if story move "$id" todo "crash recovery: reset by forge-crash-recover.sh" >/dev/null 2>&1; then
      reset_ids+=("$id")
    fi
  done <<< "$(echo "$stuck_ids_json" | jq -r '.[]')"
fi

# Clean working tree unconditionally, matching recovery-protocol.md's Step 4
# (crash recovery always cleans the tree, not only when a stuck story was
# found — a crash can leave uncommitted generator output behind even if the
# story state transition itself already landed).
git checkout . >/dev/null 2>&1 || true
tree_clean="true"
if [ -n "$(git status --porcelain 2>/dev/null | grep -v '^??' || true)" ]; then
  tree_clean="false"
fi

reset_json="[]"
if [ "${#reset_ids[@]}" -gt 0 ]; then
  reset_json="$(printf '%s\n' "${reset_ids[@]}" | jq -R . | jq -s .)"
fi
reset_count="${#reset_ids[@]}"

display="[forge] crash-recover: reset $reset_count stuck stor$([ "$reset_count" -eq 1 ] && echo y || echo ies), tree_clean=$tree_clean"
if [ "$reset_count" -gt 0 ]; then
  display="$display (${reset_ids[*]})"
fi

jq -n \
  --argjson ok true \
  --argjson reset_stories "$reset_json" \
  --argjson tree_clean "$tree_clean" \
  --arg display "$display" \
  '{ok: $ok, reset_stories: $reset_stories, tree_clean: $tree_clean, display: $display}'
