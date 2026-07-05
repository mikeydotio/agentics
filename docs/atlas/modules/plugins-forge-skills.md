---
module: plugins/forge/skills
summary: "forge's router plus its 11 pipeline-step skills, each reading/writing .forge/ artifacts via step-exit."
read_when: "Changing forge pipeline steps, .forge/ artifacts, routing, or freshen/step-exit handoffs"
sources:
  - path: plugins/forge/skills/decompose/SKILL.md
    blob: bf231703a5952d58db5b29f25f312b2914627d37
  - path: plugins/forge/skills/deploy/SKILL.md
    blob: 634d5102104ff39ba5e771ad87ad9cc1a46e44cb
  - path: plugins/forge/skills/design/SKILL.md
    blob: a0e70ce969959d259e0b91763f3da940add731e1
  - path: plugins/forge/skills/document/SKILL.md
    blob: 1972c3cb49f7f7538cba45aff731b5b6a3b79107
  - path: plugins/forge/skills/execute/SKILL.md
    blob: bdc9663d1248481670e738ce7ab25263e6b1a6da
  - path: plugins/forge/skills/forge/SKILL.md
    blob: 2c7e8bf9ad86f93bcc33364bd0f2d2e4b6a39312
  - path: plugins/forge/skills/interrogate/SKILL.md
    blob: 2f9400424fad44a9209cbba2ceeedfda24686f5d
  - path: plugins/forge/skills/plan/SKILL.md
    blob: 7840a189a85b400a7ac27c3a557aeb3944d207f5
  - path: plugins/forge/skills/research/SKILL.md
    blob: 3621f665f9766495d3c55384fc3a494806bd7381
  - path: plugins/forge/skills/review/SKILL.md
    blob: b697fc5b2e8841baa33fdc5ecd621320a5cbd21b
  - path: plugins/forge/skills/triage/SKILL.md
    blob: 25701944d6de9a8232f933e47980eec0a283b3cd
  - path: plugins/forge/skills/validate/SKILL.md
    blob: e0f031e79e1edae5370dcdc2b245dc619456a1e5
generator: cartographer/4
baseline: 50c998d53e2ed58951ac5f794afd32bfa729f658
---

# Module: plugins/forge/skills

## Purpose

This directory is forge's entire step vocabulary: the state-machine router (skills/forge/SKILL.md) that detects pipeline state from .forge/ artifacts and storyhook and dispatches, plus the 11 pipeline-step skills (interrogate through deploy) it dispatches to. Each step skill is a self-contained, stateless prompt — it reads its own inputs from .forge/, does its work (often by spawning specialist subagents from the shared agent library), writes its outputs, and exits through the shared Step Exit Protocol (handoff, commit, queue freshen, STOP) so no state has to survive in conversation context between steps. Without this module the router has a state machine but nothing to dispatch to — these files are the actual behavior of the idea-to-deployment pipeline, not just its shape.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

- Steps are stateless single-shot prompts, not persistent objects: state lives in .forge/ artifacts and storyhook, re-read from disk on every invocation — execute's Fresh-Start-vs-Resume branch is decided by reading `state_json_exists` from forge-state.sh's output, never inferred from conversation context (plugins/forge/skills/execute/SKILL.md:48-59).
- review and validate are mutually unaware siblings: neither's Exit checks whether the other's report exists before queuing freshen; forge-state.sh alone owns deciding whether review, validate, or both still need to run (plugins/forge/skills/review/SKILL.md:108-116; plugins/forge/skills/validate/SKILL.md:120-126).
- `reviewer` and `triager` are read_only:true subagents that return findings/decisions as their response; the orchestrating skill (review/triage), not the subagent, owns writing the synthesized report file (plugins/forge/skills/review/SKILL.md:46-49; plugins/forge/skills/triage/SKILL.md:36-38). `validator` is the sole exception, legitimately read_only:false, writing tests and VALIDATE-REPORT.md itself (plugins/forge/skills/validate/SKILL.md:32-34).
- decompose's auto-created parent story (plan-mapping.json's `project_story`) can never reach `done` through the normal execution loop — storyhook refuses to hand a story with children back to `story next` — so execute's Complete check explicitly excludes it from "all stories done" (plugins/forge/skills/decompose/SKILL.md:107-114; plugins/forge/skills/execute/SKILL.md:183-185).

## External deps


## Gotchas

- `story decompose` treats every Markdown heading in its input as a story, not just wave headings — piping the whole PLAN.md would turn `## Test Strategy`/`## Risk Register` into spurious stories, so decompose extracts only the `## Task Breakdown` section first (plugins/forge/skills/decompose/SKILL.md:68-77).
- The custom states/type decompose needs (`verifying`, `blocked`, the `escalate` story type) aren't idempotent to register — re-running errors with exit 2 on an already-registered slug, and that specific error must be tolerated rather than treated as failure (plugins/forge/skills/decompose/SKILL.md:42-64).
- The router's `dispatch` value for a fix-loop re-entry into plan (`"plan --orchestrated"`) is byte-for-byte identical to a genuine first-time transition from design to plan; only checking `state == "fix_loop"` first (never `dispatch` alone) avoids silently skipping the mandatory fix-cycle-counter archive call (plugins/forge/skills/forge/SKILL.md:103-113).
- Deploy is the pipeline's only terminal step exit: its orchestrated exit passes `--terminal` to cancel any pending freshen signal instead of queuing a next command, since there is no next step (plugins/forge/skills/deploy/SKILL.md:96-102).
