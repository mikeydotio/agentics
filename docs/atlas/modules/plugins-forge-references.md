---
module: plugins/forge/references
summary: "Normative protocol docs forge skills follow — execution loop, handoffs, locking, severity levels, storyhook usage"
read_when: "Changing forge pipeline behavior — execution, handoffs, locking, severity, or storyhook"
sources:
  - path: plugins/forge/references/auto-resume.md
  - path: plugins/forge/references/deterministic-checks.md
  - path: plugins/forge/references/execution-loop.md
  - path: plugins/forge/references/handoff-format.md
  - path: plugins/forge/references/questioning.md
  - path: plugins/forge/references/recovery-protocol.md
  - path: plugins/forge/references/report-format.md
  - path: plugins/forge/references/session-locking.md
  - path: plugins/forge/references/severity-levels.md
  - path: plugins/forge/references/step-handoff.md
  - path: plugins/forge/references/story-decomposition.md
  - path: plugins/forge/references/storyhook-contract.md
  - path: plugins/forge/references/team-roles.md
  - path: plugins/forge/references/verification-protocol.md
references_modules: [plugins-agents-agents-chunk-1, plugins-agents-agents-chunk-2, plugins-agents-references, plugins-forge-bin, plugins-forge-hooks, plugins-forge-skills, plugins-freshen]
generator: cartographer/2
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
