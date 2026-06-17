---
module: plugins/freshen
summary: "Automatic context clearing — queues /clear + re-invocation between workflow phases via tmux send-keys"
read_when: "Touching context clearing, .freshen signal files, or /clear re-invocation automation"
sources:
  - path: plugins/freshen/.claude-plugin/plugin.json
    blob: 030bbad689a442a32a0bc77ac38a14b1ab01e6ef
  - path: plugins/freshen/bin/freshen.sh
    blob: 99de1df3d5a354cc0834464078f31e276bdaff61
  - path: plugins/freshen/hooks/hooks.json
    blob: 685850a8d3fb5d3f11d059086fffbdecd8ea1739
  - path: plugins/freshen/hooks/on-clear.sh
    blob: 7247b0c06e0734e2a7768f41460e46c8244cc50f
  - path: plugins/freshen/hooks/on-stop.sh
    blob: 49804b1a6f98b8e1e9af3b59f13d1e50105ed627
  - path: plugins/freshen/skills/freshen/SKILL.md
    blob: 2f8f3decc4a8cae565bc1833ddab55e249d81abd
references_modules: [plugins-hook-guard, plugins-forge-skills]
generator: cartographer/2
baseline: b4cedefaba8df96ee167877bf2ee9c3143ef0b08
---

# Module: plugins/freshen

## Purpose

Freshen provides a signal-file mechanism that lets other plugins (primarily forge) trigger `/clear` and re-invoke a command between workflow phases without human interaction. The design rests on a two-file handshake: a `.freshen/<source>.signal` file written before Claude's turn ends causes the Stop hook to send `/clear` via tmux, and the subsequent SessionStart(clear) hook reads the signal, deletes it, and fires the re-invocation command. Without freshen, plugins that need a clean context window between steps must instruct the user to `/clear` manually.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `cmd_cancel` | bash function | `plugins/freshen/bin/freshen.sh:96` | `cancel --source <name>` or `cancel --all` removes pending signal files |
| `cmd_disable` | bash function | `plugins/freshen/bin/freshen.sh:125` | Cancels all signals, creates `.freshen/.disabled`; human-only per skill Hard Rule |
| `cmd_enable` | bash function | `plugins/freshen/bin/freshen.sh:136` | Removes `.freshen/.disabled`; human-only per skill Hard Rule |
| `cmd_queue` | bash function | `plugins/freshen/bin/freshen.sh:37` | Writes `<source>.signal`; requires tmux; rejects cross-source conflicts |
| `cmd_status` | bash function | `plugins/freshen/bin/freshen.sh:83` | Prints each pending signal as `source: command` |
| `freshen` | skill | `plugins/freshen/skills/freshen/SKILL.md:1` | `/freshen <subcommand>` delegates to `plugins/freshen/bin/freshen.sh`; enable/disable are human-only |
| `on-clear.sh` | hook (SessionStart:clear) | `plugins/freshen/hooks/hooks.json:22` | After freshen-initiated clear: echoes summary, tmux-sends queued command, deletes signal |
| `on-stop.sh` | hook (Stop) | `plugins/freshen/hooks/hooks.json:7` | If a signal is pending at turn end: touches `.clear-pending`, tmux-sends `/clear` |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `.clear-pending` | flag file | `plugins/freshen/hooks/on-stop.sh:38` | Marks the clear as freshen-initiated; `on-clear.sh` exits without consuming signals when absent |
| `require_enabled` | bash function | `plugins/freshen/bin/freshen.sh:30` | Gates queue/status/cancel on absence of `.freshen/.disabled` — kill switch every command obeys |
| `require_tmux` | bash function | `plugins/freshen/bin/freshen.sh:21` | `queue` dies unless `$TMUX` and `$TMUX_PANE` are set; send-keys is the only delivery channel |

## Relationships

- `plugins-freshen.on-stop.sh -> plugins-hook-guard.stop_guard_check (calls)` — `plugins/freshen/hooks/on-stop.sh:16` sources `hook-guard/lib/stop-guard.sh` to prevent Stop-hook infinite loops
- `plugins-forge-skills.step-skills -> plugins-freshen.cmd_queue (calls)` — forge step skills invoke `freshen.sh queue` to register re-invocation; evidence at `plugins/forge/skills/execute/SKILL.md`

## Type notes

- Signal file format: line 1 = command to re-invoke, optional remaining lines = progress summary (`plugins/freshen/bin/freshen.sh:75`)
- Oldest signal wins each clear cycle; at most one signal is consumed per `/clear` (`plugins/freshen/hooks/on-clear.sh:25`)
- A signal is deleted only after its `tmux send-keys` succeeds (`plugins/freshen/hooks/on-clear.sh:43`)
- User-initiated `/clear` leaves signals intact because `.clear-pending` is absent (`plugins/freshen/hooks/on-clear.sh:22`)
- Stop hook reaps signals older than 120 minutes before checking for pending ones (`plugins/freshen/hooks/on-stop.sh:27`)
- On `startup`, `resume`, or `compact` SessionStart events, all relay state is wiped (`plugins/freshen/hooks/hooks.json:28`)
- `.freshen/` is gitignored and ephemeral (`plugins/freshen/bin/freshen.sh:11`)

## External deps

- tmux — `send-keys -t $TMUX_PANE` is the sole delivery channel for both `/clear` and re-invocation commands; no fallback exists

## Gotchas

- Every hook exit path must write to stderr (`plugins/freshen/hooks/on-stop.sh:11`); silent exits cause Claude Code to inject "No stderr output" conversation feedback, which triggers another Stop event and an infinite loop.
- Only one source may be pending at a time; a second cross-source `queue` call is a hard error (`plugins/freshen/bin/freshen.sh:64`).
- `enable` and `disable` are explicitly reserved for human use; the SKILL.md Hard Rules section (`plugins/freshen/skills/freshen/SKILL.md:13`) forbids autonomous invocation.
