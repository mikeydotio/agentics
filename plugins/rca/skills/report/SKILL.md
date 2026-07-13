---
name: report
description: RCA step 5 — turn the verified diagnosis into durable REPORT.md + REMEDIATION.md via the software-architect, post findings to the latched issue, and run the caller gate: proceed to the fix, or hand off.
argument-hint: "[slug]"
---

# RCA Report — Remediation Design & the Caller Gate

Read `${CLAUDE_PLUGIN_ROOT}/references/symptom-vs-root-cause.md` (the fix-quality checks run
here) and `${CLAUDE_PLUGIN_ROOT}/references/issue-latching.md` (comment mechanics).

**Gate check**: `DIAGNOSIS.md` must exist (else route back to `diagnose`; `INCONCLUSIVE.md`
present → this step does not run). Inputs: all artifacts. Outputs: `REPORT.md`,
`REMEDIATION.md`, `APPROVAL.md`, optionally `HANDOFF.md` + an issue comment.

## 1. Remediation design (software-architect)

Spawn the shared **software-architect** (prefer `subagent_type: "agents:software-architect"`
— read-only, enforced; prompt = `${CLAUDE_PLUGIN_ROOT}/agent-overrides/software-architect-context.md`
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
summary). Then ONE AskUserQuestion — "Root cause diagnosed. How should we proceed?":
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
Standalone: `/rca continue <slug>`. Safe to `/clear`.
