# Kepner-Tregoe IS/IS-NOT Intake

Differential diagnosis for a known defect: specify what the problem IS and — for every
dimension — the nearest comparable case where it IS NOT but plausibly could be. The
*distinctions* between IS and IS-NOT, and any recent *changes* to those distinctions, point at
the cause. This replaces open-ended questioning: the grid tells you exactly which facts are
missing, so only genuine gaps generate questions.

## The grid

| Dimension | IS | IS NOT (nearest comparable) | Distinction | Recent change? |
|-----------|----|-----------------------------|-------------|----------------|
| **WHAT** — object + deviation | What entity fails, and how exactly (error text, wrong value, crash, hang) | What similar entities do NOT fail; what deviations are NOT observed | | |
| **WHERE** — location | Where in the system/UI/code path it occurs; where geographically/environmentally | Where it does NOT occur (other screens, other environments, other installs) | | |
| **WHEN** — timing + pattern | First observed; when in the lifecycle/flow it fires; frequency pattern | When it does NOT occur (before date X, on cold start, on retry) | | |
| **EXTENT** — magnitude + trend | How many cases/users/inputs; how severe; trend (growing, stable, shrinking) | The extent it is NOT (not all users, not every input, never data loss) | | |

## Pre-fill protocol

Fill cells from available sources BEFORE asking anything, tagging each cell:

1. `source: issue` — the latched GitHub/storyhook issue body and comments (highest fidelity for
   WHAT/WHEN; check for repro steps, versions, stack traces).
2. `source: user` — the invocation description and anything said in conversation.
3. `source: inferred` — light read-only recon (error text grepped to a file, a version string,
   a date from git log). Mark confidence `low|med|high`. Inferred cells with low confidence
   count as ambiguous.
4. `source: empty` — nothing known.

## Question generation

- Ask ONLY about `empty` and ambiguous cells — one AskUserQuestion per cell, one question per
  call, options offering the most likely values plus "don't know".
- Order: worst gap first. Priority: WHAT-IS → WHEN-IS (regression signal: "did this ever
  work?") → EXTENT-IS → the IS-NOT cells for whichever dimension already shows a sharp IS.
- Every dimension's IS-NOT matters more than exhaustive IS detail: "works in the simulator,
  fails on device" localizes harder than three more sentences about the failure.
- Stop rule: once WHAT-IS, WHEN-IS, and EXTENT-IS are filled and no cell is both empty and
  load-bearing, offer "enough — proceed to reproduction". Do not interrogate past usefulness.
- "Did this ever work, and when did it last work?" is mandatory — it decides whether the
  defect is a REGRESSION (bisectable: known-good ref exists) or LONGSTANDING (forensics lead
  with pickaxe/blame instead).

## Reading the grid

- **Distinctions column**: for each row, state what is different about the IS side. A sharp
  distinction (fails only for accounts created after 2026-05, only on iOS 26, only when the
  list is empty) is a direct hypothesis seed.
- **Changes column**: what changed at or before the WHEN-IS boundary — deploys, dependency
  bumps, config, data migrations, OS updates. Changes that align with the boundary go straight
  into the forensics target list (`rca-forensics.sh timeline --since <boundary>`).
- Beware the "works on my machine" dismissal: an environment-dependent failure is a WHERE
  distinction to specify, not a reason to close the investigation.

## GRID.md format

First line after the title is a one-sentence summary (rca-status.sh uses it as the listing
summary). Then the table above, fully tagged, then two sections: `## Distinctions` (bulleted,
sharpest first) and `## Aligned changes` (what changed at the WHEN boundary, with evidence
pointers). Classification line at the end: `Regression | Longstanding | Unknown` +
`known_good: <ref or none>`.
