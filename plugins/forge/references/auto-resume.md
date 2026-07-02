# Auto-Resume

Freshen-based context clearing and re-invocation for autonomous execution.

## Mechanism

Forge uses the freshen plugin for automatic session transitions. When forge pauses (session limit reached, blocked, or any pause trigger), it queues a freshen signal. The sequence:

1. **Pause**: Forge writes handoff, sets status to `paused`, releases lock
2. **Queue**: Forge runs `bash plugins/freshen/bin/freshen.sh queue "/forge resume" --source forge --summary "Execution paused — [reason]"`
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

At every pause point in the execution loop:

```bash
bash plugins/freshen/bin/freshen.sh queue "/forge resume" --source forge --summary "Execution paused — [N] stories completed this session"
```

If the queue command fails (tmux not available, freshen not installed):
- Log: "Auto-resume unavailable. Run `/forge resume` manually."
- Do NOT treat this as a fatal error -- forge still pauses cleanly.

## Teardown

On `/forge stop` or completion, cancel any pending signal:

```bash
bash plugins/freshen/bin/freshen.sh cancel --source forge
```

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
