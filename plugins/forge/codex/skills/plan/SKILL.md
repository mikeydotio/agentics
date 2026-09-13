---
name: plan
description: Task breakdown into waves with acceptance criteria. Produces PLAN.md. Spawns project-manager, qa-engineer, and skeptic agents.
---

Resolve `<plugin-root>` three directories above this loaded file's containing directory.
Read `<plugin-root>/codex/references/runtime.md` before this step.

<!-- AGE-104 DELIVERY BEGIN -->
Read `<plugin-root>/references/delivery.md` completely before this step, including standalone entry.
The local helper owns all specialist dispatch/wait/retry/cleanup; persist intent before
native dispatch and use the state-derived result envelope. On delivery_recovery, inspect
and recover existing batches before any fresh dispatch, artifact-based advancement or
cleanup. Preserve partial changes and write an incomplete handoff on failure; never
convert delivery failure into an evaluator verdict or a fresh generator retry.
In Plan mode inspect only; do not initialize delivery state or dispatch writers.
<!-- AGE-104 DELIVERY END -->

# Plan: Task Breakdown with Acceptance Criteria

You are the plan skill. Your job is to produce a detailed implementation plan organized into execution waves with testable acceptance criteria for each task.

**Read inputs:**
- `.forge/IDEA.md` (required)
- `.forge/DESIGN.md` (required)
- `.forge/research/SUMMARY.md` (for context)
- `.forge/TEAM.md` (for context)
- `.forge/handoffs/handoff-design.md` (if orchestrated — for context)
- `<plugin-root>/codex/references/team-roles.md` (before spawning — "Resolving canonical role" governs every spawn
  below; none of these agents have a forge override)

**When invoked as part of a FIX loop**, also read:
- `.forge/TRIAGE.md` — for FIX items that need planning
- `.forge/fix-cycles/cycle-N/` — for prior cycle context

## Steps

### 1. Spawn Planning Team

Resolve `canonical role` per `<plugin-root>/codex/references/team-roles.md` for each (load the canonical role and Forge override through runtime.md):

- `project-manager` — Create detailed task breakdown with dependencies, acceptance criteria, resumption points
- `qa-engineer` — Design test strategy covering unit, integration, and production-readiness tests
- `skeptic` — Stress-test the plan: are tasks too large? Missing edge cases? Unrealistic ordering?

Each agent receives IDEA.md, DESIGN.md, and research/SUMMARY.md.

### 2. FIX Loop Context (if applicable)

When invoked from a FIX loop (triage produced FIX items):
- Read the FIX items from `.forge/TRIAGE.md`
- Scope the plan to ONLY the FIX items — not a full re-plan
- Reference the original DESIGN.md and PLAN.md for context
- Create minimal waves to address the FIX items

### 3. Synthesize Plan

The PM produces `.forge/PLAN.md`:

```markdown
# Implementation Plan

## Task Breakdown

### Wave 1 (no dependencies)
- [ ] Task 1.1: [description]
  - Acceptance: [machine-evaluable criterion — what specific, observable behavior can the evaluator check?]
  - Files: [expected files to create/modify]
- [ ] Task 1.2: [description]
  ...

### Wave 2 (depends on Wave 1)
- [ ] Task 2.1: [description]
  - Acceptance: [criterion]
  - Files: [files]
  - Depends on: Task 1.1, Task 1.2
...

## Test Strategy
[QA engineer's test plan integrated into task waves]

## Resumption Points
[After each wave, state is consistent and work can be paused/resumed]

## Risk Register
[Skeptic findings, ranked by impact]
```

### 4. Acceptance Criteria Quality Check

**Critical**: The downstream evaluator agent needs **machine-evaluable** criteria. Check each criterion against this standard:

**Good (Machine-Evaluable):**
- "Config loads from YAML file and returns typed object"
- "Server starts on configured port and responds to GET /health with 200"
- "Error responses include JSON body with `error` and `message` fields"

**Bad (Subjective / Vague):**
- "Config module works correctly"
- "Good error handling"
- "Clean code"

Each criterion should answer: "What specific, observable behavior can the evaluator check in the code diff?"

### 5. Task Sizing Check

Each task should be completable in **one generator agent session** (~15-30 minutes of focused implementation). Signs a task is too large:
- More than 3-4 files expected
- Multiple distinct subsystems touched
- Complex integration with unclear boundaries
- Acceptance criteria have more than 5 items

Split large tasks.

### 6. Present Plan

Present the plan as **plain text**, then use the native question tool:
- **header:** "Plan OK?"
- **question:** "Does this implementation plan look right? Ready to execute?"
- **options:**
  - "Approved — start building (Recommended)" / "Plan is sound, begin execution. Pros: fastest path to working software. Cons: mid-execution changes are more expensive."
  - "Needs adjustment" / "I want to change task scope, ordering, or criteria. Pros: prevents wasted execution cycles. Cons: delays start of implementation."
  - "I have concerns" / "Something about the approach worries me. Pros: catches strategic issues before code is written. Cons: may require re-engaging the planning team."

If "Needs adjustment" — ask what to change, revise, re-present.

## Exit

**If `--orchestrated`:** Write `.forge/PLAN.md`, then follow the Step Exit Protocol
(`<plugin-root>/codex/references/step-handoff.md`) — write `handoff-plan.md` (Plan Handoff table) and run:
```bash
bash "<plugin-root>/bin/forge-step-exit.sh" --host codex --step plan \
  --summary "implementation plan approved" --next '$forge:forge decompose --orchestrated'
```

**If standalone:** Write `.forge/PLAN.md`, report completion to user, exit.
