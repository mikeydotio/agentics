---
name: plan
description: Task breakdown into waves with acceptance criteria. Produces PLAN.md. Spawns project-manager, qa-engineer, and devil's advocate agents.
argument-hint: ""
---

# Plan: Task Breakdown with Acceptance Criteria

You are the plan skill. Your job is to produce a detailed implementation plan organized into execution waves with testable acceptance criteria for each task.

**Read inputs:**
- `.pilot/IDEA.md` (required)
- `.pilot/DESIGN.md` (required)
- `.pilot/research/SUMMARY.md` (for context)
- `.pilot/TEAM.md` (for context)
- `.pilot/handoffs/handoff-design.md` (if orchestrated — for context)

**When invoked as part of a FIX loop**, also read:
- `.pilot/TRIAGE.md` — for FIX items that need planning
- `.pilot/fix-cycles/cycle-N/` — for prior cycle context

## Steps

### 1. Spawn Planning Team

- `project-manager` — Create detailed task breakdown with dependencies, acceptance criteria, resumption points
- `qa-engineer` — Design test strategy covering unit, integration, and production-readiness tests
- `devils-advocate` — Stress-test the plan: are tasks too large? Missing edge cases? Unrealistic ordering?

Each agent receives IDEA.md, DESIGN.md, and research/SUMMARY.md.

### 2. FIX Loop Context (if applicable)

When invoked from a FIX loop (triage produced FIX items):
- Read the FIX items from `.pilot/TRIAGE.md`
- Scope the plan to ONLY the FIX items — not a full re-plan
- Reference the original DESIGN.md and PLAN.md for context
- Create minimal waves to address the FIX items

### 3. Synthesize Plan

The PM produces `.pilot/PLAN.md`:

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
[Devil's advocate findings, ranked by impact]
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

Present the plan as **plain text**, then use AskUserQuestion:
- **header:** "Plan OK?"
- **question:** "Does this implementation plan look right? Ready to execute?"
- **options:** ["Approved — start building", "Needs adjustment", "I have concerns"]

If "Needs adjustment" — ask what to change, revise, re-present.

## Exit

**If `--orchestrated`:** Follow the Step Exit Protocol:
1. Write `.pilot/PLAN.md`
2. Write `.pilot/handoffs/handoff-plan.md` with:
   - Key Decisions: plan approved, wave/task counts, test strategy
   - Context for Next Step: plan structure summary, critical dependencies, risk highlights
   - Pipeline State: fix cycle count (if in FIX loop), yolo mode
   - Open Questions: execution preferences
3. Commit: `git add .pilot/ && git commit -m "pilot(plan): implementation plan approved"`
4. Queue freshen: `bash plugins/freshen/bin/freshen.sh queue "/pilot continue" --source pilot`
5. STOP

**If standalone:** Write `.pilot/PLAN.md`, report completion to user, exit.
