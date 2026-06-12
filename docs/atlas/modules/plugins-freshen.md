---
module: plugins/freshen
summary: "Context-clearing relay — queued signal files drive /clear + re-invocation via tmux send-keys"
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
references_modules: [plugins-forge-bin, plugins-forge-hooks, plugins-hook-guard]
generator: cartographer/1
baseline: b1e1f9d1dbced518c625c38bb87814de5af1a1b7
verified: true
---

# Module: plugins/freshen

## Purpose

The context-clearing relay: a caller drops a signal file naming a command, and freshen's hook
pair turns Claude's next turn end into `/clear` plus re-invocation of that command, both sent as
tmux send-keys. The design hinge is a two-file handshake — `<source>.signal` (what to run next)
and `.clear-pending` (proof the clear was freshen-initiated) — so relay state survives the
context wipe it triggers. Consumer plugins queue and simply return
(`plugins/freshen/skills/freshen/SKILL.md:53`); outside tmux the hooks no-op, leaving the signal
for manual handling (`plugins/freshen/hooks/on-stop.sh:33`).

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `cmd_cancel` | function | `plugins/freshen/bin/freshen.sh:96` | `cancel --source <name>` or `cancel --all` removes pending signal files |
| `cmd_disable` | function | `plugins/freshen/bin/freshen.sh:125` | `disable` cancels all signals, creates `.freshen/.disabled`; human-only per skill Hard Rule |
| `cmd_enable` | function | `plugins/freshen/bin/freshen.sh:136` | `enable` removes the `.disabled` marker; human-only per skill Hard Rule |
| `cmd_queue` | function | `plugins/freshen/bin/freshen.sh:37` | `queue <cmd> --source <name> [--summary <text>]` writes the signal; tmux required; one source pending at a time |
| `cmd_status` | function | `plugins/freshen/bin/freshen.sh:83` | `status` prints each pending signal as `source: command` |
| `freshen` | skill | `plugins/freshen/skills/freshen/SKILL.md:2` | `/freshen <subcommand>` delegates to `plugins/freshen/bin/freshen.sh`; human-only enable/disable |
| `on-clear.sh` | hook (SessionStart:clear) | `plugins/freshen/hooks/hooks.json:22` | After a freshen-initiated clear: echoes summary, tmux-sends the queued command, deletes the signal |
| `on-stop.sh` | hook (Stop) | `plugins/freshen/hooks/hooks.json:10` | If a signal is pending at turn end: touches `.clear-pending`, tmux-sends `/clear` |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `.clear-pending` | flag file | `plugins/freshen/hooks/on-stop.sh:38` | Marks the clear as freshen-initiated; `on-clear.sh` exits without consuming signals when it is absent |
| `require_enabled` | function | `plugins/freshen/bin/freshen.sh:30` | Gates queue/status/cancel on absence of `.freshen/.disabled` — the kill switch every command obeys |
| `require_tmux` | function | `plugins/freshen/bin/freshen.sh:21` | `queue` dies unless `$TMUX` and `$TMUX_PANE` are set; tmux send-keys is the only delivery channel |

## Relationships

- `plugins-freshen.cmd_queue -> plugins-freshen.on-stop.sh (emits)`
- `plugins-freshen.on-stop.sh -> plugins-freshen.on-clear.sh (emits)`
- `plugins-freshen.on-stop.sh -> plugins-hook-guard.stop_guard_check (calls)`
- `plugins-forge-bin.forge-step-exit.sh -> plugins-freshen.cmd_queue (calls)`
- `plugins-forge-hooks.session-stop.sh -> plugins-freshen.on-stop.sh (emits)`

## Type notes

- Signal file: line 1 = command, rest = optional summary (`plugins/freshen/bin/freshen.sh:76`)
- Oldest signal wins each clear cycle (`plugins/freshen/hooks/on-clear.sh:25`)
- A signal is deleted only after its send-keys succeeds (`plugins/freshen/hooks/on-clear.sh:43`)
- User-initiated `/clear` leaves signals intact (`plugins/freshen/hooks/on-clear.sh:22`)
- Stop hook reaps signals older than 120 minutes (`plugins/freshen/hooks/on-stop.sh:27`)
- startup/resume/compact sessions wipe all relay state (`plugins/freshen/hooks/hooks.json:32`)
- `.freshen/.disabled` makes both hooks exit early (`plugins/freshen/hooks/on-stop.sh:24`)
- `.freshen/` is gitignored and ephemeral (`plugins/freshen/bin/freshen.sh:11`)

## External deps

- tmux — `send-keys` delivers both `/clear` and the re-invocation command; no other channel exists

## Gotchas

- Hook exits must write stderr or the Stop event loops (`plugins/freshen/hooks/on-stop.sh:8`)
- One source pending at a time; a second source hard-errors (`plugins/freshen/bin/freshen.sh:64`)
- `plugins/freshen/skills/freshen/SKILL.md:64` wrongly claims multiple sources can coexist
- enable/disable are human-only commands (`plugins/freshen/skills/freshen/SKILL.md:13`)
