---
module: plugins/forge/agent-overrides
summary: "Forge-specific spawn context for six shared agents: story-state, artifact paths, tool limits, and output routing."
read_when: "Changing forge subagent behavior, .forge/ artifact contracts, or spawn constraints"
sources:
  - path: plugins/forge/agent-overrides/evaluator-context.md
    blob: a9b3a49d4d5ebf054eec576559f86c15b0f4f7f9
  - path: plugins/forge/agent-overrides/generator-context.md
    blob: 7cfe83c7aecca257061630df1443dacfdde444e4
  - path: plugins/forge/agent-overrides/reviewer-context.md
    blob: b72d589ac8e14956dd32cabe8503d6a5103e499d
  - path: plugins/forge/agent-overrides/software-architect-context.md
    blob: 2283713d27c0e76d163e78005ac1e6fa2f4b7600
  - path: plugins/forge/agent-overrides/triager-context.md
    blob: b51ebee1c0507cd29d9411a2a2d7c11afbdef06f
  - path: plugins/forge/agent-overrides/validator-context.md
    blob: 6c5cdda4751783942cd670dab20b4ca42bb065b3
generator: cartographer/4
baseline: 50c998d53e2ed58951ac5f794afd32bfa729f658
---

# Module: plugins/forge/agent-overrides

## Purpose

This module supplies forge-specific spawn context for six shared, pipeline-agnostic agent roles — evaluator, generator, reviewer, software-architect, triager, and validator — stating only what forge adds atop each role's base contract (referenced in-file as evaluator.md, reviewer.md, and triager.md): which story state the orchestrator already set (plugins/forge/agent-overrides/generator-context.md:9, plugins/forge/agent-overrides/evaluator-context.md:29), which .forge/ artifact paths to read, must write, or must never touch (plugins/forge/agent-overrides/validator-context.md:7, plugins/forge/agent-overrides/generator-context.md:5), and where its findings ultimately land once the orchestrator synthesizes them (plugins/forge/agent-overrides/triager-context.md:11-15). Without this layer the shared agents would run generically — unaware of .forge/ file layout, storyhook's 4KB comment ceiling, or which step's SKILL.md owns writing the combined report — and forge's FIX/ESCALATE routing and per-role output contracts would silently break.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

Ownership by write access is asymmetric and role-specific: generator alone gets Write but is forbidden from touching .forge/ state files or committing, enforced by pre/post checksums of config.json and state.json (plugins/forge/agent-overrides/generator-context.md:1-5); evaluator, reviewer, triager, and the execution-loop software-architect are read-only / no-Write-Edit by contract regardless of spawn path (plugins/forge/agent-overrides/evaluator-context.md:3-8, plugins/forge/agent-overrides/reviewer-context.md:7, plugins/forge/agent-overrides/triager-context.md:11, plugins/forge/agent-overrides/software-architect-context.md:27); validator is the sole role that owns writing an output file directly, .forge/VALIDATE-REPORT.md (plugins/forge/agent-overrides/validator-context.md:7). Lifecycle is orchestrator-driven: the story is moved to in-progress and the tree cleaned before the generator spawns, and to verifying before the evaluator spawns, with each agent's return value deciding the next transition (plugins/forge/agent-overrides/generator-context.md:9, plugins/forge/agent-overrides/evaluator-context.md:29). Review and validate are explicitly concurrent siblings feeding the same downstream triager (plugins/forge/agent-overrides/reviewer-context.md:3, plugins/forge/agent-overrides/validator-context.md:3, plugins/forge/agent-overrides/triager-context.md:5), and the write/no-write invariants above are enforced externally by orchestrator diff/checksum checks, not by agent self-discipline alone (plugins/forge/agent-overrides/generator-context.md:3-6, plugins/forge/agent-overrides/evaluator-context.md:10-16).

## External deps


## Gotchas

The evaluator's post-execution integrity check is a known-incomplete heuristic (git diff --name-only): it cannot see an edit to a file the generator already touched, or a brand-new untracked file the evaluator itself creates — only bin/forge-integrity.sh's full content-hash check closes that gap, so the tool restriction (not the diff heuristic) is the real boundary (plugins/forge/agent-overrides/evaluator-context.md:12-16). Integrity-violation handling is asymmetric: if the generator's HEAD moves (i.e. it committed), the story is blocked for user review rather than auto-recovered, explicitly because 'a commit can't be safely un-made without risking other work' — a stricter response than other violations get (plugins/forge/agent-overrides/generator-context.md:3).
