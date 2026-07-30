# Auto-resume: why the hook coordination looks the way it does

Design rationale extracted from `plugins/forge/references/auto-resume.md`, which now carries only
the operational rules. Nothing here is needed to *run* the pipeline; it is needed to *change* it
safely. Read it before touching `on-stop.sh`, `on-clear.sh`, `session-stop.sh`, or hook-guard's
`session-start.sh` — several of these rules were arrived at by breaking them first.

## Contents

- The `.clear-pending` hand-off, and the two ordering bugs behind it (F052)
- Why `.clear-consumed` has a freshness window
- Why freshen does not adopt issue #82's input-row submission confirm (issue #86)
- Why the pane-option migration is deferred (F046)

## The `.clear-pending` hand-off (F052)

Claude Code does not guarantee execution order between different plugins' hooks on the same event.
Forge's `session-stop.sh` and freshen's `on-stop.sh` are two independent `Stop` hooks. Forge's hook
*writes* the signal file freshen's hook *reads* — so if freshen's ran first it would find nothing
and exit without sending `/clear`, stranding the signal until the next session start deleted it
unread.

The fix was to stop depending on ordering: forge's hook sends `/clear` itself immediately after
writing the signal, and both hooks treat `.freshen/.clear-pending` as a single "has `/clear`
already been sent for this Stop event" marker.

The identical problem then recurred one step later, on `SessionStart(clear)`. Freshen's
`on-clear.sh` and hook-guard's `session-start.sh` both fire on that event and both read
`.clear-pending` — on-clear.sh to decide whether to process the queued signal, hook-guard to decide
whether this `/clear` was freshen-initiated (skip resetting its Stop-loop circuit breaker) or a
genuine user `/clear` (reset is correct).

**The naive fix is order-dependent and silently catastrophic.** Having `on-clear.sh` delete
`.clear-pending` when done means that if it runs *before* hook-guard in the same batch, hook-guard
finds nothing, concludes this was a bare user `/clear`, and resets the breaker. That strikes exactly
the case the breaker most needs to survive: a runaway freshen-mediated Stop/clear/resume loop
produces a `SessionStart(clear)` every cycle, so resetting on every clear means **the breaker can
never trip, no matter how many cycles run.**

So `on-clear.sh` never deletes `.clear-pending` outright — every path that used to renames it to
`.clear-consumed`, handing the fact off rather than destroying it. hook-guard checks for either and
is the sole reader/deleter of `.clear-consumed`.

## Why `.clear-consumed` has a freshness window

Adversarial verification of that fix found a second, narrower bug in the branch that looks safe.
When hook-guard runs *first* it correctly sees `.clear-pending` and skips the reset — but it must
leave the file alone, because `on-clear.sh` still needs it. `on-clear.sh` then runs and renames it
to `.clear-consumed`. Hook-guard has already finished handling *this* event and will not run again
until the next one, so nothing in this cycle ever reads or deletes that `.clear-consumed`. It
lingers on disk after an event that was already fully and correctly handled.

If the next `SessionStart(clear)` is a genuine bare user `/clear`, hook-guard finds the stale
marker, wrongly concludes that clear was freshen-initiated too, and skips a reset that should
happen — defeating the breaker's auto-recovery for an unrelated event.

The fix bounds validity by mtime rather than treating bare existence as proof. Hooks racing for the
*same* event run back-to-back in one batch, reliably well under a second apart; two genuinely
distinct `SessionStart(clear)` events are at least one model round-trip apart. This is the same
"same batch vs. a later event" reasoning hook-guard's own `stop-guard.sh` uses for
`_STOP_GUARD_DEDUP_WINDOW`. A marker younger than `CLEAR_CONSUMED_WINDOW` (default 5s) is trusted;
anything older is stale and does not suppress the reset. Either way it is deleted on read, so it can
never accumulate — exactly one consumer, exactly one read.

## Why freshen does not adopt #82's input-row confirm (issue #86)

Issue #82 fixed the same re-paste-on-retry footgun in `/issue do`'s prompt handoff
(`plugins/issue/bin/issue.sh`), and went further than freshen's fix: it confirms the prompt was
*received* by scoping the read-back to the `❯` input **row** — the real TUI renders a footer *below*
the box, which makes a last-non-blank-line check vacuous — then submits, then confirms the box
cleared. Issue #86 asked whether freshen should adopt that too.

**It must not**, for structural reasons rather than taste:

- **`/issue do` targets a separate, live pane.** It opens a new tmux window running an idle `claude`
  TUI that processes keystrokes immediately, so an in-hook `capture-pane` can observe both receipt
  and submission. The input-row confirm is correct *there*.
- **freshen targets its own pane** (`$TMUX_PANE` — the very session whose hook is running).
  Keystrokes sent by a hook are buffered and are not acted on until all of that turn's hooks finish.
  Submission is therefore causally gated on the hook batch returning, and is **unobservable from
  inside the hook**: the confirm poll runs synchronously within that batch, so it can never observe
  an effect gated on its own termination.
- **The pipeline depends on the confirm staying fast.** `on-stop.sh` must set `.clear-pending`
  *before* `/clear` is processed, or `on-clear.sh` finds no marker and skips the re-invoke. An
  input-row confirm would hang whenever the TUI echoes the typed text mid-hook → poll times out →
  `.clear-pending` never set → the already-sent `/clear` still wipes context → re-invoke skipped →
  the cycle is stranded until the 2-hour stale-signal sweep. No timing path rescues this.

So freshen adopts only the safe #82 mechanics (deliver-once, Enter-only resend, paste settle) and
keeps the last-non-blank-line check as an intentionally weak liveness probe. Under the deferred-hook
model the load-bearing branch is the `capture-pane`-*failure* path (dead pane → resend); the
content check is vacuous-but-safe, since freshen's own TUI renders the same footer-below-box layout
#82 diagnosed. The input-row confirm would only become correct if freshen ever sent to a separate
live pane the way `issue.sh` does.

## Why the pane-option migration is deferred (F046)

F046 proposed replacing the file-based `.clear-pending` / `.clear-consumed` coordination with a tmux
user pane option (`set-option -p @forge_clear_pending 1` / `show-options -pv`), on the grounds that
pane options are pane-scoped, atomic, and cannot be orphaned on disk.

That reasoning predates the freshness-window fix above, which substantially closes the orphaning
concern it was chiefly aimed at — a stale marker is now self-limiting rather than orphaned
indefinitely. Against that much-reduced benefit, a migration would require:

- Re-deriving the same ordering and freshness logic against pane options, which have no built-in
  timestamp. A second option would be needed just to carry one, giving up the atomicity that was the
  selling point.
- Updating hook-guard's `session-start.sh` in lockstep — the two sides cannot migrate
  independently — re-touching logic that took two rounds of adversarial verification to get right,
  including a real regression the first attempt introduced.
- Accepting weaker test confidence. The convention for these hooks
  (`plugins/forge/hooks/session-stop.bats`) is a *stubbed* tmux executable, so hook tests stay
  hermetic and don't need a live tmux server wherever `make test` runs. Pane options would need that
  stub to fake a *stateful* key-value store with timestamp semantics — a materially
  higher-fidelity-risk stand-in for exactly the correctness-critical logic that must not regress.

Deferred rather than forced through, mirroring the F044/F104 watchdog spike. The self-contained,
purely additive pieces (F045, F041, F056, F047) shipped on their own.

**Revisit when** a real need requires pane-scoped rather than project-dir-scoped coordination — e.g.
two concurrent Claude Code panes operating in the same project directory, which the file-based
approach does not handle and pane options would.
