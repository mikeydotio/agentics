#!/usr/bin/env bash
# forge-dag-validate.sh — detect blocked-by cycles in the storyhook dependency graph
#
# Loads `story list --json`, builds the `blocked-by` adjacency graph (the only
# edges the dependency scheduler / `story next` / `story graph` act on — see
# references/storyhook-contract.md), and runs a DFS cycle search over it.
#
# `story decompose` only ever emits forward cross-wave `blocked-by` edges, which
# are acyclic by construction, so this exists to catch cycles introduced by
# manual `story relate` calls (before this decompose run or resumed from an
# existing plan-mapping.json) — neither `story doctor` (parent/child cycles
# only) nor `story graph` (no cycle report, see below) catches these.
#
# Usage: forge-dag-validate.sh [project-dir]
#
# Output (always exit 0 — callers branch on the JSON, not the exit code):
#   {ok, has_cycles, cycles, story_count, display}
#     ok         - true if the check ran to completion (story CLI reachable,
#                  `story list --json` parsed). false means the check was
#                  skipped, not that a cycle was found.
#     has_cycles - true if one or more blocked-by cycles were found. Only
#                  meaningful when ok is true.
#     cycles     - array of cycles; each cycle is an array of story IDs that
#                  closes back on its first element (e.g. ["HP-2","HP-4","HP-2"]).
#                  One representative cycle is reported per unvisited DFS root —
#                  not necessarily every simple cycle in the graph, but enough
#                  to prove a cycle exists and show the caller where to look.
#     story_count- number of open stories considered.
#     display    - human-readable summary.
set -euo pipefail

PROJECT_DIR="${1:-.}"
cd "$PROJECT_DIR"

if ! command -v story >/dev/null 2>&1; then
  jq -n '{ok: false, has_cycles: false, cycles: [], story_count: 0,
          error: "story_cli_missing",
          display: "[forge] DAG validation skipped: `story` CLI not found"}'
  exit 0
fi

# Capture stdout/stderr to separate temp files rather than merging with 2>&1:
# a successful call must yield pure JSON on stdout, even if the CLI ever
# writes an incidental warning to stderr alongside a 0 exit.
story_out_file="$(mktemp)"
story_err_file="$(mktemp)"
trap 'rm -f "$story_out_file" "$story_err_file"' EXIT

if ! story list --json >"$story_out_file" 2>"$story_err_file"; then
  story_err="$(cat "$story_err_file")"
  jq -n --arg err "$story_err" \
    '{ok: false, has_cycles: false, cycles: [], story_count: 0,
      error: "story_list_failed", details: $err,
      display: ("[forge] DAG validation skipped: `story list --json` failed: " + $err)}'
  exit 0
fi
story_json="$(cat "$story_out_file")"

# DFS cycle search over the blocked-by graph, entirely in jq (bash on macOS
# ships 3.2, which has no associative arrays — see CLAUDE.md — so the graph
# and its traversal state live in jq, not bash).
result="$(echo "$story_json" | jq '
  def blocked_by_graph:
    (.stories | map(.story)) as $stories
    | ($stories | map(.id)) as $ids
    | ($stories
        | map({key: .id, value: [.relationships[]? | select(.relation == "blocked-by") | .other_id]})
        | from_entries) as $adjraw
    # Drop edges to ids outside the open-story set (e.g. a stale/deleted
    # reference) — they cannot participate in a cycle we can act on.
    | ($adjraw | with_entries(.value |= map(select(. as $t | $ids | index($t) != null)))) as $adj
    | {ids: $ids, adj: $adj};

  def dfs($adj; $node; $state):
    ($state | .color[$node] = 1 | .stack += [$node]) as $entered
    | (reduce ($adj[$node][]? ) as $nbr
        ($entered;
          if (.color[$nbr] // 0) == 1 then
            (.stack | index($nbr)) as $i
            | .cycles += [ (.stack[$i:] + [$nbr]) ]
          elif (.color[$nbr] // 0) == 0 then
            dfs($adj; $nbr; .)
          else
            .
          end
        )) as $visited
    | ($visited | .color[$node] = 2 | .stack |= .[0:-1]);

  def find_cycles:
    blocked_by_graph as $g
    | reduce $g.ids[] as $id
        ({color: {}, stack: [], cycles: []};
          if (.color[$id] // 0) == 0 then dfs($g.adj; $id; .) else . end
        )
    | .cycles;

  {story_count: (.stories | length), cycles: find_cycles}
')"

story_count="$(echo "$result" | jq '.story_count')"
cycles_json="$(echo "$result" | jq -c '.cycles')"
has_cycles="$(echo "$result" | jq '(.cycles | length) > 0')"

if [ "$has_cycles" = "true" ]; then
  cycle_count="$(echo "$cycles_json" | jq 'length')"
  display="[forge] DAG validation: FAILED — ${cycle_count} blocked-by cycle(s) found among ${story_count} open stories"
  while IFS= read -r cycle_line; do
    display="$display
  - $(echo "$cycle_line" | jq -r 'join(" -> ")')"
  done <<< "$(echo "$cycles_json" | jq -c '.[]')"
else
  display="[forge] DAG validation: OK — no blocked-by cycles among ${story_count} open stories"
fi

jq -n \
  --argjson has_cycles "$has_cycles" \
  --argjson cycles "$cycles_json" \
  --argjson story_count "$story_count" \
  --arg display "$display" \
  '{ok: true, has_cycles: $has_cycles, cycles: $cycles, story_count: $story_count, display: $display}'
