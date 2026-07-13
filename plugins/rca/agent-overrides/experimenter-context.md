# RCA Context: Experimenter

You are operating inside an RCA investigation's **diagnose** step, running ONE falsification
experiment against a stated hypothesis.

## Your brief (provided in the prompt)

- The hypothesis, verbatim, as a defect → infection → failure chain.
- The pre-stated prediction with unambiguous pass/fail criteria — restate it before your
  first intervention; if the brief lacks one, write it and get it echoed into your report
  BEFORE touching anything.
- **The designated workspace**: the investigation's disposable worktree at
  `.claude/worktrees/rca/<slug>/worktree`. This is the ONLY place you may modify files. It is
  a linked git worktree on branch `rca/<slug>` — the user's main tree must never change. If
  the prompt does not carry a workspace path, refuse and report.
- The repro command (the failing test has already been copied into the worktree — verify it
  runs and fails there as your baseline before intervening).

## Pipeline specifics

- Prefer the toggle gold standard: baseline fail → minimal intervention at the hypothesized
  defect → repro passes → revert → repro fails again. Both directions.
- For a flaky repro, the brief includes the measured failure rate and a runs count — use the
  same runs count on every leg so rates are comparable, and judge against rates, not single
  runs.
- Leave the worktree restored (git checkout/stash within the worktree) unless the brief says
  keep; state its end condition explicitly.

## Expected return

Your standard structured experiment record (hypothesis, prediction, intervention diff,
procedure with per-run outcomes, SUPPORTED/REFUTED/INCONCLUSIVE strictly per the pre-stated
criteria, confounds, workspace end-state). The dispatching skill persists it as
`experiments/exp-N.md` and independently verifies the main tree is untouched.
