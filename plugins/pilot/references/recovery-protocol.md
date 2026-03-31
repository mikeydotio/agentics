# Recovery Protocol

Resume and recovery sequence for pilot — restoring context after session boundaries or crashes.

## Recovery Sequence (`/pilot resume`)

### 1. Lock Check

- Check `.pilot/lock.json`
- If heartbeat fresh (< `heartbeat_window_minutes`) → exit: "Work is already running"
- If lock exists but heartbeat stale → break lock, log warning
- Acquire new lock

### 2. State Read

- Read `.pilot/state.json`
- If missing or malformed → report clear error, exit (do not guess)
- If `status` is `complete` → remove trigger if still present, exit

### 3. Handoff Read (Primary Context Source)

- Read `.pilot/handoff.md` if it exists
- Extract: patterns established, micro-decisions, code landmarks, test state, blockers, why did we stop
- Feed extracted context into the generator prompt for the next story
- **If handoff.md is missing** → pause and ask the user via `AskUserQuestion` (see `references/handoff-format.md` for the missing-handoff protocol). Do NOT silently continue with degraded context.

### 4. Crash Recovery

Query storyhook for stories in inconsistent states:

```bash
story list --json
```

Any story in `in-progress` or `verifying` state indicates a crash mid-work:
- Reset these stories to `todo`: `story HP-N is todo`
- Clean working tree: `git checkout .`

This ensures no partially-completed work contaminates the next attempt.

### 5. Determine Next Action

```bash
story next --json
```

Check what's available:
- Stories available → proceed to execution loop
- No stories, all `done` → transition to `complete` (even if state.json said `paused`)
- No stories, some `blocked` → pause: "blocked stories remain — user intervention needed"

### 6. Context Gathering

```bash
git log --oneline -10
```

Run test suite to verify codebase health.

### 6a. Context Validation

Compare handoff.md claims against actual disk state to guard against stale handoffs:

- If handoff says "tests pass" → run tests to verify
- If handoff references files that don't exist → note discrepancy, remove from code landmarks
- If git log shows commits not mentioned in handoff → session crashed mid-story, flag this

This step is especially important when the handoff is from a much older session. Trust current disk state over handoff claims when they conflict.

### 7. Decision Point

- If tests fail → stop: user must fix test failures before resuming
- If decision needed (blocked stories requiring user input) → stop
- Otherwise → enter execution loop

## Cross-Layer Inconsistency Detection

If `state.json` says `paused` but all stories are `done`:
- Transition to `complete` — state.json was stale
- This handles the case where a session completed all stories but crashed before updating state.json
