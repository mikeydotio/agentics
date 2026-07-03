# Handoff — forge × storyhook hardening effort

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
   Scoped as a design spike, tracked at
   [mikeydotio/agentics#33](https://github.com/mikeydotio/agentics/issues/33). Do the read-back
   verification and pane-option pieces first if you pick this up — they're smaller and safer.

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
