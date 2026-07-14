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

#### The Same Hazard Recurs on SessionStart(clear) (F052)

The identical ordering problem shows up again one step later, on the `SessionStart(clear)` event
that follows: freshen's `on-clear.sh` and hook-guard's `hooks/session-start.sh` are two independent
hooks (different plugins) that both fire on that same event and both read
`.freshen/.clear-pending` — on-clear.sh to decide whether to process the queued signal, hook-guard
to decide whether this `/clear` was freshen-initiated (skip resetting its Stop-loop circuit
breaker) or a genuine user `/clear` (reset is correct). Claude Code does not guarantee which of the
two runs first here either.

The naive fix — on-clear.sh deletes `.clear-pending` once it's done with it — is order-dependent:
if on-clear.sh happens to run *before* hook-guard's hook in the same batch, hook-guard finds nothing,
concludes this was a bare user `/clear`, and resets the breaker anyway. That silently defeats F052's
whole point, because it strikes exactly the case the breaker most needs to survive: a runaway
freshen-mediated Stop/clear/resume loop produces a `SessionStart(clear)` every cycle, so a
reset-on-every-clear outcome here means the breaker can never trip no matter how many cycles run.

The fix, same principle as above — don't depend on ordering: on-clear.sh never deletes
`.clear-pending` outright. Every path that used to do so instead renames it to
`.freshen/.clear-consumed`, handing the "this `/clear` was freshen-initiated" fact off rather than
destroying it. hook-guard's hook checks for `.clear-pending` **or** `.clear-consumed` and is the
sole reader/deleter of the latter, so whichever hook runs first, the other still finds the fact it
needs:

- hook-guard runs first: sees `.clear-pending` (on-clear.sh hasn't touched it yet) — skips the reset.
- on-clear.sh runs first: renames `.clear-pending` → `.clear-consumed` while doing its own
  processing; hook-guard then finds `.clear-consumed` instead and treats it identically.

#### A Narrower Regression In The "hook-guard Runs First" Order

Adversarial verification of the fix above found a second, narrower ordering bug in the branch that
looks safe: when hook-guard runs *first*, it correctly sees `.clear-pending` directly and skips the
reset — but per the constraint above it must leave the file alone (on-clear.sh still needs its
content), so hook-guard does not delete anything. on-clear.sh then runs second, as always, and
renames `.clear-pending` → `.clear-consumed`. But hook-guard has already finished handling *this*
SessionStart(clear) event and will not run again until the next one — so nothing in this cycle ever
reads or deletes the `.clear-consumed` that on-clear.sh just created. It lingers on disk after an
event that was already fully and correctly handled.

If the very next `SessionStart(clear)` is a genuine, unrelated, bare user `/clear` (no
`.clear-pending` ever touched for it), hook-guard's hook finds that stale `.clear-consumed`, wrongly
treats it as evidence that *this* `/clear` was also freshen-initiated, and skips a reset that should
happen — silently defeating the breaker's auto-recovery for an event that had nothing to do with
freshen.

The fix bounds `.clear-consumed`'s validity to a short freshness window on its mtime, rather than
treating bare existence as proof: hooks racing for the *same* SessionStart event run back-to-back in
the same batch (reliably well under a second apart); two genuinely distinct SessionStart(clear)
events are always at least one full model round-trip apart (seconds, typically far more). This is
the same "same batch vs. a later event" reasoning hook-guard's own `stop-guard.sh` already relies on
for its `_STOP_GUARD_DEDUP_WINDOW` (see `plugins/hook-guard/lib/stop-guard.sh`). A `.clear-consumed`
younger than the window (`CLEAR_CONSUMED_WINDOW`, default 5s) is trusted as this event's own
hand-off; anything older is treated as a stale leftover and does **not** suppress the reset. Either
way the marker is deleted the moment hook-guard reads it, fresh or stale, so it can never accumulate
or be misread by a later event again — there is exactly one consumer responsible for cleaning up
each marker, on exactly one read.

## Capture-Pane Read-Back (F045, F041, F056)

Both tmux sends in the auto-resume cycle — `on-stop.sh`'s `/clear` and `on-clear.sh`'s
re-invocation command — used to blind-fire `tmux send-keys` and immediately treat the send as
"done": `on-stop.sh` was explicitly "fail-fast, no retry", and `on-clear.sh` deleted its signal
file gated only on the *first* of its two send-keys calls (the literal command text) succeeding,
independent of whether the follow-up `Enter` did. A busy, wedged, or dead pane could silently
strand the whole pipeline: context cleared with nothing typed, or a command typed but never
submitted, with the durable state already discarded and no path back except the 2-hour stale-signal
sweep.

Both hooks now confirm the send via `plugins/freshen/lib/pane-confirm.sh`, a bounded
`tmux capture-pane -p` poll + resend loop:

1. Deliver the text **once**, then a *separate* Enter to submit, with a short settle
   (`PANE_PASTE_SETTLE_DELAY`, default 0.2s) in between so a bracketed paste closes and the Enter
   is read as "submit" rather than absorbed as a newline (the issue #82 race, adopted defensively).
   The paste is one `send-keys <text>` call in `"keys"` mode (short control sequences like
   `/clear`) or one `send-keys -l <text>` call in `"literal"` mode (arbitrary re-invocation command
   strings). Both the paste *and* the Enter must succeed for the send to count as attempted,
   closing F041's exact gap.
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
  confirms acceptance. The F052 `.clear-pending` → `.clear-consumed` hand-off (see above) is
  unconditional either way — it must keep firing regardless of whether the re-invoke itself was
  ultimately confirmed, since that fact (whether *this* `/clear` was freshen-initiated) is
  independent of the re-invoke's success.

Every send/confirm decision is also recorded in `.freshen/transitions.log` — see below.

### Why freshen does not adopt #82's input-row submission confirm (issue #86)

Issue #82 fixed the same *re-paste-on-retry* footgun in `/issue do`'s prompt handoff
(`plugins/issue/bin/issue.sh`). That fix goes further than freshen's: it confirms the prompt was
*received* (scoping the read-back to the `❯` input **row**, since the real TUI renders a footer
*below* the box that makes a last-non-blank-line check vacuous), then submits, then confirms the box
*cleared*. Issue #86 asked whether freshen should adopt that stronger confirm too. **It must not** —
and the reason is structural, not a matter of taste:

- **`/issue do` targets a *separate, live* pane.** It opens a new tmux window running an idle
  `claude` TUI that processes keystrokes *immediately*, so an in-hook `capture-pane` can observe
  both receipt and submission. Its input-row confirm is correct *there*.
- **freshen targets *its own* pane** (`$TMUX_PANE` — the very Claude Code session whose Stop /
  SessionStart hook is running). Per this repo's `CLAUDE.md` ("Hook ordering"), keystrokes sent by a
  hook are buffered and *"aren't acted on until all of that turn's hooks finish."* Submission is
  therefore **causally gated on the hook batch returning** and is *unobservable* from inside the
  hook — the confirm poll runs synchronously *within* that batch, so it can never observe an effect
  gated on its own termination.
- **The pipeline depends on the confirm staying fast.** `on-stop.sh` must set `.clear-pending`
  *before* `/clear` is processed, or `on-clear.sh` (which fires when `/clear` runs) finds no
  `.clear-pending` and skips the re-invoke. A receipt/submission confirm scoped to the input row
  would *hang* whenever the TUI echoes the typed text mid-hook → the poll times out → `.clear-pending`
  is never set → the already-sent `/clear` still wipes context → the re-invoke is skipped → the whole
  auto-resume cycle is stranded until the 2-hour stale-signal sweep. No timing path rescues this.

So freshen adopts only the **safe** #82 mechanics — deliver-once + Enter-only resend + the paste
settle — and keeps its last-non-blank-line check as an intentionally weak *liveness probe*. Under the
deferred-hook model the genuinely load-bearing branch is the `capture-pane`-**failure** path (a
dead/unreachable pane → resend); the content-based check is vacuous-but-safe (freshen's own TUI
renders the same footer-below-box layout #82 diagnosed, so the last non-blank line is the footer and
the check confirms fast in every reachable-pane case). The input-row confirm would only become
correct if freshen ever sent to a *separate live pane* the way `issue.sh` does — it does not today.

## Transition Audit Log (F047)

`on-stop.sh`, `on-clear.sh`, and `forge-step-exit.sh` each append one short, timestamped line to
`.freshen/transitions.log` (gitignored, inside the already-ignored `.freshen/` directory) at every
transition point: which step queued/cancelled what, which hook sent what, and whether it was
confirmed. This is deliberately **not** `tmux pipe-pane` (which mirrors a pane's entire raw output
continuously and would need its own enable/disable lifecycle plus size/rotation management to stay
bounded — real added scope for comparatively little extra diagnostic value here). The log is capped
to the most recent 500 lines (`plugins/freshen/lib/transition-log.sh`) so it stays lightweight
across a long-running pipeline. A stalled auto-resume cycle can be diagnosed post-hoc with a plain
`cat`/`tail .freshen/transitions.log`.

## Pane-Option Migration (F046) — Deferred

The hardening audit's F046 proposed replacing the file-based `.freshen/.clear-pending` /
`.clear-consumed` coordination with a tmux user pane option (`tmux set-option -p @forge_clear_pending
1` / `show-options -pv`), reasoning that pane options are pane-scoped, atomic, and can't be
"orphaned on disk" the way an unscoped, untimestamped file can (F040).

That reasoning predates the F052 hardening above: the orphaning concern it was chiefly aimed at is
now substantially closed by `.clear-consumed`'s freshness window (hook-guard's `session-start.sh`
bounds how long it trusts a marker it didn't just create itself, so a stale leftover is
self-limiting — ignored after `CLEAR_CONSUMED_WINDOW` seconds — rather than orphaned indefinitely).
Weighed against that much-reduced remaining benefit, a full migration would require:

- Re-deriving the *same* cross-plugin ordering and freshness-window logic against pane options
  instead of file mtimes (pane options have no built-in timestamp — a second option would be
  needed just to carry one, giving up the atomicity that was the whole selling point).
- Updating hook-guard's `session-start.sh` in lockstep (the two sides coordinate on the same
  signal and cannot be migrated independently), re-touching logic that took two rounds of
  adversarial verification to get right, including a real regression the first fix attempt
  introduced.
- Weaker test confidence than the current file-based coverage: this repo's established convention
  for these exact hooks (`plugins/forge/hooks/session-stop.bats`) is a *stubbed* tmux executable,
  not a live session, specifically so hook tests stay hermetic and don't depend on a real tmux
  server being available wherever `make test` runs. A pane-option migration would need that stub to
  fake a *stateful* key-value store (to make `show-options` reflect a prior `set-option`) with
  timestamp semantics of its own — a materially higher-fidelity-risk stand-in for the exact
  correctness-critical logic that must not regress, for a benefit that has already largely been
  captured by the freshness-window fix.

Given the cost/benefit has shifted since the plan was written, F046's full migration is deferred
(mirroring how F044/F104's watchdog/supervisor spike was deliberately deferred) rather than forced
through at the expense of the hard-won F052 test confidence. The genuinely self-contained,
purely-additive pieces (F045, F041, F056, F047 above) shipped on their own. Revisit F046 if a future
need actually requires pane-scoped (rather than project-dir-scoped) coordination — e.g. two
concurrent Claude Code panes operating in the same project directory — which the current file-based
approach does not handle and pane options would.

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
