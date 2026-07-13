---
module: plugins/rca/bin
summary: "Deterministic bash+jq CLI scripts backing rca: forensics, bisect, repro, hotspots, stack, scaffold, status, worktree."
read_when: "Touching rca's bin scripts (forensics, bisect, repro)"
sources:
  - path: plugins/rca/bin/rca-bisect.sh
    blob: 3f1dd62d4e6a4c4e9c3fb2fec240471d7160e6e6
  - path: plugins/rca/bin/rca-forensics.sh
    blob: 19ae014dbe722a10414e0a029535c30171dd3702
  - path: plugins/rca/bin/rca-hotspots.sh
    blob: 6e1cb8e82362cb434cc11d69434fafaf193fb817
  - path: plugins/rca/bin/rca-repro.sh
    blob: 70e6989aca1ac22e008c7ceeddc3c218685c7637
  - path: plugins/rca/bin/rca-scaffold.sh
    blob: c782b42d4f3d9e25b64c5d9a77507a753587728e
  - path: plugins/rca/bin/rca-stack.sh
    blob: d8ebc3cd169089292a024946048151f58ba4f4c7
  - path: plugins/rca/bin/rca-status.sh
    blob: 330d49a9cf4a92ebab0c54542f1a043b20ebf4e0
  - path: plugins/rca/bin/rca-worktree.sh
    blob: 3f0be46cca8dcc840ac9d6b4de3f6e8c4288b1ce
generator: cartographer/4
baseline: 7387d3614aaae8d5a5bc156cf01c251d22b1dd45
---

# Module: plugins/rca/bin

## Purpose

This is the deterministic execution layer behind the rca pipeline: eight self-contained bash+jq scripts that do git archaeology (forensics, hotspots), drive automated bisection and repro-loop runs, detect a project's test stack, and manage the isolated worktree investigations bisect against, all emitting a uniform {ok:true|false,...,display} JSON envelope with snake_case error codes so the orchestrating skill never parses free text. Every script independently guards its own preconditions (jq/git present, inside a git repo, a worktree exists) rather than relying on a shared runtime, which is what lets the pipeline shell out to any one of them standalone or from a scratch worktree. Losing this module would strip /rca of its evidence-gathering and safe-regression-bisection primitives, forcing investigators back to raw git commands with no structured output for the pipeline to act on.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `process` | function | `plugins/rca/bin/rca-hotspots.sh:73` | Private awk helper in rca-hotspots.sh's co-change script: flushes per-commit files into fcount/pair, resets nf; not externally callable. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

Investigation state is filesystem-resident under .rca/<slug>/ (meta.json plus phase artifacts); rca-status.sh's resolve_state walks a fixed artifact ladder (GRID.md → REPRO.md/OVERRIDE.md → tier → ORIGIN.md → INCONCLUSIVE.md/DIAGNOSIS.md → REPORT.md/REMEDIATION.md → APPROVAL.md → FIX.md → POSTMORTEM.md) to derive state/dispatch, so state is never stored, only inferred by file presence (plugins/rca/bin/rca-status.sh:47-60). Worktree lifecycle is separate and lives at <root>/.claude/worktrees/rca/<slug>/, with the checkout at .../worktree on branch rca/<slug> (plugins/rca/bin/rca-worktree.sh:44-46); create() mirrors worktree.json into .rca/<slug>/ only when that investigation directory already exists (plugins/rca/bin/rca-worktree.sh:106). rca-bisect.sh requires that worktree to already exist (plugins/rca/bin/rca-bisect.sh:9,87-89) and always tears it down via an EXIT trap regardless of outcome (plugins/rca/bin/rca-bisect.sh:99). Every script runs under `set -euo pipefail` and fails closed with a jq-built {ok:false,error,detail} envelope keyed by a stable snake_case error code (e.g. plugins/rca/bin/rca-scaffold.sh:22).

## External deps


## Gotchas

rca-repro.sh's run is intentionally a harness, not the test itself: a nonzero exit from --cmd is normal ok:true data (failure_rate up to 1.0), not a script error — only cmd_not_found (exit 127 on the first run) and timeout are real failures (plugins/rca/bin/rca-repro.sh:8-9,69-74). rca-bisect.sh's per-step wrapper maps build/setup failure and cmd exit 126/127 to skip(125), not bad(1) — only an in-range nonzero exit counts as a genuine regression (plugins/rca/bin/rca-bisect.sh:55-64). rca-status.sh's option_for has a catch-all default arm specifically to avoid an unset-variable crash under `set -u` that shipped in v1 (plugins/rca/bin/rca-status.sh:62-75). rca-scaffold.sh's init mutates the TARGET repo's top-level .gitignore as a side effect, idempotently appending .rca/ and .claude/worktrees/ if absent (plugins/rca/bin/rca-scaffold.sh:66-85). rca-worktree.sh's create deliberately leaves a failed worktree in place on setup-cmd failure for inspection, unlike rca-bisect.sh which always resets via an EXIT trap (plugins/rca/bin/rca-worktree.sh:87-99).
