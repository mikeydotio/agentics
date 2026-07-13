# Symptom vs Root Cause Heuristics

How to tell if you've found the real root cause or are still looking at a symptom. These
heuristics run at two points: against the verified cause in `diagnose`, and against the
proposed diff in `fix` before commit. They pair with `odc-classification.md` — a fix that
fails these checks usually means the ODC classification was made against the symptom (the
encounter point) instead of the defect (the origin).

## The Core Question

> "If I fix this, will it prevent the bug from recurring — AND prevent similar bugs?"

If the answer is "it prevents this specific bug but not similar ones," you probably have a symptom, not a root cause.

## Symptom Indicators

You're looking at a **symptom** if:

1. **The fix adds a defensive check.** Adding a null check, try/catch, or default value? You're protecting against a bad state without explaining WHY the bad state occurs.

2. **The fix is specific to one input/case.** If your fix only handles the exact scenario reported, the underlying vulnerability remains for other inputs.

3. **The fix requires careful ordering.** If the fix only works when operations happen in a specific order, you're encoding a temporal coupling — not fixing the design.

4. **The fix adds complexity.** Root cause fixes usually SIMPLIFY code by removing a flawed assumption. If the fix adds significant new logic, question whether it's the right fix.

5. **Someone says "just add a check for that."** The most common symptom-masking phrase in software development.

6. **The fix is in error handling code.** If you're changing how errors are caught/handled/reported rather than preventing the error, you're treating the symptom.

7. **You need multiple coordinated changes.** A real root cause fix is usually localized. If the fix requires changes across many files, you might be papering over a design flaw.

## Root Cause Indicators

You're looking at the **root cause** if:

1. **The fix addresses a structural issue.** It corrects a flawed abstraction, missing invariant, or broken contract between components.

2. **The fix prevents multiple symptoms.** A good root cause fix eliminates not just the reported bug but other latent bugs that haven't manifested yet.

3. **The fix removes code or simplifies logic.** Root cause fixes often simplify because they remove the flawed assumption that required complex workarounds.

4. **The fix makes an invariant explicit.** Adding a type constraint, validation at a boundary, or contract enforcement is structural.

5. **The fix is generalizable.** It teaches a lesson about the architecture that applies beyond this specific bug.

6. **Existing tests don't need modification.** If the fix causes existing tests to fail, those tests might have been encoding wrong behavior — but if ALL tests pass, the fix likely corrects something that was already supposed to be true.

7. **The fix is in the component that CREATES the bad state, not the component that ENCOUNTERS it.** Following the data upstream to where correctness breaks is finding the root cause.

## Common Traps

### The "Race Condition" Trap
"It's a race condition" is often a symptom diagnosis. The root cause question is: "Why is there shared mutable state that requires synchronization?" or "Why do these operations have temporal coupling?"

### The "Missing Validation" Trap
"We need to add input validation" is sometimes the root cause (validation at a trust boundary IS structural) but often a symptom. Ask: "Why is invalid data reaching this point? Who should have validated it and didn't?" In ODC terms this is the difference between a *Checking/Missing* defect at the boundary that owns the data (structural — fix there) and scattering guards at every encounter point (symptom masking).

### The "Configuration" Trap
"The config was wrong" is almost never the root cause. Ask: "Why did wrong config cause silent failure instead of loud failure?" and "Why is the system sensitive to this config value?"

### The "Dependency" Trap
"The library has a bug" might be true but is rarely the root cause. Ask: "Why is our system vulnerable to this library behavior? Is our usage correct? Should we have a defensive boundary?"

## Verification Tests

Apply these tests to your proposed root cause:

| Test | Question | Pass Criteria |
|------|----------|---------------|
| **Prevention** | Would this fix prevent the same bug category? | Prevents similar bugs, not just this instance |
| **Simplification** | Does the fix simplify or complicate the code? | Simplifies or keeps same complexity |
| **Invariant** | Does the fix establish or strengthen an invariant? | Makes a correctness rule explicit |
| **Locality** | Is the fix localized or spread across many files? | Primarily in one component |
| **Upstream** | Is the fix where the bad state ORIGINATES or where it's ENCOUNTERED? | At the origin |
| **Explanation** | Can you explain WHY this was wrong, not just WHAT was wrong? | Clear structural explanation |

Two ODC cross-checks on the Locality test: a genuinely non-local fix (coordinated edits across
modules — shotgun surgery) is a REDESIGN signal for the verdict rubric, not a license to
scatter patches; and an *Interface/Timing* classification legitimately touches both sides of
one boundary without failing Locality — the unit of locality is the contract, not the file.
