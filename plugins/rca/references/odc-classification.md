# ODC Classification & the Fix-Strategy Verdict

IBM's Orthogonal Defect Classification, adapted: classify the *verified* defect (never the
symptom), then let the classification — plus deterministic history signals — drive the
surgical-vs-redesign verdict. Classification happens in `diagnose`, after verification.

## Defect Type (⇒ inherent fix scope)

| Type | The defect is… | Inherent scope |
|---|---|---|
| **Assignment/Init** | a value assigned wrongly or not initialized | few lines — smallest |
| **Checking** | missing/incorrect validation of data or a condition | small, localized |
| **Algorithm** | wrong local logic/data structure, fixable without design change | one function/unit |
| **Function/Class** | a capability or major abstraction is wrong/missing — needs a design change | **design-level** |
| **Interface** | wrong interaction between components (params, messages, API contract) | the boundary + both sides |
| **Timing/Serialization** | missing/incorrect coordination of shared resources (races, ordering) | the coordination design |
| **Relationship** | associations among procedures/objects not properly considered | often design-level |
| **Build/Package/Merge** | build system, versioning, merge damage — not source logic | the build/config layer |

## Qualifier

**Missing** (should exist, doesn't) · **Incorrect** (exists, wrong) · **Extraneous** (exists,
shouldn't). *Missing* skews design-linked: nothing in the design owned the rule. An Incorrect
Assignment is a typo; a Missing Checking at a trust boundary is an unowned invariant.

## Trigger (⇒ which regression tests to add)

What surfaced it: boundary condition · workload/stress · recovery/error path · startup/restart
· configuration · concurrency · unusual input/data. The trigger names the test family the fix
must add beyond the repro itself — a concurrency-triggered defect fixed with only a
happy-path regression test will recur.

## The verdict rubric

Compute each input, then rule:

| Input | Source | Redesign signal when… |
|---|---|---|
| ODC type + qualifier | DIAGNOSIS.md | Function/Relationship, or Missing at a boundary; Interface/Timing ⇒ at least contract-level work |
| Hotspot rank | ORIGIN.md (`rca-hotspots.sh`) | implicated file in the top ranks |
| Repeat offender | ORIGIN.md (prior fix commits touching the same area) | ≥2 prior fixes to the same logic — the module, not the line, is the problem |
| Blast radius | architect's fix sketch | a *correct* fix needs coordinated edits across modules (shotgun surgery ⇒ coupling flaw) |
| Reversibility | judgment | a wrong surgical fix would be cheap to revert ⇒ tolerates SURGICAL; expensive/data-corrupting ⇒ favors doing it right now |

- **SURGICAL** — Assignment/Checking/Algorithm + Incorrect + low blast radius + not a repeat
  offender. Patch precisely, add trigger-derived tests, done.
- **REDESIGN** — the signals above point at the design. **Never inline the redesign into the
  bug fix** (reverse scope creep). The fix step still lands the narrow corrective patch — with
  the flaw explicitly logged — and the redesign is escalated as separate scoped work: an issue
  on the latched tracker (or offer `/issue new`), carrying the DIAGNOSIS.md evidence.

Both verdicts are recommendations; the user ratifies at the report gate.

## The tech-debt log (deliberate & prudent)

Knowingly patching over a design flaw is legitimate ONLY when the debt is explicit (Fowler's
technical-debt quadrant: deliberate-prudent). The log entry (in REMEDIATION.md and the
escalation issue): the flaw, why patched now, what the patch does NOT protect against, and the
condition that should trigger the redesign. An unlogged known flaw is reckless debt.

## Type ⇒ verification extras

- **Interface/Timing** ⇒ sibling sweep is mandatory-strict: every other consumer of the same
  contract/resource gets checked for the same misuse (the fix step's sweep signature comes
  from this classification).
- **Missing** qualifier ⇒ the fix should make the invariant explicit (type constraint,
  boundary validation, assertion) — not just supply the missing check at the crash site (see
  `symptom-vs-root-cause.md`: origin vs encounter point).
- **Build/Package/Merge** ⇒ check merge history (`rca-forensics.sh timeline`) for damaged
  conflict resolutions; the fix may be a re-merge, not a code edit.
