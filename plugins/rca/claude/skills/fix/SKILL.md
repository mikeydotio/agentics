---
name: fix
description: RCA step 6 — gated fix implementation. RED (repro still fails) → software-engineer implements the behavior fix → GREEN → full suite → fix: commit → sibling-pattern sweep → optional separate refactor: commit. Two hats, feature branch, push/PR left to the user.
argument-hint: "[slug]"
effort: high
---

<!-- AGE-104 DELIVERY BEGIN -->
Read `${CLAUDE_PLUGIN_ROOT}/references/delivery.md` completely before this step, including standalone entry.
Use the local delivery helper for every specialist dispatch, wait, retry and cleanup.
Persist the full roster and dispatch intent before native calls; retain returned IDs
and require the state-derived delivery envelope. On delivery_recovery, reconcile existing
batches before the artifact ladder, fresh dispatch or worktree/artifact cleanup. Failed
workers produce an incomplete HANDOFF.md and leave this step's gate unsatisfied.
Never retry a writer automatically or replace an independent challenge with self-review.
In Plan mode remain read-only; do not initialize delivery state or dispatch writers.
<!-- AGE-104 DELIVERY END -->

# RCA Fix — Gated Implementation

Read `${CLAUDE_PLUGIN_ROOT}/references/fix-protocol.md` — it is the authority for this step;
this file is its dispatch order. YOU enforce every gate between agent turns.

**Gate checks**: `APPROVAL.md` must record `decision: fix` (else stop: the caller gate was not
passed — route to `report`). `REMEDIATION.md` + `DIAGNOSIS.md` are the brief. This is the
first step allowed to modify production code — on a feature branch only.

## Gate sequence (fix-protocol.md §Gate sequence, enforced in order)

1. **Branch guard** — on the default branch? Create `rca-fix/<slug>` first. Never main.
2. **RED** — `bash ${CLAUDE_PLUGIN_ROOT}/bin/rca-repro.sh run --cmd "<repro cmd>" --runs 1`
   must FAIL. Passing → tree drifted since diagnosis: stop, re-orient (re-run diagnose's
   verification if needed), never "fix" a passing repro.
3. **Implement (hat #1)** — spawn the shared **software-engineer** (prefer `subagent_type:
   "agents:software-engineer"`; prompt = `${CLAUDE_PLUGIN_ROOT}/agent-overrides/software-engineer-context.md`
   + DIAGNOSIS.md + REMEDIATION.md + repro command). Behavior fix only, minimal diff, at the
   origin. On return: `git status --porcelain` — the diff must touch only what REMEDIATION.md
   scopes; drive-by refactors/formatting churn → revert instruction + respawn.
4. **GREEN** — repro passes (`--runs 1`; formerly-flaky repro → `--runs 20`, rate 0.0).
5. **FULL SUITE** — the stack `test_cmd` green. Existing-test failures: either the fix is
   wrong, or those tests encoded the broken behavior — the latter's changes belong in the fix
   commit with justification.
6. **Commit hat #1** — `fix:` conventional commit including the repro test + trigger-derived
   tests; message names the defect and why this is the origin; issue ref if latched.
7. **Sibling sweep** — signature from the ODC classification (per fix-protocol.md); spawn
   **evidence-collector** (`agents:evidence-collector`; prompt = its override's "sibling
   sweep" section + the signature + the fixed diff). In-scope siblings → fixed + tested via
   the same software-engineer pattern (follow-up `fix:` commit); ambiguous → follow-up issues,
   never scope-ballooning.
8. **Hat #2 (only if REMEDIATION.md calls for it)** — separate `refactor:` commit(s), suite
   green after; verify separation (`git log --oneline`: fix and refactor distinct; the fix
   commit alone makes the repro pass).
9. **Handback** — report branch, commit SHAs, gate evidence, suggested PR body. Push/PR is
   the user's. RCA never bumps or deploys.

Before committing, run the symptom-vs-root-cause checks against the final diff — a masking
fix that slipped through design review must not slip through here.

## Output

`FIX.md` per fix-protocol.md (RED evidence, diff summary, GREEN + suite evidence, sweep
dispositions, SHAs per hat, what the fix deliberately does NOT address). Next: `postmortem`
(`/rca continue <slug>` if standalone). Safe to `/clear`.
