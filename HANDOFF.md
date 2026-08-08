# Handoff

## OPEN — AGE-62 needs one command from Mikey, and until it runs nothing changed

**Run `make install-hooks` from a checkout of `main` (not a worktree), then
`make check-hooks`.** That is the whole outstanding step, and it is the user's because it
writes to `$HOME`: `~/.claude/hooks/pre-push-tests.sh` is what Claude Code actually executes,
and the fix is inert until that copy carries it. The verb backs the current file up to
`<dest>.bak.<UTC stamp>` first and prints the digest; `check-hooks` then reports
installed == repo. **Nothing touches `~/.claude/settings.json`** — the registration keeps its
path and its `timeout: 900`, which is what lets both budget resolvers keep resolving.

⚠ **Do not infer from a green `make test` that the live gate is fixed.** The suite exercises
`hooks/pre-push-tests.sh` in this repository. The installed copy is a *copy*, and
`check-hooks` reports drift without preventing it. Same structural gap AGE-72 has with
deployit's `_plugin_root`, and the same rule: verify the topology, don't assume it.

After installing, the first slow push should print **`PRE-PUSH BUDGET EXCEEDED`** and exit 2
rather than going out silently, and `~/.claude/pre-push-verdicts.log` should gain one line per
matched invocation. If the log stays empty across several pushes, the installed copy is not
the one being run — check the registration's path.

**Not in scope and still open:** AGE-63 (the matcher greps the whole command string, so prose
quoting a push costs a full suite run), AGE-64 (the suite runs twice per push), AGE-65
(inverting the gate to a test-result attestation). All three need edits outside every
repository. The new verdict log is the cheapest evidence source for AGE-63.

---

## Handoff — forge × storyhook hardening effort

## Status: core effort complete

All 8 workstreams of the hardening plan (`~/.claude/plans/idempotent-jingling-pine.md`, implementing
the 106-finding audit at `~/Enderchest/agentics-harness-audit/`) are implemented, adversarially
verified, and merged to `main` in both `mikeydotio/agentics` and `mikeydotio/storyhook`. See
`CLAUDE.md`'s "Hardening Roadmap" section for the per-workstream checklist.

A critical bug not in the original 106 findings — `story decompose`'s auto-created parent story
permanently deadlocking the `execute → review_validate` transition — was found by a live dry-run
and fixed. A final end-to-end acceptance pass (live pipeline dry-run through all 9 execute-loop
mechanics, exhaustive storyhook CLI exercise, alignment/regression-guard checks) confirmed no
regressions across the full stack of changes.

**No mid-task work is pending.** What follows is intentionally-deferred or genuinely-open
follow-up — read this section before starting anything new so you don't duplicate a decision
that was already made deliberately.

## Deliberately deferred (not oversights)

1. **tmux watchdog/supervisor** (findings F044/F104) — inverting control so a scripted supervisor
   drives `/forge` transitions instead of the LLM re-deriving `forge-state.sh`'s output every turn.
   [mikeydotio/agentics#33](https://github.com/mikeydotio/agentics/issues/33) was picked up
   2026-07-03: a design spike (3 independent architecture proposals, adversarial safety/complexity/
   operational review) concluded the supervisor — and the issue's own originally-proposed "Level
   1.5" synchronous helper — are **not** worth building yet. WS6 already delivers confirmed/audited
   sends; the remaining gap is the router's *classification* judgment (fix_loop's mandatory archive
   call, the three human-gate states), and a bash reimplementation of that judgment would be a
   second source of truth for the exact drift class `forge-contract-check.sh` exists to catch.
   Shipped instead: `forge-state.sh --record-transition` (emits `category`/`auto_advance`/
   `transition_id`), `forge-step-exit.sh --transition-id`, and `forge-transition-report.sh` —
   pure telemetry, correlated by id (not log position) so a stalled/crashed session degrades to a
   visible orphan count instead of corrupting the data. Full design doc + adversarial review:
   [agentics#33 comment](https://github.com/mikeydotio/agentics/issues/33#issuecomment-4879731013).
   Re-scoped, not closed — revisit only once `transitions.log` data actually shows category-1
   overhead is non-trivial, a real predicted/actual mismatch appears, or orphaned-predicted counts
   are persistently nonzero. Until then, no further action needed here.

2. **Pane-option state migration** (finding F046) — replacing `.freshen/.clear-pending` with a
   tmux pane option. WS6 judged the cost/benefit had shifted since the plan was written: WS7's
   `.clear-consumed` freshness-window fix already substantially closes the "orphaned flag" concern
   that motivated F046, and a migration would mean re-touching twice-adversarially-verified
   circuit-breaker safety logic for a shrinking benefit. Full reasoning in
   `plugins/forge/references/auto-resume.md`'s "Pane-Option Migration (F046) — Deferred" section.
   If you revisit this, you **must** update `plugins/hook-guard/hooks/session-start.sh` in lockstep
   and re-run `plugins/hook-guard/hooks/session-start.bats` in full (it has the exact regression
   scenarios that took two rounds to get right).

## Genuinely open follow-up

None remaining. Finding F074's storyhook-side half (`post-git.sh`'s per-invocation `python3`
spawn) was fixed in [storyhook#11](https://github.com/mikeydotio/storyhook/pull/11) — a cheap
substring pre-filter now skips the interpreter spawn for the vast majority of Bash calls that
aren't git-related. `session-start.sh`'s sed-based cwd parse was investigated and left
**intentionally** unchanged: `tests/session_start_hook.rs` has explicit tests
(`hook_script_does_not_use_python3`, `hook_script_is_under_20_functional_lines`) encoding a
deliberate design constraint that hook must satisfy — introducing python3 there broke both tests.
Not a bug; [storyhook#10](https://github.com/mikeydotio/storyhook/issues/10) is closed.

## Where to look for context

- The full plan: `~/.claude/plans/idempotent-jingling-pine.md` (self-contained, includes repo
  orientation and ground rules — read this before touching forge or storyhook).
- Per-finding evidence: `~/Enderchest/agentics-harness-audit/findings-data.json` (indexed by
  finding ID, e.g. `F009`).
- `plugins/forge/bin/forge-contract-check.sh` and `forge-agent-alignment-check.sh` are the
  regression guards that keep this hardening from silently rotting — they run under `make test`.
