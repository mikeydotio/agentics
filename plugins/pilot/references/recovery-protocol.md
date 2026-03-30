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

### 3. Handoff Read (Best-Effort)

- Read `.pilot/handoff.md` if it exists
- Extract: why did we stop? working context? patterns? blockers?
- If handoff.md missing → recovery continues without it

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

### 7. Decision Point

- If tests fail → stop: user must fix test failures before resuming
- If decision needed (blocked stories requiring user input) → stop
- Otherwise → enter execution loop

## Recovery Without Handoff

The handoff enriches recovery but is not required:

| Source | What It Provides |
|--------|-----------------|
| `state.json` | Work metadata, retry counts, session counts |
| Storyhook | Story states, comments (evaluator feedback), dependencies |
| `git log` | Recent commits, what was completed |
| `config.json` | User limits and settings |

## Cross-Layer Inconsistency Detection

If `state.json` says `paused` but all stories are `done`:
- Transition to `complete` — state.json was stale
- This handles the case where a session completed all stories but crashed before updating state.json
