---
module: plugins/forge/hooks
summary: "Forge session-lifecycle hooks — inject resume context on SessionStart, checkpoint a running pipeline on Stop"
read_when: "Touching forge session resume, stop checkpointing, or .forge state hook behavior"
sources:
  - path: plugins/forge/hooks/hooks.json
  - path: plugins/forge/hooks/session-start.sh
  - path: plugins/forge/hooks/session-stop.sh
references_modules: [plugins-forge-skills, plugins-freshen, plugins-hook-guard]
generator: cartographer/2
---

# Module: plugins/forge/hooks

## Purpose

Session-boundary survival for the forge pipeline; inert unless `.forge/state.json` exists.
`session-start.sh` re-orients a session by injecting resume context distilled from forge state.
`session-stop.sh` turns an abrupt stop into a checkpoint: handoff, pause, lock release, signal.
Without it, an interrupted run loses its place; with it, `/forge resume` continues from handoff.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `SessionStart` | hook binding | `plugins/forge/hooks/hooks.json:4` | Binds every session start (matcher `*`) to session-start.sh with a 10s timeout |
| `Stop` | hook binding | `plugins/forge/hooks/hooks.json:16` | Binds every Stop event (matcher `*`) to session-stop.sh with a 15s timeout |
| `session-start.sh` | bash hook script | `plugins/forge/hooks/hooks.json:10` | Prints `{additionalContext}` resume summary JSON, or nothing when forge is inactive |
| `session-stop.sh` | bash hook script | `plugins/forge/hooks/hooks.json:22` | Checkpoints a running pipeline to paused; guarantees stderr output on every exit |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `FRESHEN_DIR` | variable | `plugins/forge/hooks/session-stop.sh:115` | Auto-resume signal target `.freshen/`; written only inside tmux with no foreign signal pending |
| `HANDOFF_FILE` | variable | `plugins/forge/hooks/session-stop.sh:65` | Fixed degraded-handoff path `.forge/handoffs/handoff-execute.md`, echoed into state `.resume` |
| `RESUME_JSON` | variable | `plugins/forge/hooks/session-start.sh:35` | One-call jq state read: status, counters, optional `.resume` {summary, command, handoff_file} |
| `STATE_FILE` | variable | `plugins/forge/hooks/session-start.sh:26` | Activation gate in both scripts — absent `.forge/state.json` means immediate silent exit |
| `_GUARD_LIB` | variable | `plugins/forge/hooks/session-stop.sh:17` | Sources hook-guard's stop-guard circuit breaker before any work; a missing lib is tolerated |

## Relationships

- `plugins-forge-hooks.session-start.sh -> plugins-forge-skills.execute (reads)`
- `plugins-forge-hooks.session-stop.sh -> plugins-forge-skills.execute (writes)`
- `plugins-forge-hooks.session-stop.sh -> plugins-forge-skills.forge (calls)`
- `plugins-forge-hooks.session-stop.sh -> plugins-freshen.on-clear.sh (emits)`
- `plugins-forge-hooks.session-stop.sh -> plugins-freshen.on-stop.sh (emits)`
- `plugins-forge-hooks.session-stop.sh -> plugins-hook-guard.stop_guard_check (calls)`

## Type notes

- All JSON is built with jq, never printf escaping (plugins/forge/hooks/session-start.sh:9).
- Project dir: `CLAUDE_PROJECT_DIR`, else stdin `.cwd` (plugins/forge/hooks/session-start.sh:14).
- Start injects for `running` or `paused` status (plugins/forge/hooks/session-start.sh:45).
- Stop acts only when status is `running` (plugins/forge/hooks/session-stop.sh:44).
- The `.resume` object is the stop→start handshake (plugins/forge/hooks/session-stop.sh:106).
- Start prefers it over the handoff-scan fallback (plugins/forge/hooks/session-start.sh:56).
- Fallback emits newest handoff filename, never content (plugins/forge/hooks/session-start.sh:63).
- One jq pipeline rewrites state via tmp+mv (plugins/forge/hooks/session-stop.sh:100).
- It flips status to paused and bumps sessions_completed (plugins/forge/hooks/session-stop.sh:103).
- Duration derives from `.forge/lock.json` `acquired_at` (plugins/forge/hooks/session-stop.sh:52).
- The lock is deleted once the checkpoint lands (plugins/forge/hooks/session-stop.sh:110).

## External deps

- jq — sole JSON reader/builder; both hooks exit silently when it is missing
- storyhook — optional `story handoff --since` appendix in the degraded handoff
- tmux — `TMUX`/`TMUX_PANE` env vars gate the freshen auto-resume signal write

## Gotchas

- EXIT trap forces stderr output to avert a feedback loop (plugins/forge/hooks/session-stop.sh:14).
- Registration metadata still says "Conductor plugin", not forge (plugins/forge/hooks/hooks.json:2).
- `date -d` is GNU-only; on BSD duration stays unknown (plugins/forge/hooks/session-stop.sh:54).
- Guard lib path assumes sibling `../hook-guard` layout (plugins/forge/hooks/session-stop.sh:17).
- Any non-forge `*.signal` pending blocks the write (plugins/forge/hooks/session-stop.sh:119).
- Signal bypasses freshen.sh to dodge tmux validation (plugins/forge/hooks/session-stop.sh:113).
