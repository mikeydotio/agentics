---
name: report
description: RCA step 5 — turn the verified diagnosis into durable REPORT.md + REMEDIATION.md via the software-architect, post findings to the latched issue, and run the caller gate: proceed to the fix, or hand off.
---

<!-- AGE-104 DELIVERY BEGIN -->
Read `<plugin-root>/references/delivery.md` completely before this step, including standalone entry.
Use the local delivery helper for every specialist dispatch, wait, retry and cleanup.
Persist the full roster and dispatch intent before native calls; retain returned IDs
and require the state-derived delivery envelope. On delivery_recovery, reconcile existing
batches before the artifact ladder, fresh dispatch or worktree/artifact cleanup. Failed
workers produce an incomplete HANDOFF.md and leave this step's gate unsatisfied.
Never retry a writer automatically or replace an independent challenge with self-review.
In Plan mode remain read-only; do not initialize delivery state or dispatch writers.
<!-- AGE-104 DELIVERY END -->

# RCA Report — Remediation Design & the Caller Gate

## Resolve runtime first

Walk four directories upward from this file path (three above its containing directory)
to resolve `<plugin-root>`. Read `<plugin-root>/codex/references/runtime.md` completely
before this step. It defines native questions, authorization, agent dispatch, reference
selection, and verification of write boundaries. Substitute absolute paths; do not rely
on environment variables being expanded by the host.


Read `<plugin-root>/references/symptom-vs-root-cause.md` (the fix-quality checks run
here) and `<plugin-root>/codex/references/issue-latching.md` (comment mechanics).

**Gate check**: `DIAGNOSIS.md` must exist (else route back to `diagnose`; `INCONCLUSIVE.md`
present → this step does not run). Inputs: all artifacts. Outputs: `REPORT.md`,
`REMEDIATION.md`, `APPROVAL.md`, optionally `HANDOFF.md` + an issue comment.

## 1. Remediation design (software-architect)

Spawn the shared **software-architect** (use native `spawn_agent` for software-architect per runtime.md
— read-only, verified per runtime.md; prompt = `<plugin-root>/agent-overrides/software-architect-context.md`
+ DIAGNOSIS.md + EVIDENCE.md + ORIGIN.md + the grid). It returns a remediation design honoring
the verdict:
- SURGICAL → the precise corrective change at the origin, trigger-derived regression tests,
  blast radius, alternatives considered.
- REDESIGN → BOTH the narrow patch (with its tech-debt log entry) AND the scoped redesign
  proposal (as separate escalated work, sized and bounded).
- Always: the anti-pattern self-check table, invariants touched, what the fix does NOT do,
  rollback story.

You write `REPORT.md` (investigation narrative: symptom → evidence → verified chain →
classification → verdict, with confidence and any override note) and `REMEDIATION.md` (the
design) from its return.

## 2. Fix-quality checks

Run the symptom-vs-root-cause verification tests against the proposed fix. Any failure
(defensive check at the encounter point, single-case patch, complexity without structure) →
iterate with the architect. Do not present a plan that fails its own checks.

## 3. Post to the latched issue

If latched: post the condensed report comment (root-cause chain, confidence, verdict,
remediation summary) per issue-latching.md; log it in `ISSUE.json`.

## 4. The caller gate

Present the findings as plain text (root cause, chain, confidence, verdict, remediation
summary). Then one native question — "Root cause diagnosed. How should we proceed?":
- **Fix now** — proceed to the `fix` step.
- **Hand off** — write project-root `HANDOFF.md` (<100 lines: diagnosis summary, remediation
  plan pointer, exact repro command, artifact paths, degraded-confidence notes) and ensure the
  issue comment carries the same; implementation happens elsewhere/later.
- **Not convinced** — the pushback is new evidence: capture it, then re-enter `diagnose` with
  it (do not argue; investigate).

Record the decision in `APPROVAL.md` (`decision: fix|handoff`, timestamp, rationale). An
agent caller (rca invoked mid-pipeline by another agent) answers the same gate in its own
words — record verbatim.

## 5. Exit

On `fix` → next step is `fix`. On `handoff` → next is `postmortem` (the diagnosis itself
deserves the durable write-up even when the fix lands later; note "fix pending" status).
Standalone: `$rca continue <slug>`. State is durable; safe to start a fresh session.
