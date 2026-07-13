---
module: plugins/rca/agent-overrides
summary: "Per-step context briefs the rca skill injects into shared agents (evidence, experiment, fix, report, postmortem)."
read_when: "Changing an rca agent's brief or write scope"
sources:
  - path: plugins/rca/agent-overrides/evidence-collector-context.md
    blob: f30f889d3c6de0bfd690a73049a5618f3fe1be34
  - path: plugins/rca/agent-overrides/experimenter-context.md
    blob: d7c48695e0779460c5291892ad1831cb9e869688
  - path: plugins/rca/agent-overrides/hypothesis-challenger-context.md
    blob: f9b8c82d607e104ea17863a71943fd23c43510e2
  - path: plugins/rca/agent-overrides/investigator-context.md
    blob: b21c7081a15cb3a01a18aa4dc65d8dba358fbd7b
  - path: plugins/rca/agent-overrides/qa-engineer-context.md
    blob: db2cb628dc4acb8893bf9b58fba7a7621b8b7ab4
  - path: plugins/rca/agent-overrides/software-architect-context.md
    blob: f807d44a43a4e9c60730ff0eea717b6eea0fa88f
  - path: plugins/rca/agent-overrides/software-engineer-context.md
    blob: a89aa6b5f43dbb3f872285a53708319035f38ae0
  - path: plugins/rca/agent-overrides/technical-writer-context.md
    blob: 6912747c1028262fc80e9442fada5775546d6b13
generator: cartographer/4
baseline: 7387d3614aaae8d5a5bc156cf01c251d22b1dd45
---

# Module: plugins/rca/agent-overrides

## Purpose

These eight files layer rca-pipeline-specific briefs onto the shared general-purpose agents (plugins/agents/agents/) — naming which investigation step is active, which artifacts the dispatching skill has placed in the prompt (GRID.md, REPRO.md, DIAGNOSIS.md, REMEDIATION.md, etc.), and what the agent's report must contain — so one generic investigator/engineer/architect definition can be reused unmodified across rca's diagnose/locate/reproduce/fix/report/postmortem steps. Nearly all are read-only report generators; the rca skill (outside this module) owns every artifact write, and the three agents given write access (experimenter, qa-engineer, software-engineer) are each fenced to a single, narrowly scoped location. Without these overrides the shared agents would carry no RCA vocabulary or scope fence and could drift outside the artifact/worktree discipline the pipeline depends on.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

Six of the eight override files are strictly read-only — the agent returns a report and the rca orchestrator (the dispatching skill, outside this module) persists it as the named artifact: hypothesis-challenger returns to the skill which writes CHALLENGE.md (plugins/rca/agent-overrides/hypothesis-challenger-context.md:35); investigator likewise for ORIGIN.md (plugins/rca/agent-overrides/investigator-context.md:17); software-architect for REPORT.md/REMEDIATION.md (plugins/rca/agent-overrides/software-architect-context.md:39); evidence-collector for both its sections (plugins/rca/agent-overrides/evidence-collector-context.md:35-36). The three exceptions each get a narrowly fenced write scope instead: experimenter may modify files only inside the disposable worktree `.claude/worktrees/rca/<slug>/worktree` (plugins/rca/agent-overrides/experimenter-context.md:12-15); qa-engineer may create only new test/fixture files, with the dispatching skill reverting any undeclared change found via `git status --porcelain` (plugins/rca/agent-overrides/qa-engineer-context.md:18-21); software-engineer may modify only what REMEDIATION.md scopes, must not commit, and must not touch version/changelog/deploy files (plugins/rca/agent-overrides/software-engineer-context.md:15-17,23-24); technical-writer's write scope is exactly one new file, `docs/rca/<slug>.md` (plugins/rca/agent-overrides/technical-writer-context.md:30-31).

## External deps


## Gotchas

- evidence-collector-context.md is the only override serving two distinct rca steps (diagnose sweep and fix sibling-sweep) from a single file — the caller's prompt names which `## Section:` is active, not the file itself (plugins/rca/agent-overrides/evidence-collector-context.md:3).
- experimenter-context.md requires the agent to refuse outright, rather than fall back to the main tree, when its prompt lacks a worktree path, since the worktree is the only place it may modify files (plugins/rca/agent-overrides/experimenter-context.md:15).
