---
module: plugins/atlas/agent-overrides
summary: "Atlas-specific constraint docs inlined into the shared cartographer, map-repairer, and map-verifier agent prompts."
read_when: "Changing atlas agent spawn constraints or repair/verify protocols"
sources:
  - path: plugins/atlas/agent-overrides/cartographer-context.md
    blob: fc4f2dac45212adc185ba26bb90a67669edd8244
  - path: plugins/atlas/agent-overrides/map-repairer-context.md
    blob: 36b934944b5b80ae623280af602c4f7bed9a241a
  - path: plugins/atlas/agent-overrides/map-verifier-context.md
    blob: 1c84c8d01c0082d460cd0676e51d252d3bea628e
generator: cartographer/4
baseline: 50c998d53e2ed58951ac5f794afd32bfa729f658
---

# Module: plugins/atlas/agent-overrides

## Purpose

This module holds the three atlas-specific override docs (plugins/atlas/agent-overrides/cartographer-context.md, map-repairer-context.md, map-verifier-context.md) that get inlined at spawn time into the shared cartographer, map-repairer, and map-verifier agent definitions, narrowing each generic role into atlas v2's judgment-cell contract — the annotator emits content-addressed cells instead of markdown (cartographer-context.md:6-9), the repairer edits exactly one existing doc within a lint-finding scope (map-repairer-context.md:8-16), and the verifier adversarially refutes a single cell rather than a whole doc (map-verifier-context.md:3-9). Without these docs the shared agents would default to full-doc authoring and whole-module re-reads, defeating atlas's incremental hash-gated pipeline that skips unchanged content.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

- map-repairer-context.md:8-11 — the repairer owns exactly one write target per invocation (the module doc or ARCHITECTURE.md named in its prompt); the orchestrator diffs the worktree afterward and discards any other modified file.
- map-repairer-context.md:18-23 — the repairer's frontmatter write access is a narrow whitelist (summary, read_when, references_modules); sources, blob, baseline, verified, and generator are orchestrator-owned and immutable to this agent.
- map-verifier-context.md:33-40 — a cell's fail lifecycle is bounded: a fail triggers exactly one re-judgment, and a second fail on an already-re-judged cell is terminal, shipping as verify.verdict: fail rather than looping.
- cartographer-context.md:76-79 — cells are keyed by the structure they describe so an unchanged symbol or edge reuses prior cell prose verbatim across builds; these three docs define that content-addressing contract for atlas's judgment-producing and judgment-consuming agents.

## External deps


## Gotchas

- map-verifier-context.md:28-29 — a "pass" verdict means the claim survived adversarial refutation, not that it was proven true; the default posture is fail for any citation the verifier cannot confirm.
- map-repairer-context.md:13-16 — the repairer is explicitly barred from re-reading the whole module to fix a finding (that's /atlas update's job), a narrower search scope than the shared cartographer/investigator norm of reading everything.
- cartographer-context.md:63-64 — an edge.semantic verb outside the allowed grammar isn't rejected; the projector silently falls back to rendering the plain (calls) edge.
