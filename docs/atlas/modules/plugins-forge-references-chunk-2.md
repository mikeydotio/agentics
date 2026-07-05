---
module: "plugins/forge/references (chunk 2)"
summary: "Forge-specific agent naming/spawning mechanics and the evaluator's debiasing verdict checklist."
read_when: "Resolving agent spawn names/overrides, or editing evaluator verdict criteria"
sources:
  - path: plugins/forge/references/team-roles.md
    blob: 7d116f0479468ceb2f5b81ed29600b11b3742786
  - path: plugins/forge/references/verification-protocol.md
    blob: 17a0ab62b995d8db089d561a635042a5e6f24c21
generator: cartographer/4
baseline: 50c998d53e2ed58951ac5f794afd32bfa729f658
---

# Module: plugins/forge/references (chunk 2)

## Purpose

This chunk of forge's references documents the mechanics of the pipeline's agent layer: team-roles.md resolves which literal agent file to spawn for roles that are easy to misname, which project type activates which conditional agents, and how subagent_type resolution/overrides actually work; verification-protocol.md defines the evaluator's debiasing checklist that keeps a generosity-biased LLM reviewer honest. Both docs exist to keep every forge step's spawn calls and verdict checks consistent with the single canonical definitions that live in the agents plugin (agent-catalog.md, evaluator.md) rather than re-deriving or drifting from them. Losing this module would leave step skills to guess agent filenames and verdict semantics ad hoc, reintroducing the misnaming and schema-drift problems these docs were written to close (plugins/forge/references/team-roles.md:1-8, plugins/forge/references/verification-protocol.md:57-58).

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

agent-catalog.md (in the agents plugin) is the single source for agent roster, tools, and descriptions; team-roles.md deliberately covers only forge-specific naming and spawning mechanics and defers roster ownership to it (plugins/forge/references/team-roles.md:3-8). evaluator.md owns the verdict JSON schema exactly once; verification-protocol.md's checklist only maps unmet checks into that schema's criteria_checks/failures fields and is explicitly declared stale if it ever disagrees with evaluator.md (plugins/forge/references/verification-protocol.md:49-58). The full verdict object is logged to .forge/verdicts.jsonl while only its compact projection is round-tripped as a storyhook comment on retries (plugins/forge/references/verification-protocol.md:70-72).

## External deps


## Gotchas

Three agent names get chronically confused with nonexistent files — `senior-engineer`, `devils-advocate`, and bare `ux-designer` — enumerated as a correction table because none resolves to a real filename in plugins/agents/agents/ (plugins/forge/references/team-roles.md:15-19). Spawning must never use a bare `forge:` namespace — only `agents:<name>` or `general-purpose` is valid since forge registers no agents of its own (plugins/forge/references/team-roles.md:79-81). On evaluator retry, only the compact structured verdict (verdict/failures) is passed back to the generator — never raw freeform text — specifically to block prompt injection via the evaluator-to-generator feedback path (plugins/forge/references/verification-protocol.md:70-73).
