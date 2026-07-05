---
module: "plugins/agents/agents (chunk 2)"
summary: "Shared agent library, investigator–technical-writer: general specialists, atlas's map pair, forge's reviewer"
read_when: "Touching the shared agents investigator through technical-writer (incl. map-verifier)"
sources:
  - path: plugins/agents/agents/investigator.md
    blob: 3a140ee738ce520e566b8e61f683eabfca3433e6
  - path: plugins/agents/agents/lawyer.md
    blob: 5fda3e7a2e1bdc8297d9be3b223c932af798f127
  - path: plugins/agents/agents/map-repairer.md
    blob: 564b2ad94074890dcdf5a2a60ae0bb91b237d421
  - path: plugins/agents/agents/map-verifier.md
    blob: ac52315a17ab18080ad6ad89c57a77998e802aed
  - path: plugins/agents/agents/observability-engineer.md
    blob: eca36942ef2fc5771d811f8a7e758867d7207bf6
  - path: plugins/agents/agents/performance-engineer.md
    blob: 846b109f5b2225e9084733564c9dfbd38df0a527
  - path: plugins/agents/agents/project-manager.md
    blob: e969875e8b4425656e79735a9a52baeaafed37d1
  - path: plugins/agents/agents/qa-engineer.md
    blob: cf5566ed98b94145f5a4a2a60a3e18f8a75de330
  - path: plugins/agents/agents/reviewer.md
    blob: 0271c45f317b4ff3e824559b49f0a305938dea4f
  - path: plugins/agents/agents/security-researcher.md
    blob: ab64243cb5c0edbd1c34797b5941472a45e0732a
  - path: plugins/agents/agents/skeptic.md
    blob: f961e8361a32ff2be468d16c71c9575ad2e84069
  - path: plugins/agents/agents/software-architect.md
    blob: c3abdf88838589d5c78cfe5669e730737bf0195c
  - path: plugins/agents/agents/software-engineer.md
    blob: 8ebb8be26e64490f77669942f1b88c3bab9a2246
  - path: plugins/agents/agents/technical-writer.md
    blob: fcec96880785ebb5409208d8d8d2abc35ef9f375
generator: cartographer/4
baseline: 50c998d53e2ed58951ac5f794afd32bfa729f658
---

# Module: plugins/agents/agents (chunk 2)

## Purpose

This is the alphabetical middle third of the shared agent library (plugins/agents/agents/): eleven general-tier specialists — investigator, lawyer, observability-engineer, performance-engineer, project-manager, qa-engineer, security-researcher, skeptic, software-architect, software-engineer, technical-writer — spanning investigation, legal risk, ops, planning, QA, security, and documentation, plus three pipeline-specific distillations: atlas's map-repairer/map-verifier verify-then-fix pair and forge's reviewer. Each file is a self-contained spawn contract (YAML frontmatter + <role> body) inlined verbatim by whichever pipeline calls it, so the same investigator or skeptic definition serves rca, forge, and atlas without per-pipeline reimplementation. Read-only-by-default is the chunk's organizing discipline: 8 of the 14 agents carry read_only: true and return structured verdicts or reports rather than edits, keeping analysis strictly separated from the write-capable agents (map-repairer, observability-engineer, project-manager, qa-engineer, software-engineer, technical-writer) that act on those findings.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

- `read_only: true` gates 8 of the 14 agents (investigator, lawyer, map-verifier, performance-engineer, security-researcher, skeptic, software-architect, reviewer) to Read/Grep/Glob(+Bash/WebSearch) only, with no Write/Edit tool granted — e.g. `plugins/agents/agents/investigator.md:4,8`.
- `map-repairer` is the only write-capable pipeline-specific agent here, but its Edit-only tool list (no Write) restricts it to a single already-existing doc so untouched lines stay byte-identical — `plugins/agents/agents/map-repairer.md:4,70`.
- `reviewer` is the chunk's only `pipeline: forge` agent; `map-repairer` and `map-verifier` are the chunk's only `pipeline: atlas` agents — `plugins/agents/agents/reviewer.md:6-7`, `plugins/agents/agents/map-repairer.md:6-7`, `plugins/agents/agents/map-verifier.md:6-7`.
- Only these 3 pipeline-specific agents declare a prose `Lineage` line naming which general-tier agents they draw methodology from; the 11 general-tier agents in this chunk don't — `plugins/agents/agents/map-repairer.md:16`, `plugins/agents/agents/map-verifier.md:16`, `plugins/agents/agents/reviewer.md:16`.
- Every agent's `<role>` body opens with the same Mandatory Initial Read `<files_to_read>` protocol before any other action — e.g. `plugins/agents/agents/investigator.md:16-17`.

## External deps


## Gotchas

- `map-verifier`'s `pass` verdict goes false once 3 or more minor failures accumulate, even with zero majors — not a simple any-major-fails rule — `plugins/agents/agents/map-verifier.md:76`.
- `lawyer` must prepend its legal-risk disclaimer to every single output with no exceptions, even though it is read-only and never drafts binding legal documents — `plugins/agents/agents/lawyer.md:187`.
