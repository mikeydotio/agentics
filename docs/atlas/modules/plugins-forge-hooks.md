---
module: plugins/forge/hooks
summary: "SessionStart/Stop hooks that inject forge resume context and durably checkpoint state on session end."
read_when: "Editing forge's SessionStart/Stop hooks or .forge checkpoint behavior"
sources:
  - path: plugins/forge/hooks/hooks.json
    blob: f92d8253799e799123a9e1506de7aa2e1bffcc0d
  - path: plugins/forge/hooks/session-start.sh
    blob: 55e528f206411f02c75004d42c7e3495a58f9776
  - path: plugins/forge/hooks/session-stop.bats
    blob: becc594025fde02ddff419447a2f7bb0d629853d
  - path: plugins/forge/hooks/session-stop.sh
    blob: f5819abc3450df0cdb6aa8824209a3461e70c7d9
generator: cartographer/4
baseline: 50c998d53e2ed58951ac5f794afd32bfa729f658
---

# Module: plugins/forge/hooks

## Purpose

hooks.json wires two Claude Code lifecycle hooks — SessionStart and Stop — that let a forge pipeline session survive an interrupted or crashed conversation without losing state or leaking its lock. SessionStart reads .forge/state.json and injects a compact additionalContext resume summary (status, session/story counts, and either a pre-computed resume object or a bare handoff filename) so a fresh session immediately knows a resume is needed. Stop performs a crash-safe, strictly-ordered checkpoint — write a degraded handoff, flip status to paused, release the lock — before any optional or bounded work (storyhook narrative, circuit breaker, freshen auto-resume signal), so a hung external command or a tripped breaker can never leave forge's on-disk state inconsistent.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

The durable checkpoint (status=paused, sessions_completed increment, resume-object write, then lock release) is unconditional and must complete before any optional or bounded work runs — plugins/forge/hooks/session-stop.sh:135-152. .forge/lock.json's presence while status is "running" is the session's exclusivity marker; session-stop.sh always removes it once the checkpoint lands, independent of circuit-breaker state — plugins/forge/hooks/session-stop.sh:95-105,152. The hook-guard circuit breaker (stop_guard_check) is consulted only after the checkpoint and gates solely the freshen auto-resume signal, never the checkpoint itself — plugins/forge/hooks/session-stop.sh:170-175. Both hooks are one-shot processes invoked per Claude Code lifecycle event (no persistent state/threading); session-start.sh treats a missing jq as a real environment defect rather than a silent "plugin inactive" skip, because .forge/state.json existing means forge is already active — plugins/forge/hooks/session-start.sh:29-35. Cross-plugin coordination is self-contained: session-stop.sh writes its own .freshen/forge.signal and sends /clear via tmux directly rather than depending on freshen's on-stop.sh observing the signal in the same Stop-hook batch, coordinating via the shared .freshen/.clear-pending marker to avoid a double /clear — plugins/forge/hooks/session-stop.sh:177-214.

## External deps


## Gotchas

F050: the circuit-breaker check used to run before any checkpoint work, so a tripped breaker's `exit 0` silently skipped the handoff write, status flip, and lock release; it now runs after the durable checkpoint and gates only the freshen signal — plugins/forge/hooks/session-stop.sh:16-26,170-175. F051: the storyhook `story handoff` call used to run before the checkpoint with no timeout, so a hung `story` process could burn the whole 15s hook budget; it now runs after the checkpoint, bounded by a 5s run_with_timeout (falling back to gtimeout, or exit 127 if neither exists) — plugins/forge/hooks/session-stop.sh:78-92,154-168. F054: a malformed/partially-written state.json used to fail the jq read and exit 0 completely silently, leaving the agent with zero resume hint; both hooks now log to stderr, and session-start.sh additionally emits a fallback additionalContext pointing at /forge status — plugins/forge/hooks/session-start.sh:38-55, plugins/forge/hooks/session-stop.sh:52-59. F055: session duration is computed via jq's fromdate/now (never GNU-only `date -d`, which errors on BSD/macOS), with try/catch degrading an unparseable timestamp to "unknown" rather than crashing — plugins/forge/hooks/session-stop.sh:64-76. Every exit path is wrapped in an EXIT trap that always writes to stderr, specifically to avoid Claude Code's "No stderr output" feedback creating an infinite Stop-hook conversation loop — plugins/forge/hooks/session-stop.sh:10-14. session-stop.sh sends /clear itself instead of relying on freshen's on-stop.sh to notice its signal file in the same Stop event, because Claude Code does not guarantee hook execution order across plugins; the .freshen/.clear-pending marker prevents both hooks from double-sending when they do run in the same batch — plugins/forge/hooks/session-stop.sh:196-214.
