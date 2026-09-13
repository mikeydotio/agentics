# AGE-81: Council liveness and interrupted-sitting recovery

Council is an autonomous decision dependency: a silent seat previously left the chair
waiting indefinitely. The malformed-response handler had one retry and abstention, but
could not classify a response that never arrived. All four dispatch phases were exposed.

## Evidence and scope

The story's discussion, PROGRESS.md's AGE-69/70 records, and CLAUDE.md's measurement
lessons establish the observed mechanisms below. Original `.council` transcripts are
not present in this worktree; historical observations are attributed, not re-measured.
AGE-89 introduced Codex native IDs but retained the unbounded wait. Reviewed obviation
candidates: AGE-45/50/62/83/85/87/88/89/90/91/92/93/95/96/101/102/103; none replaces this work.

AGE-105 measured a separate compatibility defect in this state machine. On macOS,
`/usr/bin/python3` 3.9.6 gave `time.monotonic()` a process-relative origin: an `init`
followed six seconds later by `advance` in a new interpreter falsely aborted an otherwise
idle sitting. Python 3.14 preserved it. AGE-52/54 affect Greenlight, and AGE-104 explicitly
excluded Council; none of AGE-105's obviation candidates repaired this boundary.

| Mode | Evidence class | Mechanism | Resolution |
|---|---|---|---|
| Plain final text invisible | Observed, AGE-81 | Notification without usable delivery | Explicit host delivery + deadline |
| False synchronous assumption | Observed, AGE-81 | Detached seat despite false background flag | Nonblocking dispatch + bounded collection |
| Stale seat name | Observed, AGE-69 | Reused requested name addresses old seat | Random names, returned IDs, envelope identity |
| Bare JSON message rejected | Observed, AGE-43 | Tool expects string message body | Claude fenced JSON string |
| Ten-minute tool death | Observed, AGE-69/70 | Synchronous measurement exceeds tool lifetime | Short collection calls, targeted batches, bounded retry |
| Host kernel panic | Observed, AGE-70 | Chair disappears between dispatch and result | Persist dispatch state, recover or abort |
| Shared scratch overwrite | Observed, AGE-35/43 | Seats and chair reuse path | Private attempt scratch directories |
| Archetype lacks execution tool | Observed, AGE-70 | Challenger cannot perform measurement | Capability preflight and immediate failure |
| User question / permission wait | Reachable | Seat waits for unavailable human | Report failure; never bypass permission |
| Recursive fan-out | Reachable | Nested council grows work indefinitely | Explicit no-spawn contract + phase ceiling |
| Partial dispatch | Reachable | Some starts succeed, another fails | Record each intent and returned ID; one retry |
| Provider failure / exhausted context | Reachable | Agent dies or cannot finish | Same failure policy |
| Idle without response | Reachable | Runtime status mistaken for delivery | Probe; idle never counts as result |
| Duplicate / delayed / wrong-phase output | Reachable | Reordered messages counted in new phase | Sender + council/question/phase/seat/attempt checks |
| Probe/message rejection | Reachable | Tool unavailable, throttled, or denied | Unknown liveness earns no extension |
| Chair crash at persistence boundary | Reachable | Intent or terminal result only partly rendered | Revisioned atomic state; idempotent rendering |
| Corrupt state / concurrent writers | Reachable | Invalid structure or lost update | Validation + nonblocking lock + revision |
| Clock discontinuity | Reachable | Reboot/suspend/adjustment grants fresh budget | Original clock-pair check; interrupted abort |
| Cleanup refusal | Reachable | Shutdown acknowledgement never arrives | Independent 30-second cleanup ceiling |

Forge, RCA, and general Agents fan-out remain separate sibling work. AGE-77 read-only
enforcement remains separate. No change to panel size, voting thresholds, or IRV.

## Implementation boundary

`plugins/council/references/liveness.md` is the installed chair contract and CLI reference.
Both host skills load it before dispatch. Python standard-library modules separate policy,
validation, and persistence. Native agent tools remain host-owned; the CLI does no network
I/O, agent spawning, voting simulation, or sleeping.

Commands: init, begin-phase, record, advance, status, recover, finish. JSON stdin supplies
events and expected revision; stdout supplies state, actions, notices, and display. Errors
are nonzero and contextual. STATUS is read-only; all mutations use a nonblocking file lock
and atomic fsynced replacement. The chair must show notices, not only write Markdown.

| Transition | Durable fact |
|---|---|
| init → ready | Unique sitting and exact question, no phase dispatch |
| begin-phase → prepared | Whole panel intent and absolute deadline |
| dispatch-attempted | Native call may have occurred; recovery must reconcile |
| dispatched → pending | Actual returned agent identity |
| deadline → probing | One 30-second window within extension budget |
| probe-attempted | Probe intent persisted before send; not replayed on recovery |
| working evidence → pending | One fixed extension, never a refreshed timer |
| failure → stopping/prepared | One replacement attempt, original role/context |
| retry failure → abstained | Same terminal seat outcome for silence and malformed data |
| all resolved → phase-complete | Accepted responses archived; surviving slate available |
| two abstentions → aborted | No winner; terminal state precedes ABORT.md |
| finish decision → decided | Completed vote/runoff, chair-supplied decision Markdown |

Research budgets: 900 seconds initial + 300 extension + 300 retry = 1500 ceiling.
Later phases: 120 + 60 + 120 = 300 each. Four response phases consume at most 2400
seconds. The observed ten-minute failures justify a longer research budget, not an
unbounded measurement; these are defensible operating defaults, not latency percentiles.
Each wait is at most 30 seconds and never exceeds the current deadline. Cleanup has a
separate 30 seconds and cannot delay durable completion.

Active time uses `clock_gettime(CLOCK_MONOTONIC)`, whose system-wide epoch survives
separate helper processes on the supported macOS Python 3.9 runtime, translated to the
original UTC clock pair. Both samples must be finite and available before artifacts are
created. Backward clocks or cumulative disagreement above five seconds abort; the
tolerance is unchanged. Recovery never grants fresh time.

The persisted `clock_mono` sample becomes the anchor after a terminal transition, when
active deadline arithmetic is finished. Terminal status and commands advance the cleanup
window from that sample, independent of wall-clock changes. A negative monotonic delta
expires cleanup immediately, so reboot or an incompatible old process epoch cannot renew
the 30-second obligation. This retains schema version 1 and its existing state fields.
Changed chair identity, missing pending native IDs, and uncertain dispatch abort the
interrupted sitting. Old artifacts remain; legacy directories without STATE.json are
explicitly unknown, not proof of no dispatch.

The helper preserves the existing full-panel seat-order labels and two-proposal
arrival-order labels. Research abstainers can vote later but cannot revise a nonexistent
proposal. Deliberation abstention preserves the previous proposal. A timed-out run must
be stopped before receiving a new phase task. The chair still performs existing IRV and
semantic relevance review; a digest alone cannot prove an answer addresses the question.

## Verification

Production command tests use private `/tmp` directories and injected clock/agent events.
They exercise baseline successful dispatch, failures in every phase, exact deadlines,
identity rejection, malformed types, concurrent lock refusal, stale revisions, scratch
isolation, recovery, and terminal-render failure. CLI tests execute both host settings.
Instruction contracts require every dispatch phase and both host skills to use the helper.

The mutation battery first runs a successful production baseline. Each mutation must
apply exactly once and trigger its named assertion, not a missing-file/import/setup error.
It removes timeout, retry limit, identity checks, two-abstention abort, terminal-state
persistence, finite terminal deadline validation, the cross-process clock, the exact drift
threshold, and negative-delta cleanup handling in disposable copies. A historical-protocol
baseline confirms the original voting artifacts exist while the new integration assertions
reject its missing bounds. A real six-second, separate-interpreter CLI regression runs on
Python 3.9 and the current default interpreter; it spawns no Council worker.

Only Council and directly impacted guards run locally. Central verification owns the
full suite and publication. No live-model end-to-end guarantee is claimed: policy and
persistence are executable; host instruction compliance and semantic answer quality
remain chair responsibilities. No process can emit a notice while the host is dead.

Research: [Python clocks](https://docs.python.org/3/library/time.html),
[Python persistence](https://docs.python.org/3/library/os.html),
[Claude subagents](https://code.claude.com/docs/en/sub-agents), and
[Claude messaging](https://code.claude.com/docs/en/cross-session-messaging).
