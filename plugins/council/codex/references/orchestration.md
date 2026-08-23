# Codex Council Orchestration

This file replaces only the Claude-specific dispatch mechanics in the shared council protocol.
The shared phase order, prompts, JSON schemas, voting rules, artifacts, and failure policy remain
authoritative.

## Create the panel

For each of the three chosen archetypes, resolve and read its full canonical definition from the
Agents plugin. Derive unique task names as `council_<slug>_seat_1` through `_seat_3`, replacing
hyphens in the slug with underscores.

Start all three members with native `spawn_agent` calls before calling `wait_agent` for any member.
Use no model or reasoning-effort override; each member inherits the active Codex settings. Do not
use an `agents:<name>` namespace on Codex.

Each initial prompt has this order:

1. The full canonical role definition.
2. The execution contract below.
3. The phase-2 member prompt from the shared protocol, including the verbatim question and context.

```markdown
## Codex council-member contract

The preceding canonical definition is your specialist perspective. Its YAML tool, model, and
effort fields are Claude registration metadata, not Codex configuration. Use only tools available
in this spawned session. You are strictly read-only: do not create, edit, delete, move, stage, or
commit files. Do not spawn further agents. Return only the JSON object requested by the phase
prompt, with no markdown fence or surrounding prose.
```

Round 1 remains blind: do not include panel composition, other task names, or other members' work
in any initial prompt.

## Preserve parallelism and identity

Start all three `spawn_agent` calls back-to-back. If any spawn fails, use `interrupt_agent` on every
member already started, write `ABORT.md` with the failure, and stop. Only after all three starts
succeed may the chair call `wait_agent` until all three final responses are available.

Keep the returned member identifiers for the full council. For voting, deliberation, and runoff,
send one `followup_task` to every participating member before waiting for any response. This keeps
the three perspectives stable while each phase still runs in parallel. A seat that abstained keeps
its identity but receives no further phase task when the shared failure policy excludes it.

## Validate responses and retry once

Parse each response against the phase-specific JSON schema in the shared protocol. Reject markdown
fences, surrounding prose, missing or empty fields, invalid enum values, duplicate ranking choices,
and a deliberation seat number that does not match the member.

A malformed response gets exactly one retry through `followup_task` to that same member. The retry
prompt names the validation error, repeats the required schema, and contains no new substantive
guidance. If the retry is also malformed, record an abstention. Two abstentions in one phase require
`ABORT.md` and no decision.

## Enforce the read-only boundary

After the chair writes the phase's own artifacts and immediately before dispatch, record the
worktree status. Compare it again after every member in that phase has returned. If files changed
outside the chair's expected `.council/<slug>/` writes, do not use the affected member result:
interrupt any still-running members, record the changed paths in `ABORT.md`, and stop. Prompt-only
read-only enforcement must never be presented as a structural tool restriction.

## Finish cleanly

After the decision or abort artifact is durable, use `interrupt_agent` only for members that are
still running. Finished members need no cleanup. Return the shared Phase 6 response shape for a
decision; for an abort, return the reason and `ABORT.md` path without inventing a winner.
