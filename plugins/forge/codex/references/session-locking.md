# Session Locking

Heartbeat-based lock protocol to prevent duplicate work when remote triggers fire while a session
is active. Scripted by `bin/forge-lock.sh`  — this doc describes what the script checks
and how to read its JSON, not raw timestamp arithmetic for the model to hand-execute.

## Lock File

`.forge/lock.json` (gitignored — ephemeral runtime artifact)

```json
{
  "holder": "session-abc123",
  "acquired_at": "2026-03-28T14:30:00Z",
  "heartbeat_at": "2026-03-28T14:35:00Z"
}
```

Never read, write, or diff this file directly — always go through `forge-lock.sh`. It owns the
atomic read-modify-write and the heartbeat-staleness math (`age = now - heartbeat_at` vs
`heartbeat_window_minutes`, computed via `jq`'s `now`/`fromdate` so it's correct on both BSD and
GNU userlands with no `date -d` dependency).

## `bin/forge-lock.sh` subcommands

```bash
bash "<plugin-root>/bin/forge-lock.sh" acquire   --session-id <id> [--window-min <n>] [--forge-dir .forge]
bash "<plugin-root>/bin/forge-lock.sh" heartbeat --session-id <id> [--forge-dir .forge]
bash "<plugin-root>/bin/forge-lock.sh" release   [--session-id <id>] [--forge-dir .forge]
bash "<plugin-root>/bin/forge-lock.sh" check     --session-id <id> [--window-min <n>] [--forge-dir .forge]
```

`--window-min` defaults to `.forge/config.json`'s `heartbeat_window_minutes` (30 if absent) when
omitted.

### `acquire` — `{ok, acquired, broke_stale, held_by, display}`

Creates the lock if absent, breaks it if stale (heartbeat age exceeds the window), or reports
contention if a different session holds a fresh one. Re-acquiring with the SAME `--session-id` is
an idempotent success (`acquired: true`). Call this once, at Loop entry (Fresh Start step 4 /
Resume step 1 — see `execute/SKILL.md`). If `acquired` is `false`: STOP and report "Work is
already running in another session (held_by: `<held_by>`)" — do not proceed into the loop.

### `heartbeat` — `{ok, updated, display}`

Refreshes `heartbeat_at` for the holding session. Refuses (`ok: false`) if the lock is held by a
different session-id, or absent entirely. Call this at the three points that reflect active work,
not just loop overhead:
1. **Before spawning the generator** — reflects active work starting.
2. **After the generator completes, before spawning the evaluator** — work transitioning.
3. **After each loop iteration** — general health signal.

### `release` — `{ok, released, display}`

Deletes the lock. Without `--session-id`, releases unconditionally; with it, refuses to release a
lock held by a *different* session (guards against one session's stop path tearing down another's
active lock). Triggered by:
- `$forge:forge stop` (graceful user stop)
- Session stop hook (`hooks/session-stop.sh` — this hook `rm -f`s the lock file directly rather
  than shelling out, since it must stay dependency-light and silent on every exit path; this is
  the one place in the codebase that still touches `lock.json` outside `forge-lock.sh`, and that's
  intentional, not an oversight)
- Completion sequence (Execute's `complete:` block)

### `check` — `{ok, held, stale, action, holder, age_seconds, display}`

Read-only — never mutates `lock.json`. `action` is one of:
- `"acquire"` — no lock present, or held by the calling session itself.
- `"exit-running"` — held fresh by a different session; work is already running.
- `"break"` — held but stale; safe to break and acquire.

Prefer `acquire` directly in the common case (it already implements this decision); `check` exists
for callers that need to *inspect* lock state without side effects (e.g. `$forge:forge status`-style
tooling).

### No PID Checks

The protocol is heartbeat-only — no PID checks. PID-based locking is fragile in containers where
process namespaces differ between sessions.

## Heartbeat Window Tuning

Default: 30 minutes (`heartbeat_window_minutes` in config.json).

The window should exceed the expected maximum duration of a single story (generator + checks +
evaluator):
- **Too short**: False stale-lock detection → duplicate work
- **Too long**: Delayed crash recovery

**Worst-case resume latency**: heartbeat window only = ~30 minutes (default). Freshen fires
immediately when the session ends, so there is no trigger interval component. The heartbeat window
only matters for crash recovery (stale lock detection).

**Known gap, not solved by this script alone:** nothing refreshes the heartbeat *during* a
single long-running generator/evaluator subagent call — only at the three points listed above,
which bracket the spawn, not the inside of it. A story whose generator or evaluator legitimately
runs longer than the window can still go stale-locked mid-spawn. Exploiting the guaranteed-tmux
assumption (a background heartbeat refresher, or an `in_subagent`/`expected_completion` marker a
resumer can distinguish from a genuine crash) is the durable fix and is out of this script's scope
— call `heartbeat` at the three documented points and raise the configured window if your stories
routinely run long.

## Edge Cases

### Concurrent Resume Attempts
Freshen is fire-once per pause, so concurrent triggers are not a concern under normal operation. If
a user manually runs `$forge:forge resume` while a freshen-triggered resume is starting, `acquire`
prevents duplicate work: the second attempt sees a fresh heartbeat and reports `acquired: false`.

### Session Crash Without Lock Release
The session-stop hook attempts to queue a freshen signal for auto-resume. If the signal was queued
successfully, the next session starts automatically. If not (hook failed to run, tmux unavailable),
the user must manually run `$forge:forge resume`. The recovery sequence (`<plugin-root>/codex/references/recovery-protocol.md`,
via `bin/forge-crash-recover.sh`) handles in-progress/verifying stories (refuses cleanup while verification is in progress).
