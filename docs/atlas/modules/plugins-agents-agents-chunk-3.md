---
module: "plugins/agents/agents (chunk 3)"
summary: "Forge's triager (FIX/ESCALATE/DEFER triage) and validator (no-mock test hardening) agent definitions."
read_when: "Touching forge triage/validate steps or the triager/validator agent contracts"
sources:
  - path: plugins/agents/agents/triager.md
    blob: 4b91a0e95e560c1a4e48e6bee8d3ddd3ad2561d7
  - path: plugins/agents/agents/validator.md
    blob: e85b72f785ded4cdb4b1965161c2dd2abad5047f
generator: cartographer/4
baseline: 50c998d53e2ed58951ac5f794afd32bfa729f658
---

# Module: plugins/agents/agents (chunk 3)

## Purpose

This module defines forge's two decision-quality gate agents: triager (plugins/agents/agents/triager.md) turns reviewer and validator findings into calibrated FIX, ESCALATE, or DEFER verdicts through severity re-calibration, scope checking, systemic-impact assessment, and mandatory security elevation; validator (plugins/agents/agents/validator.md) hardens the test suite itself, enforcing a no-mock policy, an 11-category edge-case taxonomy, and requirement-to-test coverage mapping. Together they form forge's final quality gate before deploy — validator raises the bar the implementation must clear, and triager decides which remaining gaps the pipeline may auto-fix versus which need a human decision. Without them, forge's fix loop would have no systematic way to separate a trivial auto-fixable finding from one needing human judgment, and no mechanism for closing test-coverage or no-mock gaps beyond ad hoc test writing.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

triager is read-only (plugins/agents/agents/triager.md:8) with tools limited to Read, Grep, Glob (plugins/agents/agents/triager.md:4) and explicitly no Write/Edit access (plugins/agents/agents/triager.md:195) — TRIAGE.md is persisted by the orchestrator from its returned verdict, not by the agent. validator is read-write (plugins/agents/agents/validator.md:8) with Write, Edit, and Bash access (plugins/agents/agents/validator.md:4) and both writes tests and edits its own report directly. Both carry tier: pipeline-specific, pipeline: forge (plugins/agents/agents/triager.md:6-7, plugins/agents/agents/validator.md:6-7), i.e. each is spawned once per pipeline run at forge's respective triage and validate steps, not general-purpose. triager's decision framework is config-driven rather than a static rule table: it branches on `.forge/config.json`'s when_in_doubt and yolo_mode fields (plugins/agents/agents/triager.md:31, plugins/agents/agents/triager.md:96-100), so the same finding can route to FIX or ESCALATE differently across runs depending on pipeline configuration. validator's write scope is bounded by an explicit invariant: never delete existing tests unless truly worthless — assertion-free or testing deleted code (plugins/agents/agents/validator.md:216) — and never fix implementation bugs, only report them as findings (plugins/agents/agents/validator.md:203).

## External deps


## Gotchas

triager's Mission says it must "Produce a TRIAGE.md" (plugins/agents/agents/triager.md:23), but its Guardrails state "You have NO Write or Edit tools" (plugins/agents/agents/triager.md:195) — it never writes the file itself; the orchestrator persists TRIAGE.md from the agent's returned decision. validator's "No test skipping" guardrail (plugins/agents/agents/validator.md:205) coexists with an explicit env-var skip mechanism for its own new tests (plugins/agents/agents/validator.md:147-149) — the ban targets skipping existing tests to force a pass, not gating new tests on missing credentials.
