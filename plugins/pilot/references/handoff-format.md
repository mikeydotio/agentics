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
| Memory | memlayer / `.memory/` | Structural knowledge | Partially |

**Priority**: config.json + state.json + storyhook are required for recovery. handoff.md is best-effort. Memory is post-hoc enrichment.

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

## Recovery Without Handoff

If handoff.md is missing (crash without clean shutdown), recovery still works:
1. Read state.json → pilot metadata, retry counts
2. Query storyhook → story states, comments (evaluator feedback)
3. Read git log → recent commits, what was completed
4. Resume from storyhook's next story

The handoff enriches recovery but is not required for it.
