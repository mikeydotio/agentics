# Bounded specialist delivery

Read this entire contract before dispatching any specialist. The owner alone runs
its installed `bin/agent-delivery.py`; workers never write delivery state. Forge and
RCA bundle identical copies, so their existing role-resolution fallbacks still work.
No Council voting state or permission enforcement is added by this helper.

## Entry and command boundary

Resolve the helper from the loaded plugin's absolute installation path. Use a new
batch directory below `.agent-runs/` (Agents), `.forge/deliveries/` (Forge), or
`.rca/<slug>/deliveries/` (RCA). Run `status <runs-directory> --runs` on every entry
and resumption, including standalone steps. `blocked:true` means recover the listed
records before any fresh dispatch, artifact-based advancement, or destructive recovery.
Missing records mean legacy dispatch is unknown; preserve existing artifacts and
reconcile available session evidence, never claim that absence proves no dispatch.

```bash
python3 "<plugin-root>/bin/agent-delivery.py" status "<runs-directory>" --runs
python3 "<plugin-root>/bin/agent-delivery.py" <command> "<batch-directory>"
```

Pass one JSON object on stdin using a literal heredoc or an input file. Never
interpolate agent prose into shell code. Output contains `ok`, `state`, `actions`,
`notices`, and `display`; status with `--runs` instead returns `blocked`, `legacy`,
and the inspected `runs`. Nonzero or `ok:false` means stop transport, retain full
diagnostics, and read status: a state write may have succeeded before rendering failed.
Do not blindly retry. Every mutation except init requires the last observed `revision`.
Revision conflict means read fresh status and reconcile, never overwrite.

| Command | JSON fields besides revision | Purpose |
|---|---|---|
| init | owner, host, session, step, capacity, tasks | Persist complete finite roster before dispatch |
| record | task_id, attempt_id, kind, event fields below | Record actual transport facts |
| advance | none | Apply deadlines before/after transport and between waits |
| status | no stdin | Inspect one batch without changing it |
| recover | session, reachable (native ID list) | Reconcile owner/identity using original deadlines |
| finish | outcome, integrity_ok or reason | Finish succeeded, failed, interrupted, or reconciled |

`owner` is agents/forge/rca; `host` is claude/codex. `session` must be the actual
parent session identity, not a newly generated replacement on resume. Each task has
unique `task_id`, exact original `task` text, canonical `role`, and boolean `writer`.
Derive writer status from the resolved role and explicit write allowance: any write
capability or ambiguity uses true, even when the role is performing research.
Snapshot current native capacity once; the helper fixes waves and the batch ceiling.
Independent readers share available slots; writers occupy their wave alone.

Before init, preflight nonblocking native dispatch, result observation with actual
sender IDs, bounded waits, time, interruption, and at least one worker slot. If a
capability is absent, report an incomplete handoff without spawning. Never enter a
synchronous call that can hold the parent for the task's full duration. Do not change
host permissions or background settings to force availability.

Snapshot content/status, existing dirty/untracked files and approved paths before
dispatch. Store baseline evidence outside worker-owned paths. Retain each owner's
existing integrity checks. The helper validates delivery, not filesystem permissions.

## Events and actions

| kind | Event fields | Rule |
|---|---|---|
| dispatch-attempted | none | Persist immediately before native spawn/follow-up |
| dispatched | agent_id | Record the exact returned identity immediately |
| delivery | sender, body | Actual transport sender and unmodified response string |
| probe-attempted | none | Persist before the one native progress probe |
| progress | working, evidence | Current-attempt progress, not presence or idle notification |
| failure | category, reason | transport may retry; permission/capability/integrity never retry |
| stopped | agent_id, stopped, integrity_ok | Confirm old execution ended; separately verify baseline |

Consume dispatch/probe actions exactly once by recording the attempted event before
transport. A crash between attempted and returned identity is uncertain; never replay
it. Only `advance` grants current actions; status is inspection, not dispatch permission.
Never use a requested task name in place of a returned native ID.

On Claude use exposed nonblocking background dispatch and completion/messaging tools;
if explicit messaging is needed, send a string containing the envelope to the recorded
parent identity. On Codex use native spawn_agent, followup_task, wait_agent, list_agents,
and interrupt_agent as available; final responses carry the actual sending identity.
Do not invent a tool, read private inbox files, or claim an idle notification is delivery.
Follow-up corrections are new bounded attempts, not untracked work on an accepted task.

Run advance before and after transport. Collect in slices at most 30 seconds, shortened
to actions' wait_seconds and the nearest deadline. A native wait minimum longer than
the remaining time requires a shorter supported clock wait, not rounding past expiry.
Run advance again after each slice. Keep user-facing progress visible during waits.

Initial expiry requests one probe. Inspect the exact current native ID and ask for
delivery/current progress, within 30 seconds inside the extension budget. Only positive
current-attempt evidence earns the remaining extension. Idle/dead/unknown earns none.
Progress, retries, reduced capacity and resume never refresh the batch ceiling.

| Policy | Initial | One extension | One reader retry | Hard maximum |
|---|---:|---:|---:|---:|
| Agents; Forge research/design/planning; RCA readers | 900 s | 300 s | 300 s | 1500 s |
| Forge evaluator/reviewer/triager | 600 s | 120 s | 120 s | 840 s |
| Any writer | 1800 s | 300 s | 0 s | 2100 s |

The batch maximum is the sum of fixed wave maxima. Reader retry requires stopped:true
and integrity_ok:true before a replacement receives a fresh attempt ID; stopping itself
has at most 30 seconds inside the task ceiling. Salvage evidence on retry rather than
starting a full measurement battery. Writers never retry automatically. Denied tools,
unavailable capability, and unexpected writes fail immediately. Do not convert transport
failure into an evaluator verdict or consume another pipeline retry to bypass this rule.

## Worker envelope

Append these exact state-derived values to the full role + owner override + task prompt:

```json
{"batch_id":"...","task_id":"...","task_digest":"...","attempt_id":"...","kind":"result","payload":{}}
```

Payload is the role's existing output unchanged (object or string). Failure uses the
same identities, `kind:"failure"`, a nonempty `reason`, and category transport, permission,
capability, or integrity. Both hosts accept bare JSON or one complete JSON fence.

Workers must not spawn further agents, ask the user questions, wait for input, stage,
commit, or write owner state. Return unavailable input/permission immediately. Use only
approved paths and private scratch. Long commands must yield in short collection slices;
a generous delivery budget cannot rescue an unbounded synchronous tool call.

The owner validates substantive relevance and existing payload schemas after helper
acceptance. Wrong-question content records failure with context, never a fabricated
replacement response. Stale identity, duplicate and late messages remain audit events
and cannot satisfy or alter a task. Missing output is never successful completion.

## Finish and recovery

Stop/confirm owned execution and compare the content baseline after each wave. All
required results plus existing semantic/integrity gates are required before finish with
outcome succeeded and integrity_ok:true. Accepted responses alone do not authorize
pipeline advancement. Failure writes an incomplete handoff, preserves partial changes,
and halts that step without synthesizing completion markers.

Terminal state is durable before cleanup. Cleanup gets 30 seconds total; interrupt only
owned still-running identities and record stopped facts. The helper persists remaining
IDs from dispatch evidence, even if cleanup cannot run. Do not wait forever for shutdown,
delete shared scratch, or begin another run while survivors are unresolved. Rendered
LIVENESS.md is regenerated by recover after a crash between state and Markdown writes.

Same session plus confirmed reachable identities retains accepted responses and original
deadlines. New owner, lost worker, uncertain dispatch, or clock discontinuity interrupts
the batch. Monotonic time governs elapsed waits; backward clocks or more than five seconds
of wall/monotonic disagreement do not grant fresh time. No notices can be emitted while
the host is dead; the bound applies to an operating owner and makes resumed work legible.

After failed/interrupted work, explicit reconciliation may use finish outcome reconciled
with reason, integrity_ok:true and artifacts_reconciled:true only after all owned agents
are confirmed stopped and partial artifacts are preserved/reconciled against the baseline.
An uncertain send with no observable native identity cannot be declared clean. Never
automatically reconcile, delete a batch, or loop through fresh batches after failure.

Surface display and notices for probe, extension, retry, failure, interruption, recovery,
and cleanup with task, elapsed seconds, reason and audit path. Include limitations and
partial-result paths in the existing owner handoff. Persistence alone is not visibility.
