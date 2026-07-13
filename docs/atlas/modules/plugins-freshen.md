---
module: plugins/freshen
summary: "Automatic /clear + re-invocation via tmux: Stop/SessionStart hooks consume confirmed .freshen/ signal files."
read_when: "Touching context clearing, .freshen signal files, or /clear re-invocation automation"
sources:
  - path: plugins/freshen/.claude-plugin/plugin.json
    blob: 2a275975dd66736fafaeb4323de02923fb93ee43
  - path: plugins/freshen/bin/freshen.sh
    blob: 58f1e47f2d10aa68f58dafac3a83351d8ff0caa6
  - path: plugins/freshen/hooks/hooks.json
    blob: d6b0145c08230b99b9be1f9dbf838455b2dad6b6
  - path: plugins/freshen/hooks/on-clear.bats
    blob: 477bcb483c51d61cf8e530d55323521a02ef14dd
  - path: plugins/freshen/hooks/on-clear.sh
    blob: 449fc22a901badfd0ae570e2c40f05a7d0cdff89
  - path: plugins/freshen/hooks/on-stop.bats
    blob: 9f2a3a68b35afdfa56bece1c665f19f6630f2a78
  - path: plugins/freshen/hooks/on-stop.sh
    blob: 2b3f0ea3c0e9970852515592e63f3914ba2153cf
  - path: plugins/freshen/lib/pane-confirm.bats
    blob: c72c718d038ec710b63b8331ed01c8f360d01dd3
  - path: plugins/freshen/lib/pane-confirm.sh
    blob: 1ecd72ee498b7780380dc165b59c52f1c9e90987
  - path: plugins/freshen/lib/transition-log.bats
    blob: 7d96e1d6cbc66cda0a061fb8539620ba563ce732
  - path: plugins/freshen/lib/transition-log.sh
    blob: 15e6ec4c59506fc0d075645bf0aab75fa38ab3f2
  - path: plugins/freshen/skills/freshen/SKILL.md
    blob: b2fcfca147d49c8eb04a5b2084f187b791977466
  - path: plugins/freshen/tests/run-tests.sh
    blob: 626c549707b88e4917d53ddecd4a9fb50e2ad075
generator: cartographer/4
baseline: 7387d3614aaae8d5a5bc156cf01c251d22b1dd45
---

# Module: plugins/freshen

## Purpose

Freshen is the tmux mechanics behind automatic context clearing: a plugin queues a /clear + re-invocation command as a signal file under .freshen/ (plugins/freshen/bin/freshen.sh:37-81), and the Stop and SessionStart(clear) hooks send /clear and the re-invocation via tmux send-keys, each confirmed by a bounded capture-pane read-back rather than fired blind (plugins/freshen/hooks/on-stop.sh, plugins/freshen/hooks/on-clear.sh, plugins/freshen/lib/pane-confirm.sh). The idea holding it together is confirmed, retryable delivery keyed off one durable signal file, so no other plugin needs to own its own tmux-clearing logic. Without it, phase-boundary context clearing (e.g. forge's) would lose its tmux automation and fall back to manual /clear instructions (plugins/freshen/skills/freshen/SKILL.md).

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

Freshen has no application types — its state lives entirely in flat files under the gitignored, ephemeral .freshen/ directory, and its 'objects' are shell function libraries.
- Signal files (.freshen/<source>.signal): one per source, created by `freshen.sh queue` (plugins/freshen/bin/freshen.sh:60-80), enforced single-pending-source across sources (plugins/freshen/bin/freshen.sh:64-73), consumed and deleted exactly once by on-clear.sh on confirmed send (plugins/freshen/hooks/on-clear.sh:97-99) — or left in place for the next Stop/clear cycle to retry when the send can't be confirmed (plugins/freshen/hooks/on-stop.sh:78-81, plugins/freshen/hooks/on-clear.sh:100-103).
- .clear-pending / .clear-consumed flags: at most one exists during a freshen-initiated clear window. on-stop.sh sets .clear-pending only after a confirmed /clear send (plugins/freshen/hooks/on-stop.sh:76); on-clear.sh hands it off by renaming (never deleting outright) to .clear-consumed (plugins/freshen/hooks/on-clear.sh:63-66) so a same-batch, unordered hook-guard hook still observes the flag regardless of run order.
- .disabled flag: a persistent kill switch toggled only by `freshen.sh enable`/`disable` (plugins/freshen/bin/freshen.sh:125-143); every hook and CLI subcommand checks it first and no-ops or warns if set.
- lib/pane-confirm.sh and lib/transition-log.sh own no state of their own — they are stateless function libraries sourced by both hooks; transition-log.sh does own .freshen/transitions.log, an append-only diagnostic log it self-trims to FRESHEN_LOG_MAX_LINES (default 500) on every append (plugins/freshen/lib/transition-log.sh:36-49).
- No in-process threading or shared memory; all coordination is cross-process via the filesystem, and ordering between different plugins' hooks on the same event is explicitly unguaranteed (plugins/freshen/hooks/on-clear.sh:37-45).

## External deps


## Gotchas

- Only one source may have a pending signal at a time; queuing from a second source while another's signal is unconsumed is a hard error, not a queue (plugins/freshen/bin/freshen.sh:64-73).
- Every hook exit path must write to stderr — a silent exit makes Claude Code report "No stderr output", which can otherwise trigger an infinite Stop-hook loop (plugins/freshen/hooks/on-stop.sh:13-16, plugins/freshen/hooks/on-clear.sh:12-14).
- .clear-pending is renamed to .clear-consumed rather than deleted outright, solely to survive an unspecified cross-plugin ordering race with hook-guard's own SessionStart(clear) hook reading the same flag (plugins/freshen/hooks/on-clear.sh:37-66).
- A capture-pane call that itself fails is treated as "still pending" (not confirmed) — an unobservable pane must never be assumed to have accepted input (plugins/freshen/lib/pane-confirm.sh:49-58).
- Literal-mode sends require both the literal-text send-keys call AND a separate Enter call to succeed before a signal counts as delivered; a failing Enter alone must not delete the signal (plugins/freshen/lib/pane-confirm.sh:88-105, plugins/freshen/hooks/on-clear.sh:84-103).
- Signals older than 2 hours are swept and deleted before dispatch on every Stop hook run (plugins/freshen/hooks/on-stop.sh:41).
