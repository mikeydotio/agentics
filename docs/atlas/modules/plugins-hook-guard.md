---
module: plugins/hook-guard
summary: "Shared Stop-hook circuit breaker — sourced stop_guard_check halts runaway hook loops; SessionStart re-arms it"
read_when: "Touching Stop hooks, stop_guard_check/stop_guard_reset, or hook-loop protection"
sources:
  - path: plugins/hook-guard/.claude-plugin/plugin.json
  - path: plugins/hook-guard/hooks/hooks.json
  - path: plugins/hook-guard/hooks/session-start.sh
  - path: plugins/hook-guard/lib/stop-guard.sh
references_modules: [plugins-forge-hooks, plugins-freshen]
generator: cartographer/2
---

# Module: plugins/hook-guard

## Purpose

hook-guard is the circuit breaker that stops Stop-hook feedback loops: a hook whose side effects
start another turn fires its own next Stop event, forever. The plugin registers no Stop hook of
its own — it ships a sourceable library; consumer Stop hooks source
plugins/hook-guard/lib/stop-guard.sh and call stop_guard_check, which rate-counts stop events per
project and silently exits the calling hook when the rate looks like a loop. It fails open and
self-heals: state errors never block a hook, and its lone SessionStart hook wipes state so every
fresh session starts re-armed.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `session-start.sh` | hook (SessionStart: startup,resume,clear) | `plugins/hook-guard/hooks/hooks.json:10` | Sources the lib and calls `stop_guard_reset`; re-arms the breaker on each fresh session; 3s timeout |
| `stop-guard.sh` | sourced bash library | `plugins/hook-guard/lib/stop-guard.sh:2` | Source from any Stop hook; defines the guard functions only — does no work at source time |
| `stop_guard_check` | function | `plugins/hook-guard/lib/stop-guard.sh:25` | Logs one stop event; `exit 0`s the sourcing hook once >= threshold events land in the window; args `[window] [threshold]` |
| `stop_guard_reset` | function | `plugins/hook-guard/lib/stop-guard.sh:61` | Deletes the project's guard state file (and `.tmp`); idempotent |
| `STOP_GUARD_THRESHOLD` | env var | `plugins/hook-guard/lib/stop-guard.sh:16` | Overrides the trip threshold; default 4 events |
| `STOP_GUARD_WINDOW` | env var | `plugins/hook-guard/lib/stop-guard.sh:15` | Overrides the sliding window in seconds; default 30 |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `_stop_guard_file` | function | `plugins/hook-guard/lib/stop-guard.sh:18` | Sole authority for the state-file path; per-project keying (and its failure modes) live here |

## Relationships

- `plugins-forge-hooks.session-stop.sh -> plugins-hook-guard.stop_guard_check (calls)`
- `plugins-freshen.on-stop.sh -> plugins-hook-guard.stop_guard_check (calls)`
- `plugins-hook-guard.session-start.sh -> plugins-hook-guard.stop_guard_reset (calls)`

## Type notes

- State = unix timestamps in /tmp, one per stop event (plugins/hook-guard/lib/stop-guard.sh:34).
- Keyed per user + md5(CLAUDE_PROJECT_DIR|$PWD) (plugins/hook-guard/lib/stop-guard.sh:18-23).
- Defaults: threshold 4 events within a 30s window (plugins/hook-guard/lib/stop-guard.sh:15-16).
- A trip `exit 0`s the caller — Claude sees success (plugins/hook-guard/lib/stop-guard.sh:47).
- State I/O swallows errors; unwritable /tmp = guard off (plugins/hook-guard/lib/stop-guard.sh:34).
- State self-bounds via pruning (plugins/hook-guard/lib/stop-guard.sh:45-55).
- Recovery: startup/resume/clear sessions wipe state (plugins/hook-guard/hooks/session-start.sh:8).

## External deps

- md5sum — derives the per-project state-file key (plugins/hook-guard/lib/stop-guard.sh:21)
- No jq, tmux, or network — plain bash plus coreutils (`date`, `awk`, `tail`, `wc`)

## Gotchas

- Works only when sourced; executing it guards nothing (plugins/hook-guard/lib/stop-guard.sh:4-10).
- Usage wires `../hook-guard/` — siblings-only install (plugins/hook-guard/lib/stop-guard.sh:9).
- No `md5sum` → empty hash: all projects share state (plugins/hook-guard/lib/stop-guard.sh:21).
