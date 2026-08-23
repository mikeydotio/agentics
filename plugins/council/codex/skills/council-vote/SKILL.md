---
name: council-vote
description: Use when the user delegates a consequential decision with multiple defensible options and wants a three-specialist council to decide.
---

# Council Vote for Codex

You are the council chair. Convene an expertise-matched panel, run the bounded
propose → vote → deliberate → rank protocol, persist its audit trail, and return the decision.
The chair does not vote.

## Resolve the installed plugins

Resolve `<plugin-root>` as three directories above the directory containing this installed file.
Substitute that absolute path in every bundled read or command. Do not assume the current working
directory is the agentics source checkout.

Council depends on the separately installed Agents plugin. Run:

```bash
bash <plugin-root>/bin/resolve-agents-root.sh
```

Treat its single output line as `<agents-root>`. Stop with its error if resolution fails. Read
`<agents-root>/references/agent-catalog.md` before picking a panel. For every chosen archetype, run
`bash <agents-root>/bin/resolve-agent.sh <name>` and read the returned file completely. Put that
full canonical role at the start of the member prompt; the role's Claude `tools`, `model`, and
`effort` fields are metadata on Codex, not literal tool names or model overrides.

## Load only what the phase needs

- Read `<plugin-root>/references/team-composition.md` when choosing the panel.
- Read `<plugin-root>/references/council-protocol.md` for prompt templates, response schemas,
  artifact formats, voting phases, and response-failure policy. Its `Agent` dispatch descriptions
  document the unchanged Claude path; replace only those dispatch mechanics with the authoritative
  Codex adapter below.
- Read `<plugin-root>/codex/references/orchestration.md` before the first dispatch and follow it for
  native tools, parallelism, role injection, retries, cleanup, and read-only enforcement.
- Read `<plugin-root>/references/voting-mechanics.md` only if round 1 is not unanimous.

## Invariants

1. The panel has exactly three distinct archetypes: a domain specialist, an architectural
   generalist, and a challenger selected for the likely failure mode.
2. Round-1 research is blind. Start all members before collecting any response.
3. A non-unanimous first vote gets exactly one deliberation round and then ranked-choice IRV.
4. Every member is read-only even when its canonical Claude metadata includes write tools.
5. Persist the phase artifacts before advancing. Never overwrite an earlier council directory.
6. Malformed member output gets one retry, then that seat abstains. Two abstentions in one phase
   write `ABORT.md` and end without a decision.
7. If the native collaboration tools or three concurrent member slots are unavailable, write
   `ABORT.md`; never simulate a council through sequential self-reasoning.

## Invocation and return

Invocation is `$council:council-vote <question> [-- <context summary>]`. If context is omitted,
assemble it from the conversation and relevant working-tree evidence before convening. Decline
facts, cheap reversible choices, and decisions the user did not delegate.

Use the exact Phase 6 return template from the shared protocol. State that the panel ran through
Codex native subagent orchestration and include the `DECISION.md` path.
