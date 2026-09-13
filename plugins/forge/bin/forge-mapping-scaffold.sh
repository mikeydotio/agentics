#!/usr/bin/env bash
# forge-mapping-scaffold.sh — mechanical skeleton assembly for
# .forge/plan-mapping.json (F035): computes plan_hash portably, and reads
# the real post-`story decompose` story list so IDs/titles/project_story
# come from storyhook rather than being assumed or hand-typed.
#
# Usage: forge-mapping-scaffold.sh --plan <path-to-PLAN.md> [--project-dir .]
#
# Genuine judgment stays with the model: matching each story to the right
# DESIGN.md section (`design_section`), recording `task_ref`/`wave` from
# PLAN.md's wave structure, and listing `files_expected`. This script only
# hands back a skeleton with those fields present-but-null (or `[]` for
# `files_expected`) for the model to fill in, plus every mechanical field it
# can compute with certainty.
#
# Output: {ok, plan_hash, project_story, stories, display}
#   stories - {<story_id>: {task_ref, wave, title, acceptance_criteria,
#              design_section, files_expected}} for every story EXCEPT the
#              synthetic project_story (identified by having a `parent-of`
#              relationship — see references/story-decomposition.md).
#              `title` is the only field this script can fill; the rest are
#              null/[] placeholders.
set -euo pipefail

PROJECT_DIR="."
PLAN_FILE=".forge/PLAN.md"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan)         PLAN_FILE="$2"; shift 2 ;;
    --plan=*)       PLAN_FILE="${1#*=}"; shift ;;
    --project-dir)  PROJECT_DIR="$2"; shift 2 ;;
    --project-dir=*) PROJECT_DIR="${1#*=}"; shift ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

cd "$PROJECT_DIR"

if [ ! -f "$PLAN_FILE" ]; then
  jq -n --arg f "$PLAN_FILE" \
    '{ok: false, error: "plan_not_found", display: ("[forge] mapping-scaffold: PLAN.md not found at " + $f)}'
  exit 0
fi

# Portable MD5 — no GNU md5sum / BSD md5 flag differences to reconcile;
# python3 stdlib is on every target per this repo's portability convention.
plan_hash="$(python3 -c '
import hashlib, sys
with open(sys.argv[1], "rb") as f:
    print(hashlib.md5(f.read()).hexdigest())
' "$PLAN_FILE")"

project_story=""
stories_json="{}"
story_list='{"stories":[]}'

if command -v story >/dev/null 2>&1; then
  # `story list --all --json` writes its JSON body to stdout on BOTH success and
  # failure (an uninitialized project still emits a `{"result":"error",...}`
  # envelope to stdout, not stderr) — a bare `cmd || echo fallback` would
  # concatenate the failed call's own stdout with the fallback, handing jq
  # two JSON documents instead of one. Only adopt the real output when the
  # command actually exited 0; otherwise keep the empty-stories default.
  story_list_out=""
  if story_list_out="$(story list --all --json 2>/dev/null)"; then
    story_list="$story_list_out"
  fi

  # The project story is decompose's synthetic parent — identified by
  # actually having a parent-of relationship (relation field, per storyhook's
  # real JSON shape — NOT array position/order, which storyhook does not
  # document as stable).
  project_story="$(echo "$story_list" | jq -r '
    [.stories[]?
      | select([.story.relationships[]? | select(.relation == "parent-of")] | length > 0)
      | .story.id
    ] | (.[0] // "")
  ')"

  stories_json="$(echo "$story_list" | jq --arg ps "$project_story" '
    [.stories[]? | select(.story.id != $ps) | {
      (.story.id): {
        task_ref: null,
        wave: null,
        title: .story.title,
        acceptance_criteria: null,
        design_section: null,
        files_expected: []
      }
    }] | add // {}
  ')"
fi

story_count="$(echo "$stories_json" | jq 'length')"
display="[forge] mapping-scaffold: plan_hash computed, ${story_count} story skeleton(s), project_story=${project_story:-<none>}"

jq -n \
  --arg plan_hash "$plan_hash" \
  --arg project_story "$project_story" \
  --argjson stories "$stories_json" \
  --arg display "$display" \
  '{ok: true, plan_hash: $plan_hash, project_story: $project_story, stories: $stories, display: $display}'
