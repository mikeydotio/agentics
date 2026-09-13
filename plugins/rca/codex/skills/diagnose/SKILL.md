---
name: diagnose
description: RCA step 4 — form ≥2 competing defect→infection→failure hypotheses, falsify them with controlled worktree experiments, survive the challenger, classify per ODC, and rule surgical-vs-redesign. Produces the verified DIAGNOSIS.md.
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

# RCA Diagnose — Hypotheses, Falsification, Verdict

## Resolve runtime first

Walk four directories upward from this file path (three above its containing directory)
to resolve `<plugin-root>`. Read `<plugin-root>/codex/references/runtime.md` completely
before this step. It defines native questions, authorization, agent dispatch, reference
selection, and verification of write boundaries. Substitute absolute paths; do not rely
on environment variables being expanded by the host.


The core reasoning step. Read `<plugin-root>/codex/references/hypothesis-falsification.md`,
`<plugin-root>/references/odc-classification.md`, and keep
`<plugin-root>/references/symptom-vs-root-cause.md` +
`<plugin-root>/references/architectural-patterns.md` at hand for pattern matching.
Worktree rules: `<plugin-root>/codex/references/worktree-protocol.md`.

**Gate check**: `REPRO.md` or `OVERRIDE.md` must exist (else route to `reproduce`). Inputs:
GRID.md, REPRO.md/OVERRIDE.md, ORIGIN.md (FULL) or nothing yet (LIGHT), meta.json. Outputs:
`EVIDENCE.md`, `HYPOTHESES.md`, `experiments/exp-N.md`, `CHALLENGE.md`, and `DIAGNOSIS.md` or
`INCONCLUSIVE.md`.

## 1. LIGHT tier: slim inline forensics

No ORIGIN.md on LIGHT — run the two cheapest forensics inline on the implicated lines and
save under `forensics/`:
```bash
bash "<plugin-root>/bin/rca-forensics.sh" blame --file <f> --lines <a>,<b>
bash "<plugin-root>/bin/rca-forensics.sh" pickaxe --term <symbol>
```

## 2. Evidence sweep (evidence-collector)

Spawn the shared **evidence-collector** (use native `spawn_agent` for evidence-collector per runtime.md
— read-only, verified per runtime.md; prompt = `<plugin-root>/agent-overrides/evidence-collector-context.md`
["diagnose sweep" section] + GRID.md + REPRO.md + ORIGIN.md/forensics). Targeted questions
from the grid's distinctions — error handling in the failure path, test coverage gaps, sibling
patterns that work, environmental dependencies. Facts only. You write `EVIDENCE.md` from its
report.

## 3. Form competing hypotheses

Per hypothesis-falsification.md: **≥2**, each a full `defect → infection → failure` chain
seeded from distinctions, ORIGIN facts, evidence, and architectural-pattern matches. Run the
AND-condition check explicitly. Write `HYPOTHESES.md`: per hypothesis — statement, chain,
evidence for/against, the falsification experiment design (prediction first, one variable,
discriminating), rank.

## 4. Falsification experiments (experimenter, in the worktree)

For each experiment that must mutate code:
1. Ensure the worktree: `bash "<plugin-root>/bin/rca-worktree.sh" status <slug>`, create
   with `--copy <repro-test>` if absent (per worktree-protocol.md).
2. Spawn the shared **experimenter** (use native `spawn_agent` for experimenter per runtime.md; prompt =
   `<plugin-root>/agent-overrides/experimenter-context.md` + the experiment brief:
   hypothesis verbatim, pre-stated prediction, the worktree path as THE designated workspace,
   the repro command). One experiment per spawn. The toggle gold standard where possible:
   baseline fail → intervene → pass → revert → fail again.
3. **After EVERY experimenter return**: `git status --porcelain` in the MAIN tree — anything
   beyond `.rca/`, known new test files, and the scaffold's `.gitignore` change is a
   violation: halt and preserve diagnostics and pre-existing work per runtime.md.
   Otherwise persist its record as
   `experiments/exp-N.md`.

Cheaper rungs (predicted-evidence lookups, input-family probes) run without the worktree —
you or evidence-collector handle those; still record each as an exp-N.md.

## 5. Challenge

Spawn the shared **hypothesis-challenger** (use native `spawn_agent` for hypothesis-challenger per runtime.md — read-only; prompt =
`<plugin-root>/agent-overrides/hypothesis-challenger-context.md` + the surviving
hypothesis + HYPOTHESES.md + all experiment records). It attacks the hypothesis AND the
experiment designs. Write `CHALLENGE.md` from its report. Outcomes per
hypothesis-falsification.md: VERIFIED → proceed; REFUTED → next hypothesis (back to step 4);
DEEPER CAUSE → extend the chain and re-verify the new link; all refuted + no new hypotheses →
write `INCONCLUSIVE.md` (every hypothesis + refuting evidence + what would discriminate) and
exit honestly.

## 6. Classify and rule

ODC classification (type, qualifier, trigger) per odc-classification.md, then the verdict
rubric: ODC map + hotspot rank + repeat-offender + blast-radius sketch + reversibility ⇒
**SURGICAL** or **REDESIGN** (redesign = narrow patch now + logged deliberate-prudent debt +
escalation as separate scoped work; never inlined).

Write `DIAGNOSIS.md` (required contents per hypothesis-falsification.md, including confidence
with reason and any override degraded-confidence note).

## 7. Exit

Destroy the worktree unless the user wants it kept for fix reference:
`bash "<plugin-root>/bin/rca-worktree.sh" destroy <slug>` (default: destroy — no
question; keep only if the user asked). Summarize: root cause in one sentence, confidence,
verdict + why. Next: `report` (`$rca continue <slug>` if standalone). State is durable; safe to start a fresh session.
