---
name: validate
description: Test hardening — run tests, find coverage gaps, write missing tests. Produces VALIDATE-REPORT.md with findings by severity. Runs in parallel with review.
argument-hint: ""
---

# Validate: Test Hardening

You are the validate skill. Your job is to harden the test suite — run tests, find coverage gaps, write missing tests, and verify that the implementation meets requirements. You run in parallel with the review skill — both produce reports consumed by triage.

**Read inputs:**
- `.forge/IDEA.md` (required — requirements to verify)
- `.forge/PLAN.md` (required — acceptance criteria per task)
- `.forge/DESIGN.md` (required — component boundaries for integration tests)
- `.forge/handoffs/handoff-execute.md` (for test state and patterns)

**New reference (read before starting):**
- `references/severity-levels.md` — Finding severity definitions
- `references/report-format.md` — Report structure with solution options
- `references/team-roles.md` — "Resolving subagent_type" governs the spawns below; `validator`
  has a forge override (`agent-overrides/validator-context.md`), `qa-engineer` doesn't

## Steps

### 1. Spawn Validation Agents

Resolve `subagent_type` per `references/team-roles.md` for each (`agents:<name>` preferred;
`general-purpose` + inlined shared definition — plus the override for `validator` — only as
fallback):

**Always spawn:**
- `validator` — Primary test analysis and writing agent. Unlike `reviewer`/`triager`, this agent
  is legitimately `read_only: false` (it writes tests and the report itself) — its override's
  "write to VALIDATE-REPORT.md" instruction is correct as written, no contradiction to resolve here.
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
1. Write `.forge/VALIDATE-REPORT.md`
2. Commit any new tests: `git add -A && git commit -m "forge(validate): test hardening + report"`
3. Write `.forge/handoffs/handoff-validate.md` with:
   - Key Decisions: test results, coverage gaps
   - Context for Next Step: report summary for triage
4. Queue freshen unconditionally: `bash plugins/freshen/bin/freshen.sh queue "/forge continue" --source forge --summary "Validation complete"`
5. STOP

**Note:** Validate never checks for `.forge/REVIEW-REPORT.md` before deciding whether to queue
freshen — that file-presence "whoever finishes second queues" coordination previously deadlocked
the pipeline. See `skills/review/SKILL.md`'s Exit section and `skills/forge/SKILL.md`'s
**Review+Validate Parallel Dispatch** for the full model: `forge-state.sh` decides whether review,
validate, or both still need to run, and the orchestrator dispatches accordingly. This Exit section
applies when validate runs alone (`dispatch: "validate --orchestrated"`, i.e. review's report
already exists).

**If standalone:** Write report, commit tests, report findings to user, exit.
