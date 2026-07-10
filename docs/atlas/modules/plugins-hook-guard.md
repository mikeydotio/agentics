---
module: plugins/hook-guard
summary: "Shared circuit breaker that halts runaway Stop-hook loops and resets safely across SessionStart events."
read_when: "Touching Stop hooks, stop_guard_check/stop_guard_reset, or hook-loop protection"
sources:
  - path: plugins/hook-guard/.claude-plugin/plugin.json
    blob: e2b680e6c4facf11c9959e11c9586de0609d2170
  - path: plugins/hook-guard/hooks/hooks.json
    blob: d22a3169ebee8171c0149fd33e18c5f191b39144
  - path: plugins/hook-guard/hooks/session-start.bats
    blob: d0fef980e4026dbe472957321842098e21b3b4b4
  - path: plugins/hook-guard/hooks/session-start.sh
    blob: 4f29deec3b0e13b0c5ba7fcf07a718d30b638576
  - path: plugins/hook-guard/lib/stop-guard.bats
    blob: 0842673b5637640ff30a3b227c0d25a743840086
  - path: plugins/hook-guard/lib/stop-guard.sh
    blob: 49f74442f37222609fae8f05736c66d3ca7fcaea
  - path: plugins/hook-guard/tests/run-tests.sh
    blob: 3328ae66d73fa45c77f307c11b8d38fba1e63adf
generator: cartographer/4
baseline: a4486d2b70ad4124762f9d777af6a7dc007bdc6c
---

# Module: plugins/hook-guard

## Purpose

hook-guard is a shared circuit breaker that stops runaway Stop-hook loops: it counts Stop events per project within a rolling window and, past a threshold, tells the calling Stop hook to halt instead of continuing (plugins/hook-guard/lib/stop-guard.sh:15-16,47-93). Its SessionStart hook resets that counter on genuine fresh sessions but deliberately withholds the reset while a freshen-initiated /clear is mid-transition, so a freshen-mediated loop can still accumulate enough ticks to trip rather than having its counter wiped every /clear cycle (plugins/hook-guard/hooks/session-start.sh:5-37,88-115). Without this module, any plugin's Stop hook (e.g. forge's or freshen's own /clear+re-invoke cycle) has nothing to detect or halt an infinite loop.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

The breaker's state file lives outside the repo in /tmp (OS-reclaimed), keyed by hashing CLAUDE_PROJECT_DIR so each project gets its own guard file and cross-project state never mixes (plugins/hook-guard/lib/stop-guard.sh:30-45). stop_guard_check/stop_guard_reset are meant to be sourced and called from OTHER plugins' Stop and SessionStart hooks, not invoked standalone — this module owns the breaker's on-disk state format (newline-separated epoch-second ticks) but not the hooks that call it (plugins/hook-guard/lib/stop-guard.sh:2-13). plugins/hook-guard/hooks/session-start.sh is hook-guard's own SessionStart hook and is the sole reader/deleter of `.freshen/.clear-consumed` in the project dir; it never deletes `.freshen/.clear-pending` itself, since that flag's lifecycle is owned by freshen's on-clear.sh (plugins/hook-guard/hooks/session-start.sh:33-37,88-114).

## External deps


## Gotchas

The Stop-hook dedup window collapses two hooks firing for the same Stop event into one tick by wall-clock proximity, not a shared event id — any hook call within STOP_GUARD_DEDUP_WINDOW (default 2s) of the last tick is treated as a duplicate (plugins/hook-guard/lib/stop-guard.sh:17-28,55-68). A guard-file write failure now fails loud (a stderr WARNING) rather than silently disarming the breaker (plugins/hook-guard/lib/stop-guard.sh:63-67). Without md5sum (stock macOS), the guard key falls back to BSD md5, then to an unhashed sanitized project path if neither is available (plugins/hook-guard/lib/stop-guard.sh:33-43). SessionStart(clear) deliberately skips the breaker reset when a freshen-initiated /clear is pending, using a `.freshen/.clear-pending` -> `.clear-consumed` rename handoff to stay correct regardless of the unspecified relative order of hook-guard's and freshen's SessionStart(clear) hooks (plugins/hook-guard/hooks/session-start.sh:5-68). `.clear-consumed` is trusted as this event's handoff only within CLEAR_CONSUMED_WINDOW (default 5s) of its mtime, because a stale leftover from an already-fully-processed prior event could otherwise wrongly suppress an unrelated later reset (plugins/hook-guard/hooks/session-start.sh:39-68,92-114); hook-guard is documented as the sole reader/deleter of that marker, and always deletes it whether fresh or stale (plugins/hook-guard/hooks/session-start.sh:98-114).
