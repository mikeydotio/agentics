# Work Workflow

How the pilot plugin turns a plan into a finished implementation while you walk away.

---

## Overview

```
/pilot ideate "your idea"
        |
    /ideate runs with pilot-aware hints
    (question, research, design, plan)
        |
    PLAN.md approved -> automatic handoff
        |
    /pilot plan (decompose into stories)
        |
    /pilot run (canary mode: first 3 stories supervised)
        |
    Fully autonomous loop
    (generator -> deterministic checks -> evaluator -> commit)
        |
    Session ends -> handoff -> timer fires -> resume
        |
    All stories done -> COMPLETION.md
```

---

## Step by Step

### 1. Start with /pilot ideate

Run `/pilot ideate` and describe what you want to build. This invokes `/ideate` behind the scenes with pilot-aware hints:

- Acceptance criteria must be **machine-evaluable** (concrete, testable -- not vague)
- Tasks should be **sized for a single agent session** (completable by one generator spawn)
- PLAN.md wave structure should map cleanly to storyhook stories

Ideate runs its full workflow as usual -- questions you, researches the problem, designs the architecture, produces DESIGN.md and PLAN.md. The only difference is the hints that shape the output for autonomous execution.

You can also use `/ideate` directly if you want the standard flow. Phase 4.5 still offers the pilot handoff either way.

### 2. Plan approved -- automatic handoff

After you approve the plan, ideate's Phase 4.5 presents a choice:

- **Autonomous via pilot** -- you walk away
- **Execute here** -- ideate's existing Phase 5, you stay and watch
- **Just the plan** -- you execute manually

If you came through `/pilot ideate`, autonomous is the default. Pick it.

### 3. Work decomposes your plan

`/pilot plan` reads PLAN.md and:

- Breaks each task into a storyhook story with acceptance criteria
- Maps each story to the relevant DESIGN.md section (for just-in-time context)
- Sets up dependency relationships (wave 1 before wave 2, etc.)
- Writes `.pilot/plan-mapping.json` linking everything together

You see a summary like: *"Created 12 stories across 3 waves."*

If you run `/pilot plan` again on the same plan, it detects the existing mapping and asks whether to recreate, continue, or cancel.

### 4. Canary mode -- watch the first few

Work starts with `/pilot run`. For the first 3 stories (configurable via `canary_stories`), it pauses after each one and shows you the evaluator's verdict. This is your chance to validate:

- Is the generator producing good code?
- Is the evaluator catching real issues (not being too generous)?
- Are stories sized right for one agent session?

Adjust the evaluator prompt or story granularity if needed. Once satisfied, execution goes fully autonomous.

### 5. The autonomous loop

For each story, pilot runs this sequence:

1. **Pick next story** from storyhook (storyhook is the source of truth for story state)
2. **Query memory** for relevant past decisions about this component
3. **Extract context** -- only the relevant DESIGN.md section, plus any prior evaluator feedback from storyhook comments
4. **Spawn generator** as an isolated subagent with fresh context. Generator writes code but does NOT commit.
5. **Run deterministic pre-checks** -- test suite, linter/type checker, grep for TODO/FIXME/stub patterns
6. **Spawn evaluator** as an isolated subagent (read-only, no Write/Edit tools). Evaluator reviews the uncommitted diff against acceptance criteria with a skeptical, debiased stance.
7. **Outcome**:
   - **Pass** -- commit atomically, mark story done, store knowledge to memory, move on
   - **Fail** -- store structured feedback as a storyhook comment, retry (up to 3-4 attempts, configurable)
   - **Max retries exhausted** -- mark story blocked for human review
   - **Generator unsure** -- mark story blocked as `needs_decision`

At wave boundaries, an architect-reviewer subagent checks for consistency across all stories completed so far. If significant drift is detected, pilot pauses for your review.

### 6. Session handoff and auto-resume

After completing a configurable number of stories (`max_stories_per_session`, default 3-5), pilot:

- Writes a handoff document including a **working context summary** (patterns established, naming conventions, micro-decisions, known gotchas)
- Updates state to `paused`
- Releases the session lock

A **systemd timer** (or crontab entry) fires at a configurable interval (default every 15 minutes). When it fires:

- Checks the session lock -- if another session is active, does nothing
- If state is `paused`, acquires the lock, reads the handoff, checks storyhook for what's next, runs tests to verify codebase health, and re-enters the loop
- If state is `complete`, removes the timer

You can be asleep, at lunch, in meetings. Each session picks up where the last one left off.

### 7. Check in whenever you want

`/pilot status` shows a dashboard:

- Stories by state (done, in-progress, blocked, todo)
- Current wave progress
- Retry counts
- Blocked stories with evaluator feedback
- Timer status

If something's blocked, read the evaluator feedback in the storyhook comments, make a decision, unblock the story, and pilot picks it up on the next cycle.

`/pilot stop` gracefully shuts everything down -- writes handoff, releases lock, removes timer.

### 8. Completion

When all stories are done, pilot:

- Runs the full test suite
- Generates a storyhook report
- Stores project knowledge to memory (decisions, patterns, learnings)
- Removes the auto-resume timer
- Writes COMPLETION.md

You come back to a finished implementation.

---

## When things go wrong

Work is designed to escalate, not push through:

| Situation | What happens |
|-----------|-------------|
| Generator can't meet criteria after 3-4 tries | Story marked `blocked` with evaluator feedback. Waits for you. |
| Generator encounters ambiguity or needs an architectural decision | Story marked `needs_decision`. Waits for you. |
| Storyhook is unavailable (3 consecutive failures) | Work pauses gracefully with handoff. |
| Architectural drift detected at wave boundary | Work pauses for your review. |
| Session crashes without cleanup | Timer fires, finds stale lock (heartbeat > 5 min), breaks it, resumes from handoff + storyhook state. |
| You need to intervene | `/pilot stop` for graceful shutdown at any time. |

Worst-case resume latency after a crash: ~20 minutes (5 min heartbeat window + 15 min timer interval).

---

## Key commands

| Command | What it does |
|---------|-------------|
| `/pilot ideate` | Start from scratch -- invokes `/ideate` with pilot-aware hints, then hands off to plan + run |
| `/pilot init` | Validate storyhook setup, add required states |
| `/pilot plan [file]` | Decompose PLAN.md into storyhook stories |
| `/pilot run [--interval 15m]` | Start autonomous execution with auto-resume timer |
| `/pilot resume` | Resume from pause (usually called by timer, not you) |
| `/pilot status` | Dashboard of progress, blockers, retries |
| `/pilot stop` | Graceful shutdown |

---

## Configuration

All settings live in `.pilot/state.json` and are set at `/pilot run` time:

| Setting | Default | What it controls |
|---------|---------|-----------------|
| `max_stories_per_session` | 5 | Stories completed before pausing for handoff |
| `max_retries` | 4 | Generator-evaluator cycles before blocking a story |
| `canary_remaining` | 3 | Stories that require your approval before full autonomy |
| `trigger_interval` | 15m | How often the auto-resume timer fires |
