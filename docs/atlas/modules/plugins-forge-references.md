---
module: plugins/forge/references
summary: "Normative protocol docs forge skills follow — execution loop, handoffs, locking, severity levels, storyhook usage"
read_when: "Changing forge pipeline behavior — execution, handoffs, locking, severity, or storyhook"
sources:
  - path: plugins/forge/references/auto-resume.md
    blob: f08e31722891c8c40194feec34341f00c4f0ce61
  - path: plugins/forge/references/deterministic-checks.md
    blob: 4261c10f757a0f67609092542d76259c8134e24c
  - path: plugins/forge/references/execution-loop.md
    blob: df4ece58caec141b4c0d3e49700200248e9d6610
  - path: plugins/forge/references/handoff-format.md
    blob: 6bb82e1a149da9abd95e5923561ed6a8a1b9f808
  - path: plugins/forge/references/questioning.md
    blob: 9f9b36d86b68aad50152e4f7ab637218afdc1cb1
  - path: plugins/forge/references/recovery-protocol.md
    blob: 7cd1e8561b87e990af9ae32d622cddc976b26b1f
  - path: plugins/forge/references/report-format.md
    blob: c71f4cb3e84e1a3b4b2775d907c22befb2dcac02
  - path: plugins/forge/references/session-locking.md
    blob: a3f87ff06ff260ab6353c60be5f80d94fb83ca56
  - path: plugins/forge/references/severity-levels.md
    blob: f41c2141dfb7430c96eb7813c48c21010f8a709b
  - path: plugins/forge/references/step-handoff.md
    blob: 0fa2df5a74a6ad8edd339c69c970d065508212e6
  - path: plugins/forge/references/story-decomposition.md
    blob: 2aebf1da6724d05df0c737f93e309bdb4059c0f1
  - path: plugins/forge/references/storyhook-contract.md
    blob: 507554192f69294961f0bda40316ed8af6fc645b
  - path: plugins/forge/references/team-roles.md
    blob: 587d89762323b17885001c1b5471a304f8fb47e9
  - path: plugins/forge/references/verification-protocol.md
    blob: d8bc49795bc4f87f355994db97a5b084ba2c82be
references_modules: [plugins-agents-agents-chunk-1, plugins-agents-agents-chunk-2, plugins-agents-references, plugins-forge-bin, plugins-forge-hooks, plugins-forge-skills, plugins-freshen]
generator: cartographer/2
baseline: b4cedefaba8df96ee167877bf2ee9c3143ef0b08
---

# Module: plugins/forge/references

## Purpose

Forge's methodology layer: normative contracts that step skills load at dispatch time, keeping
each SKILL.md a thin router — `execution-loop` names itself the dispatch target for `/forge run`
(`plugins/forge/references/execution-loop.md:3`). Execution mechanics, pipeline transitions, and
a findings vocabulary review and validate share so triage parses both reports uniformly
(`plugins/forge/references/report-format.md:3`).

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `Agent Team Roles` | doc | `plugins/forge/references/team-roles.md:1` | Roster + spawn matrix; spawns always foreground |
| `Auto-Resume` | doc | `plugins/forge/references/auto-resume.md:1` | Freshen pause→clear→resume; tmux or manual |
| `Deterministic Pre-Checks` | doc | `plugins/forge/references/deterministic-checks.md:1` | Pre-evaluator gate: tests, lint, stubs, scope |
| `Execution Loop` | doc | `plugins/forge/references/execution-loop.md:1` | Authoritative run/resume loop spec |
| `Handoff Format` | doc | `plugins/forge/references/handoff-format.md:1` | Session handoff + four persistence layers |
| `Questioning Methodology` | doc | `plugins/forge/references/questioning.md:1` | One AskUserQuestion at a time, pros/cons options |
| `Recovery Protocol` | doc | `plugins/forge/references/recovery-protocol.md:1` | Resume order: lock, state, handoff, crash reset |
| `Report Format` | doc | `plugins/forge/references/report-format.md:1` | Finding shape shared by review and validate |
| `Session Locking` | doc | `plugins/forge/references/session-locking.md:1` | Heartbeat lock, `.forge/lock.json`; no PID checks |
| `Severity Levels` | doc | `plugins/forge/references/severity-levels.md:1` | Critical/Important/Useful + triage defaults |
| `Step Handoff Format` | doc | `plugins/forge/references/step-handoff.md:1` | Step exit protocol + rollback file map |
| `Story Decomposition` | doc | `plugins/forge/references/story-decomposition.md:1` | PLAN.md→stories; `plan_hash` idempotency |
| `Storyhook Command Contract` | doc | `plugins/forge/references/storyhook-contract.md:1` | MCP-vs-CLI selection; structured JSON comments |
| `Verification Protocol` | doc | `plugins/forge/references/verification-protocol.md:1` | Evaluator debiasing + JSON verdict schema |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `Cold-Start Essentials` | section | `plugins/forge/references/handoff-format.md:96` | The only session knowledge surviving `/clear` |
| `Interface Selection Guide` | section | `plugins/forge/references/storyhook-contract.md:5` | Batch ops via MCP; one-liners via `story` CLI |
| `State Transition Summary` | section | `plugins/forge/references/execution-loop.md:344` | Canonical story state machine |
| `Step Exit Protocol` | section | `plugins/forge/references/step-handoff.md:17` | artifacts→handoff→commit→freshen→STOP each step |

## Relationships

- `plugins-forge-hooks.session-stop.sh -> plugins-forge-references.auto-resume (implements)`
- `plugins-forge-references.auto-resume -> plugins-freshen.freshen.sh (calls)`
- `plugins-forge-references.execution-loop -> plugins-agents-agents-chunk-1.evaluator (reads)`
- `plugins-forge-references.execution-loop -> plugins-agents-agents-chunk-1.generator (reads)`
- `plugins-forge-references.execution-loop -> plugins-agents-agents-chunk-2.software-architect (calls)`
- `plugins-forge-references.execution-loop -> plugins-forge-bin.forge-prechecks.sh (calls)`
- `plugins-forge-references.step-handoff -> plugins-freshen.freshen.sh (calls)`
- `plugins-forge-references.team-roles -> plugins-agents-references.agent-catalog (reads)`
- `plugins-forge-skills.decompose -> plugins-forge-references.story-decomposition (reads)`
- `plugins-forge-skills.execute -> plugins-forge-references.execution-loop (reads)`
- `plugins-forge-skills.execute -> plugins-forge-references.verification-protocol (reads)`
- `plugins-forge-skills.forge -> plugins-forge-references.step-handoff (reads)`
- `plugins-forge-skills.interrogate -> plugins-forge-references.questioning (reads)`
- `plugins-forge-skills.research -> plugins-forge-references.team-roles (reads)`
- `plugins-forge-skills.review -> plugins-forge-references.report-format (reads)`
- `plugins-forge-skills.validate -> plugins-forge-references.severity-levels (reads)`

## Type notes

- `.forge/handoff.md` is ephemeral and untracked (`plugins/forge/references/handoff-format.md:12`).
- Step handoffs are committed at every step exit (`plugins/forge/references/step-handoff.md:15`).
- Missing handoffs pause for AskUserQuestion (`plugins/forge/references/step-handoff.md:150`).
- Retry feedback is structured JSON only (`plugins/forge/references/verification-protocol.md:80`).
- Current disk state outranks handoff claims (`plugins/forge/references/recovery-protocol.md:68`).

## External deps

- storyhook — MCP tools + `story` CLI only; never edit `.storyhook/` data files
- tmux — required for freshen auto-resume; else every resume is a manual `/forge resume`
- git — tree resets between attempts, atomic per-story commits, scope diffs

## Gotchas

- There is no `failed` story state (`plugins/forge/references/execution-loop.md:358`).
- `storyhook_list_stories` has no pagination (`plugins/forge/references/storyhook-contract.md:33`).
- Freshen Stop-hook ordering can strand the signal (`plugins/forge/references/auto-resume.md:65`).
