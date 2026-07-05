---
module: "plugins/forge/bin (chunk 3)"
summary: "Forge's state machine detector, canonical step-exit protocol, status dashboard, and transition/verdict telemetry."
read_when: "Touching forge's state detection, step-exit, or transition/verdict logging"
sources:
  - path: plugins/forge/bin/forge-state.sh
    blob: 972733c9b3315584f09099e593f09e2c28221e2d
  - path: plugins/forge/bin/forge-state.test.bats
    blob: c9151170fecde0f834fe8fc5949b60731b55c27d
  - path: plugins/forge/bin/forge-status.bats
    blob: 1bacb7aaaf16c922cd535c5f9c38b195f74b31d2
  - path: plugins/forge/bin/forge-status.sh
    blob: 8a0fcfb43935bf083d0c9f5a8ede4b96a4cfd917
  - path: plugins/forge/bin/forge-step-exit.bats
    blob: 7f694c11934d887e833ea7258249860519722c79
  - path: plugins/forge/bin/forge-step-exit.sh
    blob: 519e47eb0acad389d0cdb1f3ed37a25255962d35
  - path: plugins/forge/bin/forge-transition-report.bats
    blob: 4376ec6fe6580c23a58c98965f7e553b98ce9d83
  - path: plugins/forge/bin/forge-transition-report.sh
    blob: 1d2b1bc0495d26ce5fe0b3b003d7c379eea97280
  - path: plugins/forge/bin/forge-verdict.bats
    blob: 76893d61d97d21088036231f3440f8408a8c66d2
  - path: plugins/forge/bin/forge-verdict.sh
    blob: 51d97c1685fb3704c20ab1a38dd6f1f068647148
  - path: plugins/forge/bin/state-json-atomicity.bats
    blob: b5f6efc93c499663906bf21c7386af4dc30660f3
generator: cartographer/4
baseline: 50c998d53e2ed58951ac5f794afd32bfa729f658
---

# Module: plugins/forge/bin (chunk 3)

## Purpose

This module is forge's deterministic backbone: forge-state.sh (plugins/forge/bin/forge-state.sh) is the single source of truth for "what state is the pipeline in and what should run next," derived purely from artifact presence plus a storyhook query and never persisted, with a category/auto_advance classification alongside dispatch so callers stop string-matching dispatch to know whether a transition is a safe pass-through or needs human/side-effecting handling. forge-status.sh renders a dashboard entirely from forge-state.sh's output rather than re-deriving state, and forge-step-exit.sh is the one canonical exit path every pipeline skill calls to stage/commit .forge/, update state.json, and queue or cancel the freshen re-invocation signal. forge-transition-report.sh and forge-verdict.sh are the pipeline's audit layer, correlating predicted-vs-actual step transitions and recording durable per-attempt evaluator verdicts; without this module forge would have no consistent way to decide the next step, safely persist progress, or detect state-machine drift.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `expected_step` | def | `plugins/forge/bin/forge-transition-report.sh:79` | Given a predicted record, returns its step name if dispatch is step-shaped (ends " --orchestrated"), else null; used to flag mismatches. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

category/auto_advance: category is set explicitly at every branch of detect_state() (plugins/forge/bin/forge-state.sh:351-459), and auto_advance is a pure derived view (category == "pass_through") computed once, never independently recomputed (plugins/forge/bin/forge-state.sh:485-491) -- it cannot drift from category by construction.
transition_id lifecycle: forge-state.sh mints a "predicted" correlator as PID+RANDOM (plugins/forge/bin/forge-state.sh:500); forge-step-exit.sh accepts it via --transition-id, defaulting to the literal string "none" when omitted (plugins/forge/bin/forge-step-exit.sh:52,66-67,71); forge-transition-report.sh joins predicted and actual records by that id, never by log position (plugins/forge/bin/forge-transition-report.sh:84-106).
forge-state.sh is deliberately read-only/side-effect-free: read_project_story notes it must stay a pure detector because it's invoked from many non-execute contexts (hooks, /forge status) (plugins/forge/bin/forge-state.sh:257-258).
state.json is always written via temp-file+rename, never a direct redirect, so a concurrent reader (forge-state.sh, forge-status.sh) can never observe a partial write (plugins/forge/bin/forge-step-exit.sh:111-118); this is a structural invariant enforced by plugins/forge/bin/state-json-atomicity.bats.
forge-verdict.sh's verdicts.jsonl is append-only, one self-contained JSON object per line, matching the evaluator's unified verdict schema (plugins/forge/bin/forge-verdict.sh:88-98).

## External deps


## Gotchas

The byte-identical dispatch trap: fix_loop's dispatch is literally the string "plan --orchestrated", identical to a plain design->plan pass-through; only category/state (checked first, never dispatch) tells them apart (plugins/forge/bin/forge-state.sh:364-368; regression test plugins/forge/bin/forge-state.test.bats:811-827).
The decompose-created "project story" deadlock: storyhook's `story next` permanently excludes any story with children, so the auto-created parent story from `story decompose` must be explicitly excluded from the "all stories done" computation or execute wedges forever (plugins/forge/bin/forge-state.sh:242-264; regression test plugins/forge/bin/forge-state.test.bats:555-585).
jq length vs. shell grep counting pitfall: computing the non-done count via `echo "$states" | grep -cv '^done$'` on an empty selection would count grep's single blank line as one non-done entry, permanently wedging stories_all_done false; check_storyhook uses jq's `length` instead (plugins/forge/bin/forge-state.sh:292-296; regression test plugins/forge/bin/forge-state.test.bats:609-634).
F102 minimal-shape check: an artifact only counts as "present" once non-empty and (for .md) containing a top-level `^# ` heading anywhere, or (for .json) parsing -- guards against a truncated/zero-byte file left by a mid-write /clear or Stop-hook timeout silently advancing the state machine (plugins/forge/bin/forge-state.sh:48-72).
F053 no-op commit guard: a plain `git commit` with nothing staged aborts the whole script under `set -e`; forge-step-exit.sh checks `git diff --cached --quiet` first so a no-op commit (a common, healthy case) still lets state.json update and freshen queue (plugins/forge/bin/forge-step-exit.sh:81-101).
forge-step-exit.sh silences freshen.sh's own stdout/stderr on the --next path specifically because freshen's human-readable confirmation line would otherwise print before this script's final JSON and corrupt output for any caller parsing it as JSON (plugins/forge/bin/forge-step-exit.sh:154-160).
