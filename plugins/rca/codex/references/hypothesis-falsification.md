# Hypothesis Formation & Falsification

Zeller's scientific debugging, operationalized. Vocabulary first — it keeps the causal chain
honest:

- **Defect** — the incorrect code.
- **Infection** — incorrect program state the defect causes at runtime.
- **Failure** — the observable symptom (what the grid's WHAT-IS records).

Diagnosis = tracing the infection chain BACKWARDS from failure to defect. Not every defect
infects on every run, and not every infection reaches a failure (coincidental correctness) —
which is why "it passes now" never proves "it's fixed".

## Forming hypotheses

- **Always ≥2 competing hypotheses.** One hypothesis is an anchor, not an analysis —
  confirmation bias in debugging is documented and severe; competing explanations are the
  antidote. Write each as a full chain: `defect at <file:line-range> → infection <what state
  goes wrong> → failure <the observed symptom>`.
- Seed from: the grid's Distinctions (sharpest first), ORIGIN.md's culprit/candidates, the
  evidence sweep, and `architectural-patterns.md` pattern matches.
- **AND-condition check** (single-cause-bias guardrail): ask whether the failure needs ALL of
  several conditions together (AND ⇒ typical for concurrency/environment bugs — the hypothesis
  must name every leg) or ANY of several triggers (OR ⇒ multiple entry points — the fix scope
  widens). A linear why-chain silently assumes away AND-causes; check explicitly.
- Why-chain stop rule: stop at a cause that is **actionable and structural** — not at a fixed
  depth, and never at "someone made a mistake" (blameless: ask what allowed the mistake).

## Falsification experiments

Every hypothesis gets an experiment designed to REFUTE it, run by `experimenter` via runtime.md in the
disposable worktree (never the main tree):

1. **Prediction first.** Before any intervention: "if H1 is true, then <specific observable>;
   if false, then <specific observable>". Written into the brief; unambiguous pass/fail.
2. **One variable.** One minimal intervention per experiment.
3. **The toggle gold standard.** The strongest proof: flip the hypothesized cause and watch
   the failure follow — baseline (repro fails) → intervene at the hypothesized defect → repro
   passes → REVERT → repro fails again. Both directions, or it's correlation.
4. **Discrimination.** A good experiment separates the competing hypotheses — if H1 and H2
   predict the same observation, the experiment decides nothing; redesign it.
5. Cheaper rungs when a toggle is impossible: predicted-evidence lookup (H predicts a specific
   log line/state — go look), instrumentation runs (print/assert at the hypothesized infection
   point), input-family probes (H predicts which sibling inputs also fail — try them).

Each experiment is persisted as `experiments/exp-N.md` (the experimenter's structured record:
hypothesis, prediction, intervention diff, procedure, raw result, SUPPORTED/REFUTED/
INCONCLUSIVE, confounds).

## Challenge and verdicts

The surviving hypothesis goes to `hypothesis-challenger` via runtime.md — including its experiment-
design review (predictions pre-stated? single-variable? discriminating? toggled both ways?).
Outcomes:

- **VERIFIED** — chain traceable in code, toggle-grade or convergent multi-line evidence,
  survives challenge → DIAGNOSIS.md.
- **REFUTED** — promote the next hypothesis; if none remain, generate new ones from the
  accumulated evidence before giving up.
- **DEEPER CAUSE** — the challenge exposes a cause beneath the proposed one: extend the chain,
  re-verify the new link. The bisect culprit that merely *exposed* a latent defect is the
  classic case.
- **All refuted, no new hypotheses generatable** → write `INCONCLUSIVE.md`: every hypothesis
  + why refuted, what additional evidence would discriminate (runtime traces, more repro data,
  a different angle), and stop honestly. An honest INCONCLUSIVE beats a confident guess.

## DIAGNOSIS.md must contain

Root cause (one sentence); the verified chain with per-link evidence (file:line, experiment
number, or SHA); eliminated alternatives (hypothesis → refuting evidence); ODC classification
(see `odc-classification.md`); fix-strategy verdict + inputs; confidence HIGH/MED/LOW with the
reason (toggle-verified ⇒ HIGH; observational-only ⇒ cap at MED and say why); any override
degraded-confidence note carried forward.
