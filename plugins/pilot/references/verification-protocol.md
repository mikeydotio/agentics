# Verification Protocol

The evaluator agent's acceptance criteria checklist and debiasing methodology.

## Core Principle

The evaluator is a "tuned skeptic" — the core of generator-evaluator separation. It assumes code is incorrect until proven otherwise.

## Debiasing Instructions

LLM evaluators are biased toward generosity with LLM-generated code. Counter this with:

1. **Assume incorrect until proven**: Start from the position that the code does NOT satisfy criteria. Look for evidence that it does.
2. **Cite specific evidence**: For each criterion, cite specific lines in the diff. "It looks correct" is NOT evidence.
3. **Check for what is MISSING**: Don't just verify what is present. Actively look for missing error handling, edge cases, validation.
4. **Independent assessment**: Don't explain away problems. If something looks wrong, it probably is.

## Verification Checklist

For each story evaluation, the evaluator must check:

### 1. Acceptance Criteria (per-criterion)
For each acceptance criterion listed in the story:
- [ ] Criterion is satisfied — cite specific code lines as evidence
- [ ] Implementation is complete (no stubs, TODOs, placeholders)
- [ ] No hardcoded returns or fake implementations

### 2. Code Quality
- [ ] No `TODO`, `FIXME`, `HACK`, `XXX` comments in new code
- [ ] No placeholder/stub implementations
- [ ] No hardcoded test values in production code
- [ ] Error handling at system boundaries

### 3. Design Contract
- [ ] Interface contracts from DESIGN.md are honored
- [ ] Naming conventions match existing codebase
- [ ] No architectural violations

### 4. Regression Check
- [ ] No unrelated files modified
- [ ] No existing functionality broken
- [ ] Test suite still passes (verified by deterministic pre-checks)

### 5. Self-Check
- [ ] Files modified by evaluator: 0 (evaluator is read-only)

## Output Format

```json
{
  "verdict": "pass|fail",
  "failures": [
    {
      "criterion": "API returns 404 for missing resources",
      "evidence": "handler at line 42 returns 500 for all errors",
      "suggestion": "Add NotFoundError catch clause before generic error handler"
    }
  ],
  "summary": "Brief overall assessment"
}
```

### Pass Verdict
All criteria satisfied with cited evidence. `failures` array is empty.

### Fail Verdict
One or more criteria not satisfied. Each failure includes:
- `criterion`: Which criterion failed
- `evidence`: What was observed (cite specific lines)
- `suggestion`: Actionable fix suggestion

## Structured Feedback for Retries

When the evaluator fails a story, the structured JSON verdict is stored as a storyhook comment:

```bash
story HP-N '{"verdict":"fail","failures":[...]}'
```

On retry, the generator receives these structured fields — never raw freeform text. This prevents prompt injection via the evaluator-to-generator feedback path.

## Calibration

During canary mode (first N stories), the user reviews evaluator decisions:
- If evaluator is too lenient → tighten criteria in the prompt
- If evaluator is too strict → relax criteria
- Calibration happens at runtime, not through upfront examples
