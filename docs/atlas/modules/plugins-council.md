---
module: plugins/council
summary: "3-member sub-agent voting council that settles delegated judgment calls with a full audit trail"
read_when: "Touching /council-vote, the council protocol, voting/IRV mechanics, or panel selection"
sources:
  - path: plugins/council/.claude-plugin/plugin.json
    blob: 95156c7eb1d88d3ec7cc6797b29c0dfc89913576
  - path: plugins/council/README.md
    blob: 6fc77ba8523cf7262b3d0a8f9f79586464cefc62
  - path: plugins/council/references/archetypes.md
    blob: c44c68234b14a4ac1f63ad6212ba15acf1677685
  - path: plugins/council/references/council-protocol.md
    blob: c0f8ed74139972454cb6d45d4b50ba47417c8cbb
  - path: plugins/council/references/team-composition.md
    blob: 52fd8798ee8ab7dd5549e5104351d21fffa5b70e
  - path: plugins/council/references/voting-mechanics.md
    blob: d3542bdd4650b494776d0c000dd42833523a8255
  - path: plugins/council/skills/council-vote/SKILL.md
    blob: 43a7b337af2839fd895be747bc53d4b770be55e9
  - path: plugins/council/skills/council-vote/evals/evals.json
    blob: 1023d8902ccef3f0bbefb50eedbb9e92debe984d
references_modules: [plugins-agents-agents-chunk-1, plugins-agents-agents-chunk-2, plugins-agents-agents-ux, plugins-agents-references]
generator: cartographer/1
baseline: b9203a6997fdbc2248086c1aa9ee6f62b1e025b6
verified: true
---

# Module: plugins/council

## Purpose

Settles delegated judgment calls so a mid-task agent need not guess silently or block on the user.
The chair seats 3 shared archetypes: blind proposals, a vote, one deliberation round, IRV runoff.
Every phase has a bounded exit; decisions persist to `.council/<slug>/` for later user override.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `council` | plugin manifest | `plugins/council/.claude-plugin/plugin.json:2` | Marketplace identity; declares the propose → vote → deliberate → ranked-runoff pipeline |
| `council-vote` | skill | `plugins/council/skills/council-vote/SKILL.md:2` | Chair entry point, args `<question> [-- <context summary>]`; returns the fixed Phase-6 decision block plus the `.council/<slug>/DECISION.md` audit path |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `Council Protocol` | reference doc | `plugins/council/references/council-protocol.md:1` | Phase 0–6 runbook: every member prompt template, JSON reply shape, artifact format, and the exact caller-return template |
| `Member response failures` | protocol | `plugins/council/references/council-protocol.md:411` | Lenient parse → one retry → abstain; two abstentions in one phase write `ABORT.md` and error out, never inventing a decision |
| `Voting Mechanics` | reference doc | `plugins/council/references/voting-mechanics.md:1` | Round-1 plurality where only 3-0-0 ends early, then IRV with Borda-then-alphabetical elimination tiebreaks |
| `Chair tiebreaker` | heuristic | `plugins/council/references/voting-mechanics.md:97` | Last resort when IRV stalls: reversibility cost → aggregate confidence → smallest scope → alphabetical |
| `Team Composition` | reference doc | `plugins/council/references/team-composition.md:1` | Specialist + generalist + challenger seating rubric, worked example panels, council-stacking anti-patterns |
| `Archetypes` | reference doc | `plugins/council/references/archetypes.md:1` | Members are shared-library archetypes, optionally focused per council via injected domain nuance |
| `evals` | eval suite | `plugins/council/skills/council-vote/evals/evals.json:3` | Scenarios pin the unanimous short-circuit, forced deliberation + IRV, chair-tiebreak splits, and open questions |

## Relationships

- `plugins-council.council-vote -> plugins-agents-references.agent-catalog.md (reads)`
- `plugins-council.council-vote -> plugins-agents-agents-chunk-1.api-designer (calls)`
- `plugins-council.council-vote -> plugins-agents-agents-chunk-2.skeptic (calls)`
- `plugins-council.council-vote -> plugins-agents-agents-chunk-2.software-architect (calls)`
- `plugins-council.council-vote -> plugins-agents-agents-ux.ux-designer-mobile (calls)`

## Type notes

- Members reply in JSON only, one shape per phase: plugins/council/references/council-protocol.md:90
- A/B/C proposal labels are stable across rounds: plugins/council/references/voting-mechanics.md:34
- Members are read-only; they propose, never edit: plugins/council/references/archetypes.md:73
- The chair tabulates and tiebreaks but never votes: plugins/council/skills/council-vote/SKILL.md:36
- Dispatch fallback: general-purpose + pasted role: plugins/council/skills/council-vote/SKILL.md:118
- `.council/<slug>/` collisions get -2/-3 suffix: plugins/council/skills/council-vote/SKILL.md:83
- `.council/` is project-local and suggested for `.gitignore`: plugins/council/README.md:54

## External deps

- Claude Code `Agent` tool — sole member-dispatch mechanism; the council aborts without it
- No third-party packages — the plugin is pure markdown and JSON

## Gotchas

- Councils cannot nest — members are subagents: plugins/council/skills/council-vote/SKILL.md:58
- Never dispatch members with `run_in_background`: plugins/council/skills/council-vote/SKILL.md:29
- No Agent tool → ABORT.md, never a sequential fake: plugins/council/skills/council-vote/SKILL.md:53
- Round-1 members never learn who else is seated: plugins/council/skills/council-vote/SKILL.md:138
