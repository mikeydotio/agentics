---
module: "plugins/atlas (misc)"
summary: "Atlas plugin identity, README docs, and the /atlas orchestrator plus its SessionStart staleness hook."
read_when: "Touching atlas plugin identity, README, /atlas dispatch, or the staleness hook"
sources:
  - path: plugins/atlas/.claude-plugin/plugin.json
    blob: b6d1b9e2f6b141defd8340d2e9ee3710e1e63c72
  - path: plugins/atlas/README.md
    blob: 9cf94e438eac816b0bd995a72ef2217b7288ef3e
  - path: plugins/atlas/hooks/hooks.json
    blob: 41851681fe5ce7fdd0fc14b33dd4868d38398e6a
  - path: plugins/atlas/hooks/session-start.sh
    blob: 4277ada1b6f54bba1034edf015c622f6a3a3eb94
  - path: plugins/atlas/skills/atlas/SKILL.md
    blob: 0dd4b60cddcc8e5ed66df66dd4328ec020b9f869
generator: cartographer/4
baseline: cb09ceb006e3fb4759a91d64d9e6655e67d04bf7
---

# Module: plugins/atlas (misc)

## Purpose

This module is the user- and agent-facing entry point for the atlas plugin: plugin.json establishes its marketplace identity, README.md is the full v2 architecture and command reference for humans, and skills/atlas/SKILL.md is the thin orchestrator that routes every /atlas command to the deterministic CLI and the mapping/update/repair reference protocols, spawning cartographer annotators for the sole judgment step. hooks/session-start.sh complements it by injecting the staleness-tier message into every session at SessionStart, independent of whether the map is ever read. Remove this module and the CLI/protocols still exist but there is no /atlas command surface, no cartographer-spawn discipline, and no session-start staleness warning.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

- hooks/session-start.sh fails open at every guard — missing project dir, no map, missing python3/jq, missing atlas-cli, or a failed status call all `exit 0` silently rather than blocking session start (plugins/atlas/hooks/session-start.sh:27,30,33-34,38,40).
- SKILL.md's orchestrator never writes map docs, judgment cells, or judgments.json itself: `atlas-cli project` renders docs and cartographer annotators emit cells; the orchestrator only assembles prompts and pipes annotator output to `judgment ingest` (plugins/atlas/skills/atlas/SKILL.md:10-14,25-29).
- Cartographer agents spawned by this skill are pinned to model `sonnet[1m]`; the pin is scoped to this skill's spawns only and does not alter the shared cartographer.md definition or this skill's own `model: inherit` (plugins/atlas/skills/atlas/SKILL.md:5,71-84).
- Map-writing flows must acquire the `.atlas/lock/` heartbeat lock before touching map files and release it on every exit path, including aborts (plugins/atlas/skills/atlas/SKILL.md:41-42).

## External deps


## Gotchas

- hooks/session-start.sh explicitly drains stdin even when CLAUDE_PROJECT_DIR is already set, to avoid a broken pipe from the unread SessionStart payload (plugins/atlas/hooks/session-start.sh:23-24).
- INDEX.md and atlas-ledger.json are derived files: hand edits are silently overwritten on the next rebuild and flagged by lint until then — edit the module docs instead (plugins/atlas/README.md:248-251).
- Merge conflicts inside docs/atlas/ must not be hand-resolved; pick either side wholesale (`git checkout --ours -- docs/atlas/`) and rerun `/atlas update`, since INDEX.md/atlas-ledger.json are derived and a `merge=union` driver would corrupt them (plugins/atlas/README.md:140-152).
- A crashed map/update run's heartbeat lock under `.atlas/lock/` is only taken over by another session after roughly 10 minutes (plugins/atlas/README.md:217-218).
