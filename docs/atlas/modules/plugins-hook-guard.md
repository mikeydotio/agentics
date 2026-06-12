---
module: plugins/hook-guard
summary: "Circuit breaker for Stop hooks — sourceable bash lib that halts rapid stop-event loops; reset on SessionStart"
read_when: "Touching Stop hooks, stop_guard_check/stop_guard_reset, or hook-loop protection"
sources:
  - path: plugins/hook-guard/.claude-plugin/plugin.json
    blob: 107ca34d0b952e0377f64fcdf555e589f4a85d65
  - path: plugins/hook-guard/hooks/hooks.json
    blob: d22a3169ebee8171c0149fd33e18c5f191b39144
  - path: plugins/hook-guard/hooks/session-start.sh
    blob: 00d27a0d31baad818f66b8ef6dc9c6dc85f7509c
  - path: plugins/hook-guard/lib/stop-guard.sh
    blob: 3cde01ee73b5e599e062fc0f11e74f1912886b13
references_modules: [plugins-forge-hooks, plugins-freshen]
generator: cartographer/1
baseline: 0ce4ca44c3cc0b4a95d86862de8dc79914ffacbf
verified: true
---

# Module: plugins/hook-guard

## Purpose

Circuit breaker that prevents Stop-hook infinite loops: a Stop hook that re-prompts Claude can
otherwise retrigger itself forever. The plugin's substance is a sourceable bash library,
`plugins/hook-guard/lib/stop-guard.sh` — sibling plugins source it at the top of their Stop hooks
and call `stop_guard_check` before doing anything else. Its only registered hook is a SessionStart
reset, so a tripped breaker self-heals on the next session startup, resume, or clear.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `SessionStart` | hook registration | `plugins/hook-guard/hooks/hooks.json:4` | On startup/resume/clear, runs `plugins/hook-guard/hooks/session-start.sh` (3s timeout) to wipe breaker state |
| `stop_guard_check` | bash function | `plugins/hook-guard/lib/stop-guard.sh:25` | Records a stop event; at threshold events within the window, warns on stderr and exits the sourcing script with 0. Optional args override window and threshold. Never returns nonzero |
| `stop_guard_reset` | bash function | `plugins/hook-guard/lib/stop-guard.sh:61` | Deletes the breaker state file and its .tmp; idempotent, safe when no state exists |
| `STOP_GUARD_THRESHOLD` | env var | `plugins/hook-guard/lib/stop-guard.sh:16` | Stop events within the window that trip the breaker (default 4) |
| `STOP_GUARD_WINDOW` | env var | `plugins/hook-guard/lib/stop-guard.sh:15` | Sliding-window length in seconds for counting stop events (default 30) |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `_stop_guard_file` | bash function | `plugins/hook-guard/lib/stop-guard.sh:18` | Single source of the state-file path; both public functions key every read, write, and delete through it |

## Relationships

- `plugins-forge-hooks.session-stop.sh -> plugins-hook-guard.stop_guard_check (calls)`
- `plugins-freshen.on-stop.sh -> plugins-hook-guard.stop_guard_check (calls)`
- `plugins-hook-guard.session-start.sh -> plugins-hook-guard.stop_guard_reset (calls)`
- `plugins-hook-guard.stop_guard_check -> plugins-hook-guard._stop_guard_file (calls)`
- `plugins-hook-guard.stop_guard_reset -> plugins-hook-guard._stop_guard_file (calls)`

## Type notes

- State: one epoch timestamp per line in `/tmp/claude-stop-guard-<user>-<hash>`; OS cleans /tmp.
- State key: 8-char md5 of the project dir, per user — `plugins/hook-guard/lib/stop-guard.sh:18`.
- Project dir is `CLAUDE_PROJECT_DIR` else `PWD` — `plugins/hook-guard/lib/stop-guard.sh:19`.
- Default trip: 4 events in 30s; args can override — `plugins/hook-guard/lib/stop-guard.sh:29`.
- A trip exits 0, so Claude Code sees a clean hook — `plugins/hook-guard/lib/stop-guard.sh:47`.
- Trip message `hook-guard: circuit breaker tripped` — `plugins/hook-guard/lib/stop-guard.sh:43`.
- Fail-open: unwritable state means no protection — `plugins/hook-guard/lib/stop-guard.sh:34`.
- On trip, pre-window entries are pruned — `plugins/hook-guard/lib/stop-guard.sh:45`.
- Each `/clear`, startup, or resume re-arms the breaker — `plugins/hook-guard/hooks/hooks.json:6`.
- Reset hook logs `hook-guard: ok` to stderr — `plugins/hook-guard/hooks/session-start.sh:10`.

## External deps

- None third-party; uses `md5sum`, `awk`, `date` — `plugins/hook-guard/lib/stop-guard.sh:21`.

## Gotchas

- Code after a tripped guard never runs — `plugins/hook-guard/lib/stop-guard.sh:47`.
- Prescribed sourcing assumes sibling plugin install — `plugins/hook-guard/lib/stop-guard.sh:9`.
- Missing lib degrades to unguarded, not failure — `plugins/hook-guard/lib/stop-guard.sh:10`.
