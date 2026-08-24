# Freshen could consume a Codex continuation before Codex accepted it

- **Date**: 2026-08-23 PDT / 2026-08-24 UTC
- **Severity/Impact**: High — Freshen's Codex reset path could silently lose a queued workflow continuation while reporting success; affected runs could also submit concatenated reset text or leave the continuation pending in the input box.
- **Status**: Fixed in `e33c914` and `be91f85`

## Summary

Freshen 3.9.1 could report a successful Codex `/new` lifecycle and delete its queued signal even when Codex accepted neither the reset nor the continuation. The Codex integration expected `/new` to emit `SessionStart(clear)`, but Codex 0.149.0 instead emitted a lazy `SessionStart(startup)` only after another prompt was submitted; the fallback path therefore advanced using pane appearance rather than lifecycle acknowledgement. Commits `e33c914` and `be91f85` replace that inference with a Codex-specific, monotonic reset handshake that preserves the claimed command until ordered startup and Stop events prove delivery. The durable lesson is that asynchronous host transitions require host-observed acknowledgement and at-most-once state, not elapsed time or terminal-text disappearance.

## Timeline

- **2026-07-03** — `e325e496` introduced a shared last-nonblank-line pane predicate, and `e10cd36` connected its result to reset progress and signal deletion. These semantics were valid for the original Claude-oriented flow but did not model Codex's persistent footer or lazy startup.
- **2026-08-23 10:11 PDT** — `c2588474` added native Codex support and reused the shared pane predicate in a detached `/new` fallback. This was the first native Codex deferred-reset implementation; there is no known-good predecessor to bisect.
- **2026-08-23 PDT / 2026-08-24 UTC** — A failure was observed after a fresh context clear and full Codex relaunch. The original workflow signal had probably already been consumed, so investigation continued with harmless signals in disposable Codex homes and tmux panes.
- **2026-08-23 PDT / 2026-08-24 UTC** — The exact installed-manifest path reproduced the semantic failure. Raw hook capture established that `/new` emitted lazy `source:"startup"`, detached-worker capture ruled out lost cwd/plugin/tmux environment, and controlled experiments separated the reset race from trust, matcher, stale-state, and plugin-root hypotheses.
- **2026-08-23 22:22 PDT** — `e33c914` landed the Codex lifecycle handshake for AGE-96. The repaired path passed 21 of 21 real semantic trials, all 58 Freshen tests, and the packaging smoke.
- **2026-08-23 22:33 PDT** — The mandatory sibling sweep found that same-source requeue was isolated only at continuation submission. `be91f85` moved the command into the journal atomically at initial Stop, made Codex status/cancellation journal-aware, updated the shipped Codex skill contract, and added the early-window regression. The revised path passed another real semantic trial and all 60 Freshen tests.

## Root cause & trigger

Freshen modeled Codex `/new` using the wrong lifecycle contract. Its manifest routed continuation work through `SessionStart(clear)`, while Codex 0.149.0 emitted no event when `/new` was entered and later emitted `SessionStart(startup)` only after a new prompt. The intended clear adapter was therefore unreachable, and the actual startup adapter treated planned reset state as stale cleanup.

That interface mismatch forced the detached Stop worker to become the primary continuation path. The worker treated `.clear-pending` and broad pane readiness as reset completion; the shared confirmation predicate inspected the last nonblank terminal line, which in Codex was normally a persistent footer rather than the active input row. The worker could consequently submit the continuation during an unsettled transition, classify still-pending text as accepted, and delete the signal even though persisted Codex rollouts contained zero accepted continuation messages. An outer retry could also repaste `/new`, producing concatenated input such as `/new/new`.

The triggering condition was an asynchronous `/new` transition followed by detached continuation delivery on Codex's lazy-startup boundary. The verified chain was:

```text
incorrect /new-to-SessionStart source model and no planned-reset handshake
  -> worker advances on footer/UI state instead of a post-/new lifecycle event
  -> continuation is submitted in an unstable or wrong session and appears accepted
  -> signal is deleted although Codex accepted no continuation
```

ODC classification: **Interface / Incorrect**, with a necessary **Timing/Serialization / Missing** companion; trigger: asynchronous startup/restart boundary.

## Contributing factors

- The shared pane predicate was designed around another host's terminal layout, while Codex keeps footer text below its active input.
- The initial Codex smoke treated signal deletion and Freshen transition labels as its success oracle, so the implementation and the test could agree on a false positive.
- `/new` does not itself create the new Codex thread or fire SessionStart; a subsequent harmless prompt is required to trigger the lazy `startup` event.
- The fallback had no durable binding to a signal checksum, nonce, pane, tmux socket, or lifecycle phase, and a retry could paste the reset command more than once.
- A five-second post-reset delay improved the controlled reproduction from 0/3 to 3/3 passes, but exact revert restored failures and timing alone provided no correctness invariant.
- AGE-90 repaired plugin-root routing and exposed this downstream state-machine defect; it did not introduce it. Exact-manifest evidence also excluded trust, matcher loading, wrong cwd, lost detached environment, disabled state, and stale guards from the reproduced failure.

## The fix

Commit `e33c914` implements a Codex-only lifecycle state machine under `.freshen/.codex-reset/`. Commit `be91f85` closes the sibling-sweep overwrite window by atomically moving the command bytes into that journal at initial Stop, before reset work begins; a same-source requeue is therefore a separate next-cycle signal throughout the handshake. Together they bind each planned reset to a nonce, checksum, command bytes, and tmux target; submit `/new`, a harmless bootstrap, and the continuation at most once; interpret the lazy matching `SessionStart(startup)` as reset acknowledgement; and retire the claimed command only after the continuation's subsequent Stop event. Empty-prompt parsing now reads the Codex input region rather than its footer, and wrong source, wrong target, changed signal, cancellation, disabled state, busy pane, send failure, or timeout fails closed.

The verdict was **REDESIGN at the Codex lifecycle boundary**: a timer-only patch would have retained the incorrect event model and false-acceptance paths. AGE-96 contains the focused host-specific repair, while AGE-98 tracks the broader redesign of shared pane-delivery inference and locking outside this corrective scope.

## Preventative action — killing the class

The automated regression `plugins/freshen/tests/test-codex-lifecycle-reset.sh` now exercises the real installed-manifest Stop → `/new` → lazy `SessionStart(startup)` → bootstrap Stop → queued continuation → continuation Stop path from an established Codex thread in a disposable tmux server. Its external oracle inspects persisted rollouts: the prime must remain in the old rollout, bootstrap and continuation must each appear exactly once in the new rollout, and no malformed `/new*` user prompt may exist. This prevents Freshen's own logs or signal deletion from certifying their own correctness.

Codex compatibility tests additionally enforce at-most-once reset and continuation pastes, source/pane/socket binding, initial-claim same-source isolation, journal-aware status/cancellation, fail-closed timeouts, and exact prompt parsing. The fix completed 22/22 real semantic trials across the final handshake revisions and `make test-freshen` completed 60/60 plus packaging smoke. The repository-wide suite reached only the pre-existing Semver release-content gate, where `plugins/semver/hooks/hooks.json` differed from tag `v3.9.1` while `VERSION` remained 3.9.1; AGE-96 changed no Semver files.

## Lessons

- Host lifecycle names are not interchangeable contracts. Capture and test the raw event source emitted by each supported host, especially at reset and startup boundaries.
- Terminal text movement is not command acceptance when a TUI has persistent chrome. Delivery must be confirmed by a semantic event or durable host artifact.
- Detached, multi-hook workflows need an explicit monotonic journal with stable identity and at-most-once transitions; timers may aid settling but cannot serve as acknowledgement.
- End-to-end hook tests need an oracle outside the implementation's own state and logs, and setup failures must be counted separately from semantic outcomes.
