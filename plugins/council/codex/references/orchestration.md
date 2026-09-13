# Codex Council Orchestration

This file replaces only the Claude-specific dispatch mechanics in the shared council protocol.
The shared phase order, prompts, payload schemas, voting rules, artifacts, and shared liveness policy remain
authoritative.

## Create the panel

For each of the three chosen archetypes, resolve and read its full canonical definition from the
Agents plugin. Read `references/liveness.md` and call `bin/council-state.py` for
`init` and `begin-phase`. Use its random council/attempt names and retain the returned
native IDs. A slug alone is not globally unique. Inspect unfinished state on entry and
run `recover` before creating another sitting.

Start all three members with native `spawn_agent` calls before calling `wait_agent` for any member.
Use no model or reasoning-effort override; each member inherits the active Codex settings. Do not
use an `agents:<name>` namespace on Codex.

Each initial prompt has this order:

1. The full canonical role definition.
2. The execution contract below.
3. The helper identity envelope, chair identity, private scratch path, and deadline.
4. The phase-2 member prompt from the shared protocol, including the verbatim question and context.

```markdown
## Codex council-member contract

The preceding canonical definition is your specialist perspective. Its YAML tool, model, and
effort fields are Claude registration metadata, not Codex configuration. Use only tools available
in this spawned session. Do not modify repository files or chair artifacts. Measurement
artifacts and disposable copies belong only in your assigned private scratch directory.
Do not spawn further agents. Do not wait for user input or permission approval: report a
failure with its reason, without bypassing restrictions. Long measurements use short
collection calls or targeted batches. Return the requested identity envelope with the phase
payload as your final response; bare JSON or one JSON fence is valid, without surrounding prose.
```

Round 1 remains blind: do not include panel composition, other task names, or other members' work
in any initial prompt.

## Preserve parallelism and identity

Start all three members before collecting any research response. Persist `dispatch-attempted`
before each native call and `dispatched` with its returned ID immediately after. A failed spawn
is a helper `failure` for that seat, consuming the same one retry; preflight inability to create
three concurrent members is an immediate `finish outcome:abort`. Never fake missing seats.

Keep the returned member identifiers for the full council. For voting, deliberation, and runoff,
send one `followup_task` to every participating member before collecting responses. Use
`state.participants`: a research abstainer may vote later but has no proposal to revise.
Never reuse an old attempt token or assume a requested task name identifies its current owner.

## Validate delivery and bound every wait

Use the shared helper loop for research, vote, deliberation, and runoff. Call `advance` before
and after transport; `wait_agent` is only a mailbox wakeup, not proof of completed output.
Read actual delivered messages and their senders. Pass final envelopes to `record kind:delivery`.
Reject a substantively unrelated answer even if it copied the right digest; record a failure.

Use `wait_agent` with at most 30000 milliseconds, shortened to `actions[].wait_seconds`.
If less than the tool's minimum remains, use an available shorter clock wait instead.
Never use an unbounded native call. Return visible progress while collecting.

At `probe`, use `list_agents` for the exact returned member ID and, where needed,
`send_message` for one current-attempt progress/delivery probe. Only affirmative working
status tied to this attempt earns one extension. Report unknown status as `working:false`.
Neither an idle notification nor an ID's presence is a completed result.

Missing, malformed, blocked, or failed responses get **exactly one retry**, enforced by the
helper. Follow `stop` using `interrupt_agent` and record `stopped` before `followup_task`
or a replacement `spawn_agent`. Reuse the same role and original phase context; inject the new
attempt envelope. Retry time includes interruption and dispatch; it never extends the ceiling.
Two abstentions in one phase require `ABORT.md` and no decision. Render phase artifacts only
at `phase-complete`, and preserve the helper's PANEL.md abstentions.

## Enforce the read-only boundary

After the chair writes the phase's own artifacts and immediately before dispatch, record the
worktree status. Compare it again after every participating member is accepted or abstained. If files changed
outside the chair's expected `.council/<slug>/` writes, do not use the affected member result:
interrupt any still-running members, record the changed paths in `ABORT.md`, and stop. Prompt-only
read-only enforcement must never be presented as a structural tool restriction.

## Finish cleanly

Use helper `finish` for the decision or abort. After its artifact is durable, use
`interrupt_agent` only for owned members still running. Cleanup has 30 seconds total;
record remaining IDs with `record kind:cleanup` and return without waiting for acknowledgements. Return the shared Phase 6 response shape for a
decision; for an abort, return the reason and `ABORT.md` path without inventing a winner.
