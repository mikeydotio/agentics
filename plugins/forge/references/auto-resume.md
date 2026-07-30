# Auto-Resume

Freshen-based context clearing and re-invocation for autonomous execution.

## Mechanism

Forge uses the freshen plugin for automatic session transitions. When forge pauses (session limit reached, blocked, or any pause trigger), it queues a freshen signal. The sequence:

1. **Pause**: Forge writes handoff, sets status to `paused`, releases lock
2. **Queue**: Forge runs `bin/forge-step-exit.sh` (`references/step-handoff.md`), which queues the
   signal via freshen (resolving freshen's own portable path internally — never a bare
   `plugins/freshen/...` invocation from a step skill)
3. **Stop**: Session ends. Freshen's Stop hook detects the signal, sends `/clear` via tmux
4. **Clear**: Context is wiped. Freshen's SessionStart(clear) hook reads the signal, echoes the summary as a progress breadcrumb, sends `/forge resume` via tmux
5. **Resume**: New session starts. Forge's SessionStart hook injects state context. `/forge resume` acquires lock and continues

This is fire-once: the signal file is consumed after use. Each pause must re-queue.

## tmux Requirement

Freshen requires tmux (`$TMUX` and `$TMUX_PANE` environment variables). Claude must be running inside a tmux session.

- **tmux available**: Auto-resume works automatically. No user intervention needed between sessions.
- **tmux not available**: Forge logs a warning at `/forge run` time. The user must run `/forge resume` manually after each session ends. All other forge functionality works normally.

## Setup (at `/forge run`)

No installation step is needed. Forge checks for tmux availability and reports:

```
If $TMUX and $TMUX_PANE are set:
  -> "Auto-resume via freshen is available."
Else:
  -> Warning: "tmux not detected -- auto-resume unavailable. Manual /forge resume required."
```

## Pause (queuing the signal)

At every pause point in the execution loop, `bin/forge-step-exit.sh --step execute --summary "..."
--next "/forge resume"` (see `references/step-handoff.md`) queues the signal as part of the
standard step-exit call — there is no separate freshen invocation to write by hand.

If the queue fails (tmux not available, freshen not installed), the script reports
`freshen_queued: false` with a `fallback_message`:
- Show it to the user: "Auto-resume unavailable. Run `/forge resume` manually."
- Do NOT treat this as a fatal error -- forge still pauses cleanly.

## Teardown

On `/forge stop`, cancel any pending signal — see `skills/forge/SKILL.md`'s `/forge stop` section
for the portable path resolution (freshen's plugin root as a sibling of forge's own, never a bare
`plugins/freshen/...` path). On completion (all stories done), deploy's terminal step-exit call
(`--terminal`) cancels the signal instead of queueing a next one.

## Session-Stop Hook

When the session ends unexpectedly (not a graceful `/forge stop`), the forge session-stop hook:
1. Writes a degraded handoff
2. Sets status to `paused`
3. Releases the lock
4. Attempts to queue a freshen signal for auto-resume:
   - Writes `.freshen/forge.signal` directly (bypasses `freshen.sh` to avoid tmux validation in hook context)
   - Sends `/clear` itself via `tmux send-keys` (see **Cross-Plugin Hook Ordering** below) — it does
     not wait for freshen's own Stop hook to notice the signal
   - If tmux is not available or the write fails, the signal is skipped -- user must `/forge resume` manually

### Cross-Plugin Hook Ordering

Claude Code does **not** guarantee execution order between different plugins' hooks registered on
the same event (forge's `session-stop.sh` and freshen's `on-stop.sh` are two independent `Stop`
hooks that both fire on the same Stop event). This matters here specifically because forge's hook
*writes* the signal file that freshen's hook *reads* — if freshen's hook happened to run first, it
would find nothing yet and exit without ever sending `/clear`, silently stranding the signal until
the next session start deleted it unread.

The fix is to not depend on ordering at all: forge's session-stop hook sends `/clear` itself
(`tmux send-keys -t "$TMUX_PANE" "/clear" Enter`) immediately after writing the signal, rather than
relying on freshen's Stop hook to pick it up. To avoid a double `/clear` if freshen's hook runs
*after* forge's in the same batch and finds the just-written signal, both hooks treat
`.freshen/.clear-pending` as a single "has `/clear` already been sent for this Stop event" marker:
whichever hook sends `/clear` first sets it; the other checks it first and skips sending a second
one. Either hook can safely run first or run alone — the outcome (exactly one `/clear` sent, the
signal left for `on-clear.sh` to consume) is the same.

(Separately, tmux itself buffers keystrokes until the CLI is ready to accept input, so a `/clear`
sent from within a Stop hook is not acted on until all of that turn's Stop hooks have finished
running. That buffering guarantee is real, but it is unrelated to the ordering problem above — it
governs *when a already-sent* `/clear` is processed, not *whether* one gets sent in the first
place.)

#### The same hand-off on SessionStart(clear)

The same ordering hazard recurs one event later. Freshen's `on-clear.sh` and hook-guard's
`hooks/session-start.sh` both fire on `SessionStart(clear)` and both read `.freshen/.clear-pending`
— on-clear.sh to decide whether to process the queued signal, hook-guard to decide whether this
`/clear` was freshen-initiated (skip resetting its Stop-loop circuit breaker) or a genuine user
`/clear` (reset is correct). Order is not guaranteed here either.

Three rules make it order-independent. Changing any of them reintroduces a bug that is silent in
normal operation and only shows up when the circuit breaker is needed:

1. **`on-clear.sh` never deletes `.clear-pending`.** Every path that would delete it instead renames
   it to `.freshen/.clear-consumed`, handing the "this `/clear` was freshen-initiated" fact off
   rather than destroying it.
2. **hook-guard accepts either marker** — `.clear-pending` or `.clear-consumed` — and is the sole
   reader and deleter of `.clear-consumed`. Whichever hook runs first, the other still finds the
   fact it needs.
3. **`.clear-consumed` is trusted only within a freshness window** (`CLEAR_CONSUMED_WINDOW`, default
   5s, on its mtime), not on bare existence, and is deleted the moment hook-guard reads it —
   fresh or stale. Existence alone would let a marker left over from a correctly-handled event
   suppress the reset on the *next*, unrelated `/clear`.

Rationale for all three, including the two bugs that produced them:
[`docs/decisions/forge-auto-resume.md`](../../../docs/decisions/forge-auto-resume.md).

## Capture-Pane Read-Back

Neither tmux send in the cycle — `on-stop.sh`'s `/clear` and `on-clear.sh`'s re-invocation command —
may be blind-fired. A busy, wedged, or dead pane otherwise strands the whole pipeline silently:
context cleared with nothing typed, or a command typed but never submitted, with the durable state
already discarded and no path back except the 2-hour stale-signal sweep.

Both hooks confirm the send via `plugins/freshen/lib/pane-confirm.sh`, a bounded
`tmux capture-pane -p` poll + resend loop:

1. Deliver the text **once**, then a *separate* Enter to submit, with a short settle
   (`PANE_PASTE_SETTLE_DELAY`, default 0.2s) in between so a bracketed paste closes and the Enter
   is read as "submit" rather than absorbed as a newline (the issue #82 race, adopted defensively).
   The paste is one `send-keys <text>` call in `"keys"` mode (short control sequences like
   `/clear`) or one `send-keys -l <text>` call in `"literal"` mode (arbitrary re-invocation command
   strings). Both the paste *and* the Enter must succeed for the send to count as attempted.
2. Poll `capture-pane -p` (a handful of attempts, ~300ms apart) for evidence the sent text no
   longer sits, unsubmitted, on the pane's last non-blank line — i.e. it left the input box. This
   is deliberately agnostic to what Claude Code's TUI renders once a command is accepted (an
   implementation detail that could change); "no longer sitting there unsubmitted" is the weakest
   claim that still meaningfully distinguishes "the pane reacted" from "the pane never processed
   it at all" (the busy/wedged-pane failure mode). A failed `capture-pane` call itself (dead pane,
   bad target) is treated as *not yet confirmed*, never as success.
3. On failure to confirm, re-send the **Enter alone** (bounded — a couple of extra attempts),
   **never re-pasting the text**: re-pasting would duplicate the command in the input box (issue
   #86, the sibling of the #82 re-paste-on-retry bug). Only a paste that never landed (the
   `send-keys` call itself errored) is retried as a paste.

**What changes on an unconfirmed send:**

- `on-stop.sh` only sets `.clear-pending` — the durable flag `on-clear.sh` and hook-guard's
  breaker-skip both key off of — once the `/clear` is confirmed. If it's never confirmed,
  `.clear-pending` is left unset and the `*.signal` file untouched, so the *next* Stop event
  retries the whole clear from scratch. This is safe without introducing a new cross-plugin race:
  Stop hooks in the same batch run sequentially (see "Cross-Plugin Hook Ordering" above), so
  `on-stop.sh` — including its confirm/resend loop — always finishes before any other plugin's
  Stop hook in the same batch starts. There is no window where a partially-confirmed clear could
  be observed by forge's `session-stop.sh`.
- `on-clear.sh` only deletes the signal once both send-keys calls succeeded *and* the read-back
  confirms acceptance. The `.clear-pending` → `.clear-consumed` hand-off (see above) is
  unconditional either way — it must keep firing regardless of whether the re-invoke itself was
  ultimately confirmed, since that fact (whether *this* `/clear` was freshen-initiated) is
  independent of the re-invoke's success.

Every send/confirm decision is also recorded in `.freshen/transitions.log` — see below.

The last-non-blank-line check is deliberately a weak *liveness probe*, not a receipt confirm.
Do not "strengthen" it to scope the read-back to the `❯` input row the way `/issue do` does: freshen
sends to its own pane, where submission is causally gated on the hook batch returning and is
therefore unobservable from inside the hook, and a confirm that hangs strands the entire
auto-resume cycle. Full reasoning:
[`docs/decisions/forge-auto-resume.md`](../../../docs/decisions/forge-auto-resume.md).

## Transition Audit Log

`on-stop.sh`, `on-clear.sh`, and `forge-step-exit.sh` each append one short, timestamped line to
`.freshen/transitions.log` (gitignored, inside the already-ignored `.freshen/` directory) at every
transition point: which step queued/cancelled what, which hook sent what, and whether it was
confirmed. This is deliberately **not** `tmux pipe-pane` (which mirrors a pane's entire raw output
continuously and would need its own enable/disable lifecycle plus size/rotation management to stay
bounded — real added scope for comparatively little extra diagnostic value here). The log is capped
to the most recent 500 lines (`plugins/freshen/lib/transition-log.sh`) so it stays lightweight
across a long-running pipeline. A stalled auto-resume cycle can be diagnosed post-hoc with a plain
`cat`/`tail .freshen/transitions.log`.

## Coordination is file-based, deliberately

`.clear-pending` / `.clear-consumed` are files rather than tmux pane options. A migration to pane
options was evaluated and deferred; revisit it only if a real need arises for pane-scoped rather
than project-dir-scoped coordination — e.g. two concurrent Claude Code panes in the same project
directory, which the file-based approach does not handle. Reasoning:
[`docs/decisions/forge-auto-resume.md`](../../../docs/decisions/forge-auto-resume.md).

## Safety

- Signal cancelled on `/forge stop` (user-initiated graceful stop)
- Signal cancelled on completion (all stories done)
- Runaway safeguards (`max_sessions`, `max_total_retries`) prevent unbounded execution
- Freshen's cross-source conflict check prevents forge's signal from conflicting with other sources
- Stale signal cleanup: freshen's Stop hook deletes signals older than 2 hours

## Resume Latency

With freshen, resume is near-instant:
- Session ends -> Stop hook fires `/clear` -> SessionStart hook sends `/forge resume`
- Total latency: seconds (limited only by Claude's response time)

## Worst-Case Resume Latency

If a session crashes without releasing the lock, the next resume attempt must wait for the heartbeat to go stale (default: 30 minutes). With freshen, there is no additional trigger interval delay.
