---
module: "plugins/forge/references (chunk 1)"
summary: "Forge's execution-loop, locking, handoff, recovery, storyhook-contract, and questioning protocol specs."
read_when: "Changing forge's execution loop, locking, handoffs, recovery, or storyhook protocol"
sources:
  - path: plugins/forge/references/auto-resume.md
    blob: dc5887c9b340e44d76271c729dfdbbcc99376310
  - path: plugins/forge/references/deterministic-checks.md
    blob: b869a9700e37e93c12665ca5af66df0ca15cffdc
  - path: plugins/forge/references/entry-guards.md
    blob: 547bc14e21414f57349ae8bee086dcff2d981049
  - path: plugins/forge/references/execution-loop.md
    blob: 9f33f6ca1ec8014371cb46c3034b5ef237bc89e4
  - path: plugins/forge/references/handoff-format.md
    blob: bebc349f4bc0932acb4b737d87d1ec4335f5afc3
  - path: plugins/forge/references/questioning.md
    blob: 9f9b36d86b68aad50152e4f7ab637218afdc1cb1
  - path: plugins/forge/references/recovery-protocol.md
    blob: 64ee83b8c796ab30f6b3239ac90f09048ae23f6a
  - path: plugins/forge/references/report-format.md
    blob: c71f4cb3e84e1a3b4b2775d907c22befb2dcac02
  - path: plugins/forge/references/session-locking.md
    blob: 448161ab0fd0d5b9202e3ab666841cd7dfc59c55
  - path: plugins/forge/references/severity-levels.md
    blob: f41c2141dfb7430c96eb7813c48c21010f8a709b
  - path: plugins/forge/references/step-handoff.md
    blob: f06c7404795e377e76b1933f7c8d7edb9942d416
  - path: plugins/forge/references/story-decomposition.md
    blob: cbb0701534b06b4f5521c8112f184573dbbb5834
  - path: plugins/forge/references/storyhook-contract.md
    blob: 4a9c083a8d5c6d0edb4b71d9cd5291e22ff3b166
generator: cartographer/4
baseline: 50c998d53e2ed58951ac5f794afd32bfa729f658
---

# Module: plugins/forge/references (chunk 1)

## Purpose

The detailed protocol layer forge's step skills (a separate module) dispatch to for anything beyond "call a script and branch on its JSON" — the execution loop's full state machine, session locking, handoff/recovery formats, the storyhook CLI contract, severity/report conventions, and the interrogation questioning method. It keeps skill files thin: locking semantics, the execute loop's state-transition table, and storyhook's quirks (nested JSON envelopes, non-idempotent state/type registration, the permanently-unreachable project story) live here exactly once instead of being re-derived per skill. If these docs vanished, every step skill would have to reconstruct forge's crash-recovery, handoff, and storyhook-integration behavior from scratch, and the copies would inevitably drift out of sync with the actual bin/ scripts they describe.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

- `.forge/state.json`'s `status` is only ever `"running"` or `"paused"` — there is no `"complete"` value; whether execution hands off to review_validate is decided by storyhook + `forge-state.sh`, never state.json alone (plugins/forge/references/execution-loop.md:463-468, plugins/forge/references/recovery-protocol.md:29-32).
- `.forge/lock.json` (gitignored, ephemeral) holds `holder`/`acquired_at`/`heartbeat_at` and must never be read or written directly except through `bin/forge-lock.sh` — the one sanctioned exception is `hooks/session-stop.sh`, which `rm -f`s it directly on every exit path (plugins/forge/references/session-locking.md:9-23, plugins/forge/references/session-locking.md:59-62).
- `.forge/COMPLETION.md` is owned exclusively by the deploy step; the execute loop's Complete path must never write it even though "all stories done" sounds terminal, because `forge-state.sh` treats its mere existence as the whole-pipeline-finished signal (plugins/forge/references/execution-loop.md:396-402).
- decompose's synthetic `project_story` (the auto-created parent of every task story) can never reach `done` through the normal execution loop — storyhook's `story next` permanently refuses any story with children — so `forge-state.sh` explicitly excludes it from its "all done" computation rather than the loop special-casing it (plugins/forge/references/story-decomposition.md:88-102, plugins/forge/references/execution-loop.md:404-416).
- A session handoff is backed by four independent persistence layers (config.json + state.json, handoff-execute.md, verdicts.jsonl, storyhook) with different tracked/ephemeral status each — only config.json and the handoff file are committed to git (plugins/forge/references/handoff-format.md:9-19).

## External deps


## Gotchas

- `story decompose` treats every Markdown heading in its input as a story, not just `### Wave N` headings — piping full PLAN.md verbatim would spawn spurious stories from `## Test Strategy`/`## Resumption Points`/`## Risk Register`; decompose extracts only the `## Task Breakdown` section first (plugins/forge/references/story-decomposition.md:42-57, plugins/forge/references/storyhook-contract.md:265-268).
- Neither `story graph`'s JSON nor text output reports `blocked-by` cycles, and `story doctor` only catches parent/child cycles — visually eyeballing `story graph` for cycles has been observed experimentally to miss a real one; DAG validation must go through `bin/forge-dag-validate.sh`'s DFS instead (plugins/forge/references/storyhook-contract.md:270-286).
- The deterministic stub-grep pre-check deliberately does NOT flag bare `stub`/`placeholder`/`XXX` substrings (only whole-word TODO/FIXME/HACK and named "unimplemented" idioms), because the broader match false-positived on legitimate code like a form field's `placeholder` prop (plugins/forge/references/deterministic-checks.md:22-27).
- Nothing refreshes the session lock's heartbeat *during* a single long-running generator/evaluator subagent call, only at three bracketing points — a story whose subagent legitimately outruns the heartbeat window can still go stale-locked mid-spawn (known gap F095, plugins/forge/references/session-locking.md:94-101).
- Two independent Stop-event hooks (forge's and freshen's) both write/read `.freshen/.clear-pending` with no guaranteed execution order; forge's hook sends `/clear` itself rather than relying on freshen's hook to notice the signal first, to avoid silently stranding it if freshen's hook happened to run first (plugins/forge/references/auto-resume.md:67-89).
