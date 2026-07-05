---
module: plugins/council
summary: "Runs a 3-member sub-agent council — propose, vote, deliberate, IRV runoff — to decide judgment calls without the user."
read_when: "Touching /council-vote, its protocol, voting/IRV mechanics, or panel rubric"
sources:
  - path: plugins/council/.claude-plugin/plugin.json
    blob: 003228fc3037ddb7171323261c1ccc67754b0a96
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
generator: cartographer/4
baseline: 50c998d53e2ed58951ac5f794afd32bfa729f658
---

# Module: plugins/council

## Purpose

The council plugin gives an agent a structured way to make an autonomous, defensible judgment call when the user is unavailable rather than guessing silently or blocking on AskUserQuestion (plugins/council/README.md:10-12). Its organizing idea is real deliberation at small scale: 3 archetypes drawn from the shared agent library propose independently, cast a single-choice vote, deliberate once if not unanimous, then run a ranked-choice (IRV) runoff with a chair tiebreaker used only when IRV cannot resolve (plugins/council/README.md:3-6; plugins/council/references/voting-mechanics.md:99-101). Without it, an orchestrating agent facing a genuine expertise tradeoff (interaction design, schema choices, dependency acceptance) has no bounded fallback short of interrupting the user or picking silently.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

The chair (the orchestrator skill) owns the entire .council/<slug>/ artifact directory end-to-end; it is created once, in Phase 0, and is never overwritten — a slug collision appends -2, -3, etc. until a free directory is found (plugins/council/references/council-protocol.md:13-14). Panel size is a hard invariant of exactly 3 seats, never resized up or down (plugins/council/skills/council-vote/SKILL.md:25-26). The chair never casts a ballot for the whole run — it only tabulates votes and applies a documented tiebreaker when IRV cannot resolve (plugins/council/references/voting-mechanics.md:4-6; plugins/council/skills/council-vote/SKILL.md:36-37). A member's abstention is a terminal per-phase state, not a retryable one: after one retry, a still-malformed response marks that seat abstaining for the rest of the phase (plugins/council/references/council-protocol.md:441-453), and two or more abstentions in a single phase terminates the whole council via ABORT.md instead of producing a decision (plugins/council/references/council-protocol.md:470-475).

## External deps


## Gotchas

Council members cannot spawn their own sub-councils: a member is itself a subagent, so the Agent tool it would need typically isn't available to it, and it must decline (write ABORT.md) rather than fake a council with sequential self-reasoning (plugins/council/skills/council-vote/SKILL.md:53-58). The chair must never dispatch members with run_in_background — it needs all 3 responses in hand before it can tally a vote or write a round's artifact, so backgrounding would silently break phase sequencing (plugins/council/skills/council-vote/SKILL.md:27-30).
