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

**The evaluator's output schema is defined exactly once — in
`plugins/agents/agents/evaluator.md`'s "Output Format" section.** Read that section for the full
JSON shape (`verdict`, `failures[]`, `criteria_checks[]`, `edge_case_findings[]`,
`security_findings[]`, `design_adherence`) and the `failures[]` fold-in transform. This checklist
(above) is what the evaluator applies per-criterion; each unmet check becomes one
`criteria_checks` entry with `status: "fail"`, which the transform then copies into `failures[]`
with `category: "criteria"`.

Do not redefine the schema here or anywhere else — if this section and `evaluator.md` ever
disagree, `evaluator.md` is authoritative and this section is stale.

## Structured Feedback for Retries

When the evaluator fails a story, the COMPACT projection of the schema above (`{"verdict":
"fail", "failures": [...]}` — see `evaluator.md`'s "Storage split") is stored as a storyhook
comment:

```bash
story comment HP-N '{"verdict":"fail","failures":[...]}'
```

The full verdict object (including `criteria_checks`, `edge_case_findings`, `security_findings`,
`design_adherence`) is logged separately to `.forge/verdicts.jsonl`, not truncated to fit the
storyhook comment. On retry, the generator receives the compact form's structured fields — never
raw freeform text. This prevents prompt injection via the evaluator-to-generator feedback path.

