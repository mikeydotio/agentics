---
name: validate
description: Test hardening — run tests, find coverage gaps, write missing tests. Produces VALIDATE-REPORT.md with findings by severity. Runs in parallel with review.
argument-hint: ""
---

# Validate: Test Hardening

You are the validate skill. Your job is to harden the test suite — run tests, find coverage gaps, write missing tests, and verify that the implementation meets requirements. You run in parallel with the review skill — both produce reports consumed by triage.

**Read inputs:**
- `.pilot/IDEA.md` (required — requirements to verify)
- `.pilot/PLAN.md` (required — acceptance criteria per task)
- `.pilot/DESIGN.md` (required — component boundaries for integration tests)
- `.pilot/handoffs/handoff-execute.md` (for test state and patterns)

**New reference (read before starting):**
- `references/severity-levels.md` — Finding severity definitions
- `references/report-format.md` — Report structure with solution options

## Steps

### 1. Spawn Validation Agents

**Always spawn:**
- `validator` — Primary test analysis and writing agent
- `qa-engineer` — Test strategy review and edge case identification

Both agents receive IDEA.md, PLAN.md, DESIGN.md, and the execute handoff.

### 2. Run Test Suite

The validator runs the full test suite first to establish baseline:

```bash
# Auto-detect test command
npm test / pytest / cargo test / make test / etc.
```

Record: total, pass, fail, skip, duration.

### 3. Coverage Analysis

The validator and qa-engineer independently assess:
- Which IDEA.md requirements have test coverage
- Which components have unit tests
- Which integration boundaries are tested
- Which error handling paths are exercised
- Which edge cases are covered

### 4. Write Missing Tests

The validator writes tests for critical gaps found during analysis:
- Use the project's existing test framework and patterns
- Focus on behavior tests, not implementation detail tests
- All written tests must pass

### 5. Synthesize VALIDATE-REPORT.md

```markdown
# Validation Report

## Test Suite Results
- Total: X | Pass: Y | Fail: Z | Skip: W
- Run command: [command]
- Duration: [time]

## Findings

### [Finding Title]
- **Severity**: Critical | Important | Useful
- **Description**: [what's missing or broken]
- **Option 1 (Recommended)**: [solution] — Pros: ... Cons: ...
- **Option 2**: [solution] — Pros: ... Cons: ...
- **Option 3**: [solution] — Pros: ... Cons: ...

[Repeat for each finding]

## Requirement Coverage
| Requirement | Tested? | Test Location | Notes |
|------------|---------|---------------|-------|
| [from IDEA.md] | YES/NO | [file:test_name] | [gaps] |

## Tests Written This Step
- [test file]: [what it tests, why it was missing]

## Strengths
[Good testing patterns to reinforce]
```

**Finding severity levels:**
- **Critical**: Meaningful risk to system/data security/integrity (untested critical path, failing tests)
- **Important**: Usability issues that tests should catch
- **Useful**: Nothing broken but tests would improve confidence

## Exit

**If `--orchestrated`:** Follow the Step Exit Protocol:
1. Write `.pilot/VALIDATE-REPORT.md`
2. Commit any new tests: `git add -A && git commit -m "pilot(validate): test hardening + report"`
3. Write `.pilot/handoffs/handoff-validate.md` with:
   - Key Decisions: test results, coverage gaps
   - Context for Next Step: report summary for triage
4. **If review is also complete** (check for `.pilot/REVIEW-REPORT.md`): queue freshen
5. **If review is not yet complete**: STOP without queuing freshen
6. STOP

**Note:** Same parallel coordination as review — see review skill for details.

**If standalone:** Write report, commit tests, report findings to user, exit.
