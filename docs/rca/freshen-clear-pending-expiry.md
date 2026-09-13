# AGE-100: Abandoned clear markers suppressed every later Stop

## Cause and reproduction

Freshen's Claude Stop hook records a confirmed tmux send in
`.freshen/.clear-pending`. Confirmation does not prove that Claude executed
`/clear`. If execution never follows, the Clear hook cannot consume the marker.
The old Stop guard trusted its presence indefinitely, even with a queued signal.
Signal pruning did not cover this hidden marker.

The regression drives the production Stop hook with an external tmux fixture:
a successful initial send creates the marker; its real filesystem mtime is
aged 121 seconds without invoking Clear; a second Stop must dispatch again.
Before the fix, that second dispatch never happened. Eight new regressions
failed while all eight original Stop tests and the preservation controls passed.

## Recovery contract

After circuit-breaker and disabled checks, Stop expires a pending marker at
age >=120 seconds, before looking for signals. It removes only that marker,
warns on stderr, and records age and threshold in `transitions.log`. A queued
signal then follows normal confirmed-send handling. A confirmed retry creates
a fresh marker; an unconfirmed retry preserves the signal without a marker.

The hook reads modification time using GNU/BSD stat fallbacks. Timestamp
validation precedes arithmetic. Fresh and future-dated markers remain intact;
unavailable or invalid metadata produces a warning and preserves pending state.
A failed removal produces an error and prevents dispatch. A marker consumed
during metadata inspection is harmless.

This is retry permission on the next eligible Stop, not a timer or evidence
that a delayed original clear can no longer execute. Existing delivery and
cross-hook concurrency assumptions remain. Clock rollback can delay expiry.
Codex's separate reset journal is unchanged. The sibling sweep found Forge's
marker writer and Hook Guard's clear-event readers; Freshen owns recovery for
both marker writers, preserving the existing `.clear-consumed` handoff.

## Validation

All commands used `TMPDIR=/tmp` and the isolated-store wrapper for Bats.

| Check | Result |
|---|---|
| Freshen Stop tests | 19 passed, including 11 new cases |
| Freshen Clear and Hook Guard SessionStart tests | 18 passed |
| Claude dispatcher clear-transition case | 1 passed |
| Hook shell syntax; changed-file ShellCheck warnings/errors; whitespace | Passed |

Coverage includes exact 119/120/121-second boundaries, future timestamps,
no-signal/no-tmux recovery, failed retransmission, preserved consumed state,
GNU/BSD interfaces, invalid/failed metadata, concurrent consumption, failed
removal, disabled state, and circuit-breaker precedence. The lifecycle case
proves an actual initial send, exactly one recovery submission, immediate
deduplication, and subsequent Clear consumption. Tests use real state files;
only external utilities are shimmed. Full-suite validation belongs to the
central verifier.
