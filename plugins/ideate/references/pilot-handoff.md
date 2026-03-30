# Work Handoff

How ideate's PLAN.md maps to pilot's storyhook-based execution, and what makes a plan pilot-ready.

## PLAN.md → Storyhook Stories

Work decomposes PLAN.md waves into individual storyhook stories:

| PLAN.md Element | Storyhook Equivalent |
|----------------|---------------------|
| Wave | Story group with shared dependencies |
| Task | Individual story |
| Task acceptance criteria | Story comment (machine-evaluable) |
| Wave dependencies | `story HP-X precedes HP-Y` relationships |
| Wave priority | Story priority (wave 1=high, 2=medium, 3+=low) |

## Acceptance Criteria Format

**Critical**: Work's evaluator agent needs **machine-evaluable** criteria. The evaluator checks each criterion individually and must cite specific code evidence.

### Good (Machine-Evaluable)
- "Config loads from YAML file and returns typed object"
- "Server starts on configured port and responds to GET /health with 200"
- "Error responses include JSON body with `error` and `message` fields"
- "Unit tests exist for all public functions with >80% line coverage"

### Bad (Subjective / Vague)
- "Config module works correctly" — what does "correctly" mean?
- "Good error handling" — what counts as "good"?
- "Clean code" — unmeasurable
- "Well-tested" — no specific threshold

### Pattern
Each criterion should answer: "What specific, observable behavior can the evaluator check in the code diff?"

## Task Sizing

Each story should be completable in **one generator agent session** (~15-30 minutes of focused implementation). Signs a task is too large:

- More than 3-4 files expected
- Multiple distinct subsystems touched
- Complex integration with unclear boundaries
- Acceptance criteria have more than 5 items

Split large tasks into smaller, independently verifiable stories.

## Wave Structure

Waves should reflect **true dependencies**, not just logical grouping:

- Wave 1: Foundation (types, config, utilities) — no dependencies
- Wave 2: Core features that build on foundation
- Wave 3+: Integration, polish, testing

Within a wave, all tasks are independent and can execute in any order.

## Phase 4.5: Pilot Handoff Gate

After PLAN.md is approved (Phase 4), ideate presents an execution choice:

1. **Check if pilot plugin is installed**: Look for `plugins/pilot/.claude-plugin/plugin.json`
2. If installed, offer via AskUserQuestion:
   - "Autonomous via pilot (you can walk away)"
   - "Execute here (ideate Phase 5)"
   - "Just the plan — I'll execute manually"
3. If "Autonomous via pilot":
   - Invoke `/pilot plan` with `.planning/PLAN.md`
   - Report story count and dependency structure
   - Ask: "Start autonomous execution now?"
   - If yes → `/pilot run`

If pilot is NOT installed, skip the autonomous option — only offer Phase 5 execution or manual.
