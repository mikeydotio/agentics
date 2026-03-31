# Handoff Format

Specification for the handoff artifact that enables clean session transitions.

## Four Layers

Pilot handoffs use four complementary persistence layers:

| Layer | File | Purpose | Tracked? |
|-------|------|---------|----------|
| Config + State | `.pilot/config.json` + `.pilot/state.json` | Machine-readable settings and runtime state | config: yes, state: no |
| Handoff | `.pilot/handoff.md` | Human-readable session narrative | No (ephemeral) |
| Verdict Log | `.pilot/verdicts.jsonl` | Structured evaluator history | No (ephemeral) |
| Storyhook | `.storyhook/` | Story-level state and comments | Yes |

**Priority**: config.json + state.json + storyhook are required for mechanical recovery. handoff.md is the primary context source — if missing, pause and ask the user (see "Recovery Without Handoff" below).

## handoff.md Format

```markdown
# Work Handoff

## Session Summary
- **Session**: [session ID from lock]
- **Duration**: [time from lock acquired_at to now]
- **Stories completed**: [count]
- **Stories attempted**: [count]
- **Status**: [why we stopped — max_stories, blocked, error, user stop]

## What Happened
[Narrative of what was accomplished this session]

## Stories Completed This Session
- HP-5: [title] — [one-line summary]
- HP-6: [title] — [one-line summary]

## Current Blockers
- HP-7: [blocked reason and last evaluator feedback]

## Working Context
[This is the most valuable section for the next session]

### Patterns Established
- [Naming conventions decided during implementation]
- [Architecture patterns that emerged]

### Micro-Decisions
- [Small decisions not in DESIGN.md that future stories should follow]

### Known Gotchas
- [Things that tripped up the generator or evaluator]
- [Flaky tests and their names]

## What's Next
- [Next story to pick up]
- [Any decisions needed from user]
```

## Writing the Handoff

The handoff is written at these triggers:
1. **`/pilot stop`** — User-initiated graceful stop
2. **Session stop hook** — Session ending (compaction, timeout)
3. **Loop pause** — `max_stories_per_session` reached, blocked, storyhook failure, runaway safeguard

The handoff MUST include a "working context" section that captures patterns, conventions, and micro-decisions from the session. This is what makes resumed sessions effective — without it, the next session starts cold.

## Cold-Start Essentials

When context is cleared between stories (`max_stories_per_session: 1`), the handoff is the ONLY source of session knowledge. These sections are mandatory in every handoff:

### Patterns Established (REQUIRED)

Every naming convention, architectural pattern, error handling approach, or code organization decision made during execution. Examples:
- "All handlers use the pattern: validate → transform → persist → respond"
- "Error types are defined in `src/errors.ts`, one per module"
- "Tests use the factory pattern from `tests/helpers/factory.ts`"

### Micro-Decisions (REQUIRED)

Decisions not in DESIGN.md that emerged during implementation:
- "Used zod instead of joi for validation (better TypeScript inference)"
- "Config paths are relative to project root, not CWD"

### Code Landmarks (REQUIRED)

Key files and their roles, so the next session knows where things are without exploring:
- "`src/config.ts` — central config, all modules import from here"
- "`src/middleware/auth.ts` — auth middleware, uses JWT with RS256"
- "`tests/helpers/factory.ts` — test data factories for all domain objects"

### Test State (REQUIRED)

- Which tests pass, which are flaky, which are skipped
- Test run command and any required environment setup
- Most recent test suite output summary

## Recovery Without Handoff

If handoff.md is missing (crash without clean shutdown), the orchestrator MUST pause and ask the user what to do via `AskUserQuestion`:

- **header:** "Missing Handoff"
- **question:** "The handoff document from the previous session is missing (`.pilot/handoff.md`). Without it, the generator will work without knowledge of patterns and conventions established in prior sessions, which may cause inconsistencies."
- **options:**
  - "Continue anyway" / "Proceed using storyhook + state.json + git log — I can fill in context if needed"
  - "Stop" / "Let me investigate what happened before resuming"

If "Continue anyway", recovery falls back to:

| Source | What It Provides | What It Lacks |
|--------|-----------------|---------------|
| `state.json` | Metadata, retry counts | No working context |
| Storyhook | Story states, evaluator feedback | No cross-story patterns |
| `git log` | Recent commits | No micro-decisions or gotchas |
| `config.json` | User limits | No session narrative |
