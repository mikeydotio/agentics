---
module: plugins/forge/agent-overrides
summary: "Forge-only constraint blocks appended to shared agent definitions at spawn time"
read_when: "Changing forge subagent behavior, .forge/ artifact contracts, or spawn constraints"
sources:
  - path: plugins/forge/agent-overrides/evaluator-context.md
    blob: b4715b5bee3329bda946a53974d2181bc0edb1d4
  - path: plugins/forge/agent-overrides/generator-context.md
    blob: 890854c3045a23300025d08ae29648d89a3df3cb
  - path: plugins/forge/agent-overrides/reviewer-context.md
    blob: bdb0d4c562ebcd72aa17d554874c7dd54978138c
  - path: plugins/forge/agent-overrides/triager-context.md
    blob: dafbb15a8c519f18741996c8e385c616b2c1d7fe
  - path: plugins/forge/agent-overrides/validator-context.md
    blob: 6c5cdda4751783942cd670dab20b4ca42bb065b3
references_modules: [plugins-agents-agents-chunk-1, plugins-agents-agents-chunk-2, plugins-agents-agents-chunk-3]
generator: cartographer/1
baseline: 65c6f5e8e65713af63741fbe8d498384f530200e
verified: true
---

# Module: plugins/forge/agent-overrides

## Purpose

The pipeline-override layer of forge's agent spawning. Each file is a constraint block the
forge orchestrator concatenates after a shared agent definition from the agents plugin, so
shared prompts stay pipeline-neutral while spawned agents still learn forge's contracts:
`.forge/` artifact paths, story-state expectations, and the integrity checks run around each
spawn. Remove these and forge's agents lose the no-commit rule, report locations, severity
vocabulary, and FIX/ESCALATE routing.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `Forge-Specific Evaluator Constraints` | override block | `plugins/forge/agent-overrides/evaluator-context.md:1` | Evaluator must modify zero files or its verdict is discarded and the story blocked; deterministic pre-check results arrive in-context and must inform the verdict; verdict JSON ≤4KB with retry-actionable `failures` entries |
| `Forge-Specific Generator Constraints` | override block | `plugins/forge/agent-overrides/generator-context.md:1` | Generator never commits and never touches `.forge/` (checksum-enforced); implements exactly one story's acceptance criteria; JSON output ≤4KB |
| `Forge-Specific Reviewer Context` | override block | `plugins/forge/agent-overrides/reviewer-context.md:1` | Reviews the committed codebase as a whole, not story diffs; writes `.forge/REVIEW-REPORT.md`; findings use CRITICAL/IMPORTANT/ADVISORY severities for triage |
| `Forge-Specific Triager Context` | override block | `plugins/forge/agent-overrides/triager-context.md:1` | Reads both step reports plus `.forge/config.json` (`when_in_doubt`, `yolo_mode`); writes `.forge/TRIAGE.md`; FIX findings route to a generator, ESCALATE to the user via `AskUserQuestion`; yolo mode caps at 10 fix cycles |
| `Forge-Specific Validator Context` | override block | `plugins/forge/agent-overrides/validator-context.md:1` | Hardens tests for the entire implemented codebase; writes `.forge/VALIDATE-REPORT.md`; new test files follow the project's existing naming convention |

## Load-bearing internals

None — each file is a single flat constraint block; its full contract is in the Public API table.

## Relationships

- `plugins-forge-agent-overrides.evaluator-context -> plugins-agents-agents-chunk-1.evaluator (extends)`
- `plugins-forge-agent-overrides.generator-context -> plugins-agents-agents-chunk-1.generator (extends)`
- `plugins-forge-agent-overrides.reviewer-context -> plugins-agents-agents-chunk-2.reviewer (extends)`
- `plugins-forge-agent-overrides.triager-context -> plugins-agents-agents-chunk-3.triager (extends)`
- `plugins-forge-agent-overrides.validator-context -> plugins-agents-agents-chunk-3.validator (extends)`

## Type notes

- Generator spawns on a clean tree (`plugins/forge/agent-overrides/generator-context.md:9`)
- Evaluator verdict selects `done` or retry (`plugins/forge/agent-overrides/evaluator-context.md:9`)
- `.forge/` state files are checksummed (`plugins/forge/agent-overrides/generator-context.md:5`)
- Outputs land as storyhook comments, ≤4KB (`plugins/forge/agent-overrides/evaluator-context.md:7`)
- Review and validate run as parallel steps (`plugins/forge/agent-overrides/reviewer-context.md:3`)
- Both reports are declared triager inputs (`plugins/forge/agent-overrides/triager-context.md:5`)
- `when_in_doubt` defaults to escalate (`plugins/forge/agent-overrides/triager-context.md:8`)
- `.forge/verdicts.jsonl` has test history (`plugins/forge/agent-overrides/validator-context.md:9`)

## External deps

- storyhook — story tracker; verdict/output JSON is stored as story comments capped at 4KB
- git — overrides assume orchestrator-run `git diff --name-only` and `git checkout .` checks

## Gotchas

- Only FIX and ESCALATE verdicts get routes (`plugins/forge/agent-overrides/triager-context.md:11`)
- H2 naming mixes Constraints and Context (`plugins/forge/agent-overrides/reviewer-context.md:1`)
