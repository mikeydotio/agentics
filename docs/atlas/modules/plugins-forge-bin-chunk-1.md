---
module: "plugins/forge/bin (chunk 1)"
summary: "Forge bin/ drift guards (agent roster, storyhook CLI) plus .forge archiving, crash recovery, and DAG cycle detection."
read_when: "Touching forge's drift guards, .forge archiving, crash recovery, or DAG cycle detection"
sources:
  - path: plugins/forge/bin/forge-agent-alignment-check.bats
    blob: 2be7d7e0252ef7c2f3d58fdd80bb0be7ce22865e
  - path: plugins/forge/bin/forge-agent-alignment-check.sh
    blob: cad94fd7aa3b4181c6db27118d500a3f383345cd
  - path: plugins/forge/bin/forge-archive.bats
    blob: f754dcb6446ba9a569f3b03cce3c2dcfce2a2b7e
  - path: plugins/forge/bin/forge-archive.sh
    blob: c3423e09b2e3b9c60f47dca03a2b60bfece5a538
  - path: plugins/forge/bin/forge-close-project-story.bats
    blob: 3fc002f461b00724b8030d282d2db695221b1840
  - path: plugins/forge/bin/forge-close-project-story.sh
    blob: 77f26817274b858bd20baabd1d7c0e9025ea9ec9
  - path: plugins/forge/bin/forge-contract-check.bats
    blob: c681535eb3474d14e4f55ad92dc7a2f66087657f
  - path: plugins/forge/bin/forge-contract-check.sh
    blob: 0d79fdb5cb020b48d60c349139923134db3c2e4c
  - path: plugins/forge/bin/forge-crash-recover.bats
    blob: 806681a59664e4132f9a230085e4e15782008185
  - path: plugins/forge/bin/forge-crash-recover.sh
    blob: 402f93159c147940faed7faf0a2244b7d8410da4
  - path: plugins/forge/bin/forge-dag-validate.bats
    blob: a9e7114d35591ab9b75224fe9ca7c27543ed05d1
  - path: plugins/forge/bin/forge-dag-validate.sh
    blob: 6458f5f4a75663dfdfda7146d0c795d631a49a06
  - path: plugins/forge/bin/forge-fix-archive.bats
    blob: 6ee57d2039827686e39b4836a37e3b9442d25b73
  - path: plugins/forge/bin/forge-fix-archive.sh
    blob: 5d47adc896de14abbac6ec082f69c4bc3cefddad
  - path: plugins/forge/bin/forge-handoff-scaffold.bats
    blob: 6d60f36eed5d6141ae15c38b5d602c73805f6bb5
generator: cartographer/4
baseline: cb09ceb006e3fb4759a91d64d9e6655e67d04bf7
---

# Module: plugins/forge/bin (chunk 1)

## Purpose

This chunk is forge's bin/ safety-net layer: two regression guards, forge-agent-alignment-check.sh and forge-contract-check.sh, read the REAL shared-agents roster and the REAL storyhook `--help`/`help relate` output at runtime instead of hardcoding a roster or verb list, so forge's docs/skills can never silently drift back to a dead agent name or a fictional CLI grammar the way they already did once (each script's header cites the past incident). The remaining scripts are the pipeline's state-hygiene layer — archiving and resetting `.forge/` artifacts between runs and fix cycles, undoing a crashed mid-step, closing the decompose-created synthetic project story, and detecting blocked-by cycles in the storyhook dependency graph before the scheduler acts on a corrupted one. Remove this chunk and forge loses both its only automated defense against the documentation/CLI drift its own hardening audit found, and the scripted archival/crash-recovery/cycle-detection guarantees that keep `.forge/` state trustworthy across runs.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `blocked_by_graph` | def | `plugins/forge/bin/forge-dag-validate.sh:63` | Builds `{ids, adj}`, the blocked-by adjacency graph from `story list --json`, dropping edges to ids outside the open story set. |
| `dfs` | def | `plugins/forge/bin/forge-dag-validate.sh:74` | Recursive DFS over `$adj`; updates `$state`'s color/stack and appends any back-edge cycle found to `.cycles`. |
| `emit` | def | `plugins/forge/bin/forge-agent-alignment-check.sh:69` | Serializes `obj` to one JSON line on stdout — the script's sole output channel; every exit path calls it before returning 0. |
| `find_cycles` | def | `plugins/forge/bin/forge-dag-validate.sh:89` | Folds `dfs` from every unvisited story id over `blocked_by_graph`'s adjacency, returning all detected blocked-by cycles. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

Every script here is a standalone bash CLI (`set -euo pipefail`) that always exits 0 and reports failure only via a JSON `ok`/`error` field, so callers branch on the JSON body, not the exit code (plugins/forge/bin/forge-crash-recover.sh:12-17, plugins/forge/bin/forge-dag-validate.sh:16-20). forge-dag-validate.sh's cycle search is written entirely in jq rather than bash because "bash on macOS ships 3.2, which has no associative arrays" (plugins/forge/bin/forge-dag-validate.sh:59-61). forge-agent-alignment-check.sh's real logic lives in an embedded python3 heredoc and degrades to a still-`ok:false`-shaped skip result when python3 is absent (plugins/forge/bin/forge-agent-alignment-check.sh:54-59). forge-close-project-story.sh is explicitly a best-effort hygiene action — its own header states the actual deadlock fix is forge-state.sh's read-only exclusion of `project_story` from its done-computation elsewhere in the pipeline (plugins/forge/bin/forge-close-project-story.sh:15-21).

## External deps

- json — imported
- os — imported
- re — imported
- sys — imported

## Gotchas

forge-contract-check.sh only checks the first qualifying `story` invocation per line — a chained `story a && story b` on one line would miss the second (plugins/forge/bin/forge-contract-check.sh:161-163). forge-dag-validate.sh deliberately keeps `story list --json`'s stdout and stderr in separate temp files instead of merging with `2>&1`, so an incidental stderr warning on a successful 0-exit call can't corrupt the JSON parse (plugins/forge/bin/forge-dag-validate.sh:42-47). forge-close-project-story.sh exists only because storyhook's `story next` permanently excludes any story with children via a `has_children` filter in storyhook's own src/app.rs, called out as an out-of-scope HARD CONSTRAINT this script works around rather than changes (plugins/forge/bin/forge-close-project-story.sh:8-13).
