# Council delivery and liveness contract

Both host implementations must use `bin/council-state.py`; never maintain parallel
deadline or retry arithmetic in the chair's reasoning. Read this file completely before
dispatch. The phase templates in `council-protocol.md` describe the **payload inside**
the envelope below, not an alternative wire format.

## Command boundary

Resolve `<plugin-root>` from the loaded host skill, and `<council-dir>` to the absolute
`.council/<slug>/` directory. Invoke:

```bash
python3 "<plugin-root>/bin/council-state.py" <command> "<council-dir>"
```

Supply one JSON object on stdin using a literal heredoc or a file; never interpolate
agent text into shell code. Every command returns `ok`, `state`, `actions`, `notices`,
and `display`. Errors return `ok:false`, exit nonzero, and name the command and directory.
Preserve diagnostics, inspect `status`, and stop transport after an error. A failed
artifact write may follow a successful state write: never blindly repeat a command.

`status` is read-only and needs no stdin. Every other command except `init` requires
`revision` from the most recent output. A revision conflict requires a fresh `status`
and reconciliation; it never permits an unconditional overwrite. Only the chair calls
this helper. Members cannot write state or phase artifacts.

| Command | Additional JSON fields | Meaning |
|---|---|---|
| `init` | `question`, `chair` (native session ID), `host` (`claude`/`codex`), `archetypes` (three distinct strings) | Persist a unique sitting before dispatch |
| `begin-phase` | `phase`: `research`, `vote`, `deliberation`, or `runoff` | Persist the whole panel's intents and deadlines |
| `record` | `seat`, `attempt_id`, `kind`, event fields below | Record observed transport facts |
| `advance` | none | Apply deadlines before/after transport and between bounded waits |
| `recover` | `chair`, `reachable` (exact observed native agent IDs) | Reconcile interrupted work without fresh time |
| `finish` | `outcome:"abort"`, `reason`; or `outcome:"decision"`, `markdown` | Persist terminal state, then render ABORT.md or DECISION.md |

Record events:

| `kind` | Event fields | Chair action |
|---|---|---|
| `dispatch-attempted` | none | Persist immediately before issuing native dispatch |
| `probe-attempted` | none | Persist before the one native probe; recovery will not resend it |
| `dispatched` | `agent_id` | Record the identity actually returned, immediately after dispatch |
| `delivery` | `sender`, `body` (string) | Pass the actual message and transport sender without rewriting |
| `failure` | `reason` | Report native dispatch failure, permission denial, unavailable tools, or wrong-question content |
| `liveness` | `agent_id`, `working` (boolean), `evidence` | Record the current attempt's observed status; unknown is false |
| `stopped` | `agent_id` (previous ID), `stopped` (boolean) | Confirm the old run ended before dispatching its replacement attempt |
| `cleanup` | `remaining` (list of agent IDs; no seat/attempt fields) | After terminal outcome, record agents cleanup could not stop |

Never resend an action merely because it reappears in output. `dispatch-attempted`
removes the dispatch action. A crash before `dispatched` leaves an uncertain send that
must be reconciled through `recover`, not replayed. Record `probe-attempted` before sending each probe once per attempt;
consume delivery events once. Retired attempts and duplicates cannot alter results.

## Bounded collection for every phase

| Phase | Initial | Working extension, once | Retry, once | Hard ceiling |
|---|---:|---:|---:|---:|
| Research | 900 s | 300 s | 300 s | 1500 s |
| Vote | 120 s | 60 s | 120 s | 300 s |
| Deliberation | 120 s | 60 s | 120 s | 300 s |
| Runoff | 120 s | 60 s | 120 s | 300 s |

The phase starts **before** dispatch. All seats share its ceiling; all retries are
parallel. There are at most 2400 seconds of response waiting across all four phases.
Known ten-minute measurement failures justify the 15-minute initial research budget;
five more minutes permit a productive battery to finish. Retry time is for salvaging
existing evidence or delivering a result, not restarting a full battery. These defaults
are operational limits, not measured percentiles.

1. Preflight nonblocking native dispatch, result collection, clock access, interruption,
   and three member slots. If unavailable, `finish` with an actionable abort before
   spawning; do not simulate votes. Do not weaken permissions to gain capability.
2. `begin-phase`; snapshot existing repository changes. For each participant, record
   intent, dispatch, and record its returned identity. Start every initial member before
   collecting any research response. Bookkeeping calls between dispatches do not expose
   other proposals. Use the native parallel form when available.
3. Call `advance` before and after transport. Follow actions, and collect in slices of
   **at most 30 seconds**, shortened to `wait_seconds`. If a native wait's minimum exceeds
   the remaining time, use a shorter available clock wait; never round past the deadline.
   No native call may synchronously hold the chair for a whole seat task. If that cannot
   be guaranteed on this host, abort rather than enter an unbounded call.
4. At the initial deadline, `probe` means inspect the **exact returned ID**, then send
   one request for delivery or current-attempt progress. `ListAgents`/`list_agents` may
   supply evidence; presence alone is not proof of progress. The probe has at most 30
   seconds **inside** the extension budget. Positive current-attempt evidence earns the
   remainder of that extension. Idle, dead, denied, missing, or unknown earns none.
5. The same failure path handles silence, bad JSON, dispatch errors, blocked tools, and
   lost messages: exactly one retry, then abstention. Follow `stop` before `dispatch`;
   confirm the old run has ended, reuse its agent ID if resumable, otherwise replace it
   with the same role and phase context. Never reuse a requested name in place of the
   returned ID. A retry gets a new attempt token and private scratch directory.
6. A retry repeats the original task and relevant prior evidence plus the precise failure
   reason and new envelope identity. Research remains blind. Later-phase replacements
   receive the same slate and phase evidence as the original member. Neither retry nor
   progress updates can reset the phase ceiling.
7. Wait for `phase-complete`, not "three messages". Write that phase's existing Markdown
   artifacts from accepted state. Two abstentions in any phase immediately produce
   `ABORT.md`; no further ballots or invented decision. One follows the shared protocol's
   existing reduced-slate, stand, or reduced-voter rules.

At each retry, extension, abstention, abort, or recovery, surface `display` and the
relevant `notices` to the user: phase, seats, elapsed seconds, reason, and audit path.
Persisting `LIVENESS.md` alone is insufficient. Keep normal progress visible during long
waits. Include degraded participation in the final decision's rationale/dissent.

After a terminal artifact is durable, interrupt only owned agents still running. Cleanup
has **30 seconds total**, never delays or invalidates the outcome, and never waits for
an unbounded shutdown acknowledgement. Record remaining IDs with `record kind:cleanup`.
Do not delete another sitting's artifacts or scratch work.

## Member envelope and isolation

Copy the exact identity values from state into every member prompt:

```json
{
  "council_id": "<state.council_id>",
  "question_digest": "<state.question_digest>",
  "phase": "<state.phase>",
  "seat": 1,
  "attempt_id": "<seat.attempt_id>",
  "kind": "result",
  "payload": {"summary":"...","rationale":"...","risks":"...","confidence":"high"}
}
```

For inability to complete, use the same identity with `kind:"failure"` and a nonempty
`reason`, omitting `payload`. Never ask the user a question or wait for a permission
answer. Report denied/unavailable tools immediately without bypassing the restriction.
Do not spawn further agents or convene a sub-council, even if the runtime allows it.

Use only the assigned `scratch` directory for measurement artifacts or disposable
copies. Do not modify repository files, chair artifacts, shared scratch, or other seats'
directories. The chair creates each private path. Long measurements must use short
collection calls or targeted batches; no ten-minute synchronous tool call. These are
instructions plus the existing host checks, not a claim of structural sandbox enforcement
(AGE-77 remains separate).

The helper accepts bare JSON or exactly one JSON fence on **both** hosts, rejects invalid
field types, and validates sender plus council/question/phase/seat/attempt before tally
eligibility. The chair also reads the substantive answer for the actual question; a
copied digest cannot prove semantic relevance. Wrong-question answers are failures.

Use `state.proposals` as the slate. With two proposals, omit C and the `third` ranking
field from prompts and examples. A research abstainer may vote later but has no proposal
to revise, so deliberation dispatches only proposal authors. A deliberation abstainer's
proposal stands unchanged, and the seat may vote in runoff.

## Resume before convening anew

On entry or resumption inspect `.council/*/STATE.json` for unfinished sittings relevant
to the task. Never infer "not dispatched" merely from missing proposals or DECISION.md.
`ready` means no phase intent; `prepared` means intent without a recorded native attempt;
`dispatch-attempted` is uncertain; `pending` names a confirmed native agent.

Run `status`, inspect reachable native IDs, then `recover`. The same chair with confirmed
identities keeps accepted responses and original deadlines. A new chair session, an
uncertain send, a lost pending agent, or a clock discontinuity aborts the old sitting as
interrupted. Preserve the record; a separately authorized fresh council uses a new slug
and ID. Do not automatically loop through fresh sittings after abort.

Monotonic elapsed time governs active waits. UTC deadlines remain in state for inspection;
backward time or more than five seconds of wall/monotonic disagreement aborts rather
than granting time after suspend/reboot/clock adjustment. `recover` regenerates terminal
artifacts after a crash between state persistence and Markdown rendering.

For pre-helper directories without STATE.json, report legacy interrupted/unknown state;
preserve them and never claim they were not dispatched. No process emits notices while
the host is dead. This protocol bounds an operating chair and makes resumed work legible.

## Sources and compatibility

- [Python time](https://docs.python.org/3/library/time.html): monotonic elapsed-time clocks.
- [Python os](https://docs.python.org/3/library/os.html): atomic replacement and fsync.
- [Claude subagents](https://code.claude.com/docs/en/sub-agents): background execution,
  returned IDs, and version-dependent message routing.
- [Claude messaging](https://code.claude.com/docs/en/cross-session-messaging): tool
  availability and delivery failures vary by host configuration. Use exposed tools;
  do not edit runtime inboxes or enable experimental features to make this protocol work.
