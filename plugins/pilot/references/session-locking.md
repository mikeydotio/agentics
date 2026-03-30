# Session Locking

Heartbeat-based lock protocol to prevent duplicate work when remote triggers fire while a session is active.

## Lock File

`.pilot/lock.json` (gitignored — ephemeral runtime artifact)

```json
{
  "holder": "session-abc123",
  "acquired_at": "2026-03-28T14:30:00Z",
  "heartbeat_at": "2026-03-28T14:35:00Z"
}
```

## Protocol

### Acquiring a Lock

1. Check if `.pilot/lock.json` exists
2. If no lock → create it with current session ID and timestamp → acquired
3. If lock exists → check heartbeat staleness

### Heartbeat Staleness Check

```
age = now - lock.heartbeat_at
stale = age > heartbeat_window_minutes (from config.json, default 30)
```

- **Heartbeat fresh** (age < window) → Lock is held by an active session
  - Exit with message: "Work is already running in another session"
- **Heartbeat stale** (age >= window) → Previous session likely crashed
  - Break the lock (delete and recreate)
  - Log warning: "Broke stale lock (holder: [old holder], last heartbeat: [timestamp])"
  - Acquire new lock

### Updating Heartbeat

Update `heartbeat_at` in lock.json at these points:
1. **Before spawning generator** — reflects active work starting
2. **After generator completes, before spawning evaluator** — work transitioning
3. **After each loop iteration** — general health signal

This ensures the heartbeat reflects active work, not just loop overhead.

### Releasing a Lock

Delete `.pilot/lock.json`. Triggered by:
- `/pilot stop` (graceful user stop)
- Session stop hook
- Completion sequence

### No PID Checks

The protocol uses heartbeat-only — no PID checks. PID-based locking is fragile in containers where process namespaces differ between sessions.

## Heartbeat Window Tuning

Default: 30 minutes (`heartbeat_window_minutes` in config.json).

The window should exceed the expected maximum duration of a single story (generator + checks + evaluator):
- **Too short**: False stale-lock detection → duplicate work
- **Too long**: Delayed crash recovery

**Worst-case resume latency**: heartbeat window + trigger interval = ~45 minutes (30 + 15 default).

## Edge Cases

### Concurrent Resume Attempts
Two triggers fire simultaneously:
1. First one checks lock → stale → breaks and acquires
2. Second one checks lock → fresh (just acquired by first) → exits
Race window is small (< 1 second between check and acquire). Acceptable risk.

### Session Crash Without Lock Release
Next trigger fires → finds stale heartbeat → breaks lock → resumes normally.
Recovery sequence handles in-progress/verifying stories (resets to todo).
