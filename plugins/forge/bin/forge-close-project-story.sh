#!/usr/bin/env bash
# forge-close-project-story.sh — explicitly close the decompose-created
# "project story" once every real task story is done.
#
# `story decompose` auto-creates a synthetic parent story from PLAN.md's
# `## Task Breakdown` heading and records its ID as `project_story` in
# plan-mapping.json (see references/story-decomposition.md). storyhook's
# `story next` permanently excludes ANY story with children from ever being
# offered (a `has_children` filter in storyhook's own src/app.rs — out of
# scope to change, see the hardening plan's HARD CONSTRAINT), so the project
# story can never reach `done` by the normal generator/evaluator loop path a
# leaf task story does. Left alone, it stays `todo` forever even after every
# real task story is done.
#
# forge-state.sh's check_storyhook() already excludes project_story from its
# "are all stories done" computation (reading it directly from
# plan-mapping.json), so the pipeline advances correctly whether or not this
# script ever runs — that read-only exclusion is what actually fixes the
# deadlock. This script is a separate, best-effort hygiene step: it actually
# closes the project story for real, so `story list` / `story summary`
# don't show a permanently-open story to anyone inspecting the project later.
# The execute loop's Complete step (references/execution-loop-complete.md) calls this
# once all real work is done. The close writes to storyhook's own store, which
# is outside the repository, so nothing about it reaches a commit (AGE-11).
#
# Usage: forge-close-project-story.sh [project-dir]
#
# Output (always exit 0 — callers branch on the JSON, not the exit code):
#   {ok, closed, project_story, reason, display}
#     ok             - true if the script ran to completion far enough to
#                       make a real decision (story CLI reachable, plan
#                       mapping + story list parsed). false means the
#                       decision was skipped entirely — check `reason`.
#     closed         - true only if this invocation actually issued
#                       `story move <project_story> done`.
#     project_story  - the story ID read from plan-mapping.json, or "" if
#                       none was recorded.
#     reason         - machine-readable outcome token, one of:
#                       no_plan_mapping | no_project_story_recorded |
#                       story_cli_missing | story_list_failed |
#                       project_story_not_found | already_done |
#                       tasks_incomplete | closed | move_failed
#     display        - human-readable summary.
set -euo pipefail

PROJECT_DIR="${1:-.}"
cd "$PROJECT_DIR"

FORGE_DIR=".forge"
MAPPING_FILE="$FORGE_DIR/plan-mapping.json"

emit() {
  local ok="$1" closed="$2" project_story="$3" reason="$4" display="$5"
  jq -n \
    --argjson ok "$ok" \
    --argjson closed "$closed" \
    --arg project_story "$project_story" \
    --arg reason "$reason" \
    --arg display "$display" \
    '{ok: $ok, closed: $closed, project_story: $project_story, reason: $reason, display: $display}'
}

if [ ! -f "$MAPPING_FILE" ] || ! jq -e . "$MAPPING_FILE" >/dev/null 2>&1; then
  emit true false "" "no_plan_mapping" \
    "[forge] close-project-story: skipped — no plan-mapping.json"
  exit 0
fi

project_story="$(jq -r '.project_story // ""' "$MAPPING_FILE")"
if [ -z "$project_story" ]; then
  emit true false "" "no_project_story_recorded" \
    "[forge] close-project-story: skipped — plan-mapping.json has no project_story"
  exit 0
fi

if ! command -v story >/dev/null 2>&1; then
  emit false false "$project_story" "story_cli_missing" \
    "[forge] close-project-story: skipped — \`story\` CLI not found"
  exit 0
fi

story_out_file="$(mktemp)"
story_err_file="$(mktemp)"
trap 'rm -f "$story_out_file" "$story_err_file"' EXIT

if ! story list --json >"$story_out_file" 2>"$story_err_file"; then
  story_err="$(cat "$story_err_file")"
  emit false false "$project_story" "story_list_failed" \
    "[forge] close-project-story: skipped — \`story list --json\` failed: $story_err"
  exit 0
fi
story_json="$(cat "$story_out_file")"

project_story_state="$(echo "$story_json" | jq -r --arg ps "$project_story" \
  '.stories[]? | select(.story.id == $ps) | .story.state')"

if [ -z "$project_story_state" ]; then
  emit true false "$project_story" "project_story_not_found" \
    "[forge] close-project-story: skipped — project story $project_story not found in \`story list\`"
  exit 0
fi

if [ "$project_story_state" = "done" ]; then
  emit true false "$project_story" "already_done" \
    "[forge] close-project-story: no-op — $project_story is already done"
  exit 0
fi

# Every OTHER story (i.e. every real task story) must be done before we
# close the project story — same non-done computation forge-state.sh's
# check_storyhook() uses, just scoped to this one script's own read.
non_done_tasks="$(echo "$story_json" | jq -r --arg ps "$project_story" \
  '[.stories[]? | select(.story.id != $ps and .story.state != "done")] | length')"

if [ "$non_done_tasks" -gt 0 ]; then
  emit true false "$project_story" "tasks_incomplete" \
    "[forge] close-project-story: no-op — $non_done_tasks task story(ies) still not done"
  exit 0
fi

if story move "$project_story" done >/dev/null 2>&1; then
  emit true true "$project_story" "closed" \
    "[forge] close-project-story: closed $project_story — all real task stories done"
else
  emit false false "$project_story" "move_failed" \
    "[forge] close-project-story: \`story move $project_story done\` failed"
fi
