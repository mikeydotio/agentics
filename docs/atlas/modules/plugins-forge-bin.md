---
module: plugins/forge/bin
summary: "Forge's deterministic shell layer — artifact-driven state machine, status, prechecks, step-exit, archives"
read_when: "Changing forge state detection, step transitions, execute prechecks, or .forge archiving"
sources:
  - path: plugins/forge/bin/forge-archive.bats
    blob: f754dcb6446ba9a569f3b03cce3c2dcfce2a2b7e
  - path: plugins/forge/bin/forge-archive.sh
    blob: c3423e09b2e3b9c60f47dca03a2b60bfece5a538
  - path: plugins/forge/bin/forge-fix-archive.bats
    blob: 53f0cc7dcb48f4f722745be6652c97eb268f81b1
  - path: plugins/forge/bin/forge-fix-archive.sh
    blob: 856351c82edf19d73a4216c55f5e505d28ef0883
  - path: plugins/forge/bin/forge-prechecks.bats
    blob: f3f37c85c73d74a68524debf8702dd027e8f214e
  - path: plugins/forge/bin/forge-prechecks.sh
    blob: 3a13af0af4431bb1849f2894a95d8b74a58002d4
  - path: plugins/forge/bin/forge-state.sh
    blob: 9714a17958e0474b38bbe16e3bf274fe3089bf82
  - path: plugins/forge/bin/forge-state.test.bats
    blob: 52d217e63755effa17b21da964ad77ec63ec071e
  - path: plugins/forge/bin/forge-status.bats
    blob: f867fd01545e4ee29c76113cd7771d43b11e6dd3
  - path: plugins/forge/bin/forge-status.sh
    blob: f2b83fb7bb63b79a63465c4c0a4ece1b7213dbcd
  - path: plugins/forge/bin/forge-step-exit.bats
    blob: b24f5876a48be789f28ce24e262ce7c8193b016c
  - path: plugins/forge/bin/forge-step-exit.sh
    blob: 3266bf2642e68d13caeb57060be61bb1fdeae442
references_modules: [plugins-freshen, plugins-forge-skills, plugins-forge-references]
generator: cartographer/2
baseline: b4cedefaba8df96ee167877bf2ee9c3143ef0b08
---

# Module: plugins/forge/bin

## Purpose

Deterministic substrate beneath the forge orchestrator: every pipeline decision computable
without an LLM — next step, precheck verdict, step exit — is a standalone bash script printing
one jq-built JSON object for the calling skill. State is derived, never stored: each call
recomputes the next step from which artifacts exist under `.forge/`, so forge resumes after
interruptions and context clears. The `.bats` files pin each script's JSON contract.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `forge-archive.sh` | script | `plugins/forge/bin/forge-archive.sh:2` | Tarballs `.forge/` to `<archive-dir>/forge-<slug>-<timestamp>.tar.gz`, then deletes `.forge/` |
| `forge-fix-archive.sh` | script | `plugins/forge/bin/forge-fix-archive.sh:2` | Moves TRIAGE.md, PLAN.md, plan-mapping.json into `.forge/fix-cycles/cycle-<N>`; N is zero-based |
| `forge-prechecks.sh` | script | `plugins/forge/bin/forge-prechecks.sh:4` | Execute-loop gate: tests, linter, stub grep, scope check; emits `{ok, all_passed, checks, display}` |
| `forge-state.sh` | script | `plugins/forge/bin/forge-state.sh:1` | Router input: derives `{state, dispatch, fix_cycle, yolo, has_handoff, artifacts}` from `.forge/` |
| `forge-status.sh` | script | `plugins/forge/bin/forge-status.sh:2` | Dashboard JSON: display string, artifact checklist, execution progress, fix cycles, handoffs |
| `forge-step-exit.sh` | script | `plugins/forge/bin/forge-step-exit.sh:2` | Commits `.forge/` as `forge(<step>): <summary>`, pauses state.json, queues freshen re-invocation |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `check_storyhook` | function | `plugins/forge/bin/forge-state.sh:112` | Probes `story` CLI; `stories_all_done` gates execute→review_validate, ESCALATE titles gate pause_escalate |
| `detect_state` | function | `plugins/forge/bin/forge-state.sh:144` | State machine: first-match chain testing latest-stage artifacts first; emits `<skill> --orchestrated` dispatch |
| `detect_test_cmd` | function | `plugins/forge/bin/forge-prechecks.sh:35` | Test autodetect order: npm test, pytest, cargo test, make test, tests/run-tests.sh; `detect_lint_cmd` mirrors it |
| `has_fix_items` | function | `plugins/forge/bin/forge-state.sh:82` | awk for a `- ` item under a `## FIX` heading in TRIAGE.md; picks fix_loop vs document after triage |
| `read_config` | function | `plugins/forge/bin/forge-state.sh:51` | `.forge/config.json` defaults: yolo=false, max_fix_cycles=3, max_fix_cycles_yolo=10 → effective max |
| `run_scope_check` | function | `plugins/forge/bin/forge-prechecks.sh:209` | Diffs modified files vs the story's `files_expected` in plan-mapping.json; warning-only, never fails |

## Relationships

- `plugins-forge-bin.forge-step-exit.sh -> plugins-freshen.freshen.sh (calls)` — `plugins/forge/bin/forge-step-exit.sh:46`
- `plugins-forge-skills.SKILL -> plugins-forge-bin.forge-state.sh (calls)` — `plugins/forge/skills/forge/SKILL.md:64`
- `plugins-forge-skills.SKILL -> plugins-forge-bin.forge-status.sh (calls)` — `plugins/forge/skills/forge/SKILL.md:236`
- `plugins-forge-skills.SKILL -> plugins-forge-bin.forge-step-exit.sh (calls)` — `plugins/forge/skills/forge/SKILL.md:222`
- `plugins-forge-skills.SKILL -> plugins-forge-bin.forge-archive.sh (calls)` — `plugins/forge/skills/forge/SKILL.md:109`
- `plugins-forge-skills.SKILL -> plugins-forge-bin.forge-fix-archive.sh (calls)` — `plugins/forge/skills/forge/SKILL.md:167`
- `plugins-forge-references.execution-loop -> plugins-forge-bin.forge-prechecks.sh (calls)` — `plugins/forge/references/execution-loop.md:131`

## Type notes

- Soft failures keep exit 0 with `{ok: false, error}` (plugins/forge/bin/forge-archive.sh:11).
- `.forge/state.json` is the only mutable state; read at plugins/forge/bin/forge-status.sh:87.
- Step exit writes `status: "paused"` + resume command (plugins/forge/bin/forge-step-exit.sh:35).
- This guards the freshen signal from session-stop.sh (plugins/forge/bin/forge-step-exit.sh:32).
- `dispatch` is empty for complete and pause states (plugins/forge/bin/forge-state.sh:148-161).
- fix_loop re-enters the pipeline at plan, not execute (plugins/forge/bin/forge-state.sh:167).
- `forge-status.sh` has its own coarser `detect_state` (plugins/forge/bin/forge-status.sh:49).
- Only `forge-state.sh` dispatch drives routing; status state names diverge from it.

## External deps

- jq — builds every JSON output; hard requirement
- story (storyhook CLI) — optional; probed via `command -v` (plugins/forge/bin/forge-state.sh:118)
- git — diffs for stub/scope checks; step-exit commit
- tar — archive creation; size via GNU/BSD `stat` fallback
- bats — runs the `*.bats` contract files

## Gotchas

- Two bats files load their script as a sibling (plugins/forge/bin/forge-state.test.bats:3).
- Four resolve `../plugins/forge/bin/` from the test dir (plugins/forge/bin/forge-status.bats:4).
- That path only resolves one level under the repo root, never in place.
- Step exit dies pre-JSON if `git commit` fails (plugins/forge/bin/forge-step-exit.sh:29).
- Tests retry once; a retry pass is reported flaky (plugins/forge/bin/forge-prechecks.sh:76).
- The tarball includes gitignored runtime files (plugins/forge/bin/forge-archive.sh:32).
