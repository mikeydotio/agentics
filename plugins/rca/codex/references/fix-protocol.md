# Fix Protocol

Gated implementation of an approved remediation. The skill enforces every gate between agent
turns — the implementer implements; the gates are not its to skip. Two-hats discipline
throughout (Fowler): the behavior-changing fix and any refactor are SEPARATE commits, so a
future bisect can attribute regressions cleanly.

## Gate sequence

1. **Branch guard.** `git branch --show-current`; on the default branch, create
   `rca-fix/<slug>` first. Never commit to main. (If the user was already on a feature branch,
   stay on it and say so.)
2. **RED.** `rca-repro.sh run --cmd "<repro cmd>" --runs 1` → must still FAIL. A passing repro
   here means the tree drifted since diagnosis — stop and re-orient; fixing an already-passing
   test proves nothing.
3. **Implement — hat #1.** Spawn `software-engineer` via runtime.md briefed with DIAGNOSIS.md +
   REMEDIATION.md: behavior fix only, minimal diff, at the ORIGIN of the bad state (not the
   encounter point), no drive-by refactors, no formatting churn, honor the verdict (a SURGICAL
   verdict does not license restructuring; a REDESIGN verdict still means the narrow patch —
   the redesign is separate escalated work).
4. **GREEN.** Repro test passes (`--runs 1`; for a formerly-flaky repro, `--runs 20` and
   failure_rate 0.0).
5. **FULL SUITE.** The stack's `test_cmd` fully green. A fix that breaks other tests is either
   wrong or has discovered tests encoding the broken behavior — in the latter case those test
   changes belong in the fix commit with justification in the message.
6. **Commit hat #1.** `fix:` conventional commit — what was wrong (defect), how it manifested
   (failure), why this is the origin, issue ref if latched. Include the repro test + any new
   trigger-derived tests in this commit (they document the defect).
7. **Sibling-pattern sweep** (fix-it-everywhere). Derive a search signature from the ODC
   classification + the defect's shape (the pickaxe term, the misused API, the pattern the
   experimenter toggled). Spawn `evidence-collector` via runtime.md to find other occurrences.
   - In-scope siblings (same defect, clearly wrong): fix + test in the same spawn, appended to
     the fix commit or a follow-up `fix:` commit.
   - Ambiguous/out-of-scope: follow-up issues on the tracker, listed in FIX.md. Never let the
     sweep balloon the fix.
8. **Hat #2 (optional).** Only if REMEDIATION.md explicitly calls for a refactor now: separate
   `refactor:` commit(s), full suite green again after. Verify separation:
   `git log --oneline` shows fix and refactor as distinct commits; the fix commit alone makes
   the repro pass.
9. **Handback.** Push/PR is the user's. Report: branch, commit SHAs, gate evidence, suggested
   PR body (diagnosis summary + fix rationale + test evidence).

## FIX.md

Records, with command output excerpts: RED evidence (pre-fix failure tail), the diff summary,
GREEN evidence, full-suite result, sweep findings + dispositions, commit SHAs per hat, and
anything the fix deliberately does NOT address (pointing at the tech-debt log / escalation
issue).

## Anti-patterns the skill rejects

- **Symptom masking** — try/catch, retry, default value, or null guard at the encounter point
  without addressing why the bad state exists (`symptom-vs-root-cause.md` heuristics run
  against the diff before commit).
- **Test weakening** — loosening an assertion to get GREEN.
- **Scope creep** — refactors smuggled into hat #1; redesigns smuggled into hat #2.
- **Suite skips** — committing with the full suite red or tests skipped-to-pass.
- RCA never runs `/semver bump` or any deploy step — versioning/deployment are the user's,
  from main, later.
