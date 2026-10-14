# RCA registry resolution lacked an owned completion boundary

- **Date**: 2026-10-14
- **Severity/Impact**: Registry-backed RCA role resolution could wait indefinitely. Operational frequency and a last-known-good installed lookup are unknown.
- **Status**: Fixed in candidate source at `b2da31230b88f23f25ca463e5e76affc8b6bcd37`; release and live installation remain unverified.

## Summary

The RCA Agents resolver could block indefinitely while reading the external plugin registry.
Its shell command substitution delegated both command completion and output lifetime to the
registry CLI without owning a deadline or cancellation contract. The repair introduces a
supervisor that owns execution, output files, cleanup, and final outcome classification while
preserving identity selection. Callers must check final status before accepting output.

## Timeline

| Date | Evidence or change |
|---|---|
| 2026-09-12 | Commit `3608756f49f6a65af6aab71e9f31f0ea370c71bd` introduced the registry command substitution in `plugins/rca/bin/resolve-agents-root.sh`. |
| 2026-10-14 | A reported lookup stall prompted investigation. An installed-layout fixture reproduced a marked registry invocation that exceeded a three-second outer watchdog despite a requested 0.25-second resolver bound. The reported stall's exact blocked subprocess remains unestablished. |
| 2026-10-14 | Controlled experiments isolated command lifetime and inherited stdout as blocking mechanisms. The unchanged reproduction passed with the repair and failed after reverting only the shell entry in a disposable copy. |
| 2026-10-14 | Independent review found and then cleared a cancellation race during finalization. All 27 required local `make test` targets passed before fix commit `b2da31230b88f23f25ca463e5e76affc8b6bcd37`. |

## Root cause & trigger

The original registry invocation used unbounded shell command substitution. A CLI that did
not finish therefore kept the resolver waiting without a classified outcome. A separate
experiment observed the CLI parent absent while its child retained stdout: the resolver
remained blocked until that descriptor closed. Command completion and pipe EOF were distinct
requirements, neither governed by the resolver.

**ODC classification:** Interface / Missing; triggered by recovery, error-path, and cancellation
conditions. The trigger requires registry selection rather than an explicit override or checkout sibling.
Empty and malformed finite inputs returned promptly, ruling out the proposed parser loop. These
experiments establish the source defect, not a cause for every interruption or a recent regression window.

## Contributing factors

- The external CLI and its descendants controlled resources the caller needed to finish.
- Identity validation covered finite registry responses but did not enforce command lifetime.
- The first repair accepted cancellation during output or metadata finalization without always changing the final outcome; independent review exposed that separate race.

## The fix

This is a narrow **REDESIGN** of the execution boundary. The public shell entry now execs
[`resolve-agents-root.py`](../../plugins/rca/bin/resolve-agents-root.py), which runs the private
shell validator in an owned process group with regular output files and closed unrelated file
descriptors. It applies a mandatory finite deadline, bounded TERM/KILL cleanup, and a group
check before accepting success or genuine absence. The validator preserves override, sibling,
exact marketplace/version, ambiguity, and manifest checks. External failures cannot impersonate
locally observed timeout or cancellation; no registry invocation is automatically retried.

An I/O-free signal-mask completion boundary reconciles accepted or pending cancellation before
committing an outcome. Bounded finalization corrections handle diagnostic and persistence
failures without repeating validation. Output and process exit are not atomic: **discard stdout
unless the final exit status is 0**. The [runtime contract](../../plugins/rca/codex/references/runtime.md)
defines the deadline, exit codes, evidence, and conditions for a fresh authorized attempt.

Validation passed: 31 focused resolver tests, five Codex contracts, 28 capture-guard cases, and
an isolated installation smoke. The complete local `make test` gate exited 0 in 1025.898 seconds;
independent comparison bound all 637 source entries and the passing log to the exact fix commit.
This proves candidate behavior and packaging, not deployment or live installed recovery.
Interpreter startup, blocking filesystem/kernel/finalization I/O, and detached descendants
remain outside the stated completion guarantee.

Forge's `plugins/forge/bin/resolve-dependency.sh` and Council's `plugins/council/bin/resolve-agents-root.sh`
retain separate registry-capture debt. Revisit shared ownership when repairing either consumer or
introducing another runner; this fix does not repair those consumers or their selection policies.

## Preventative action — killing the class

- [`codex_resolver_liveness_test.py`](../../plugins/rca/tests/codex_resolver_liveness_test.py): `test_nonterminating_registry_is_bounded_by_resolver` separates the resolver deadline from emergency test cleanup.
- [`codex_resolver_recovery_test.py`](../../plugins/rca/tests/codex_resolver_recovery_test.py): named cases cover silent hangs without retry, resistant children, inherited and detached writers, direct/group cancellation, spawn races, and external failure-code classification. Finalization cases cover cancellation during success publication, pending signals, post-completion signals, and failed metadata correction; 11 pre-correction subcases failed before the race fix.
- [`bounded-capture-guard.sh`](../../tests/bounded-capture-guard.sh) guards covered bounded-command consumers against shell substitution. The installation smoke reads resolver output from a file only after checking status; identity regressions remain covered by `codex_resolver_test.py`.

## Lessons

Own command lifetime and output lifetime at the same boundary. Keep absence distinct from failed
observation, and preserve failed attempts before any fresh run. Group cleanup and passing candidate
tests do not prove all descendants are gone or that an installed version contains the repair.
