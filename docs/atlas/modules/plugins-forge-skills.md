---
module: plugins/forge/skills
summary: "Forge skill layer — /forge state-machine router plus 11 step skills driving idea-to-deploy via .forge/ artifacts"
read_when: "Changing forge pipeline steps, .forge/ artifacts, routing, or freshen/step-exit handoffs"
sources:
  - path: plugins/forge/skills/decompose/SKILL.md
    blob: 3249c4147869ea1f2d6db65ccf0794236280e491
  - path: plugins/forge/skills/deploy/SKILL.md
    blob: 7edc7603ad97eeb10ef3d6d832e75fb1aa4080c9
  - path: plugins/forge/skills/design/SKILL.md
    blob: 7fbb4a709f5ce22a3a1a180e9145112530614088
  - path: plugins/forge/skills/document/SKILL.md
    blob: 4047df8107d7a86c2e1d74e03dc1097a7ecb00d2
  - path: plugins/forge/skills/execute/SKILL.md
    blob: 281bcfd7a2fcf4e4fd4a145558c7bdc2416c3eec
  - path: plugins/forge/skills/forge/SKILL.md
    blob: cc8b1715710e2d20c14e785a99fb46df714c5673
  - path: plugins/forge/skills/interrogate/SKILL.md
    blob: f7d7b94f1cc5cf6adfa7b6f7f1f7a1156c7e1eb6
  - path: plugins/forge/skills/plan/SKILL.md
    blob: d9cf6c05ef00ad0f90b9a7cefd6f41c789cf4e0a
  - path: plugins/forge/skills/research/SKILL.md
    blob: b8f37ff44dbf23e6809e6388d990ac6c67b00ce2
  - path: plugins/forge/skills/review/SKILL.md
    blob: 7c9a3c691da2e92cecb2ca0543f70a1b974f9c84
  - path: plugins/forge/skills/triage/SKILL.md
    blob: f4a3a022b00861b0d73d7ca04555bf842f188e59
  - path: plugins/forge/skills/validate/SKILL.md
    blob: 85336f6fd87b68c30526b9ef28a39da2e0c1c464
references_modules: [plugins-agents-agents-chunk-1, plugins-agents-agents-chunk-2, plugins-agents-agents-chunk-3, plugins-forge-bin, plugins-forge-references, plugins-freshen]
generator: cartographer/1
baseline: b1e1f9d1dbced518c625c38bb87814de5af1a1b7
verified: true
---

# Module: plugins/forge/skills

## Purpose

A thin state-machine router (`forge`) plus 11 step skills. The router derives pipeline position
from which `.forge/` artifacts exist and dispatches the next step with `--orchestrated`; each step
spawns agents, writes one artifact plus a handoff, commits, queues freshen, and stops — so every
step starts in cleared context and the pipeline resumes from artifacts alone.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `decompose` | skill | `plugins/forge/skills/decompose/SKILL.md:2` | PLAN.md waves → storyhook stories; writes `.forge/plan-mapping.json` |
| `deploy` | skill | `plugins/forge/skills/deploy/SKILL.md:2` | Gated on `.forge/DEPLOY-APPROVAL.md`; writes `.forge/COMPLETION.md` |
| `design` | skill | `plugins/forge/skills/design/SKILL.md:2` | Architecture review by roster team; writes `.forge/DESIGN.md` |
| `document` | skill | `plugins/forge/skills/document/SKILL.md:2` | Runs even with ESCALATEs pending, then mandatory pause; writes `.forge/DOCUMENTATION.md` |
| `execute` | skill | `plugins/forge/skills/execute/SKILL.md:2` | Generator-evaluator loop; commits only on pass verdict |
| `forge` | skill | `plugins/forge/skills/forge/SKILL.md:2` | Detects state from artifacts; dispatches steps with `--orchestrated` |
| `interrogate` | skill | `plugins/forge/skills/interrogate/SKILL.md:2` | Questions a raw idea; writes `.forge/IDEA.md` |
| `plan` | skill | `plugins/forge/skills/plan/SKILL.md:2` | Waves + machine-evaluable criteria; writes `.forge/PLAN.md` |
| `research` | skill | `plugins/forge/skills/research/SKILL.md:2` | Writes `.forge/research/SUMMARY.md` and `.forge/TEAM.md` |
| `review` | skill | `plugins/forge/skills/review/SKILL.md:2` | Static analysis vs DESIGN.md; writes `.forge/REVIEW-REPORT.md` |
| `triage` | skill | `plugins/forge/skills/triage/SKILL.md:2` | FIX or ESCALATE per finding; writes `.forge/TRIAGE.md` |
| `validate` | skill | `plugins/forge/skills/validate/SKILL.md:2` | Tests + gap-filling; writes `.forge/VALIDATE-REPORT.md` |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `--orchestrated` | flag | `plugins/forge/skills/forge/SKILL.md:143` | Selects step-exit protocol vs clean standalone return |
| `Step Exit Protocol` | protocol | `plugins/forge/skills/forge/SKILL.md:212` | Write artifact + handoff, commit, queue freshen, STOP |
| `config.json` | config | `plugins/forge/skills/forge/SKILL.md:258` | yolo, max_fix_cycles, retry/session caps |
| `plan_hash` | guard | `plugins/forge/skills/decompose/SKILL.md:26` | MD5 of PLAN.md; mismatch forces continue/recreate/cancel |

## Relationships

- `plugins-forge-skills.forge -> plugins-forge-bin.forge-state.sh (calls)`
- `plugins-forge-skills.forge -> plugins-forge-bin.forge-step-exit.sh (calls)`
- `plugins-forge-skills.forge -> plugins-freshen.freshen.sh (calls)`
- `plugins-forge-skills.execute -> plugins-freshen.freshen.sh (calls)`
- `plugins-forge-skills.execute -> plugins-forge-references.execution-loop.md (reads)`
- `plugins-forge-skills.execute -> plugins-agents-agents-chunk-1.generator.md (reads)`
- `plugins-forge-skills.execute -> plugins-agents-agents-chunk-1.evaluator.md (reads)`
- `plugins-forge-skills.research -> plugins-agents-agents-chunk-1.domain-researcher (calls)`
- `plugins-forge-skills.design -> plugins-agents-agents-chunk-2.software-architect (calls)`
- `plugins-forge-skills.plan -> plugins-agents-agents-chunk-2.project-manager (calls)`
- `plugins-forge-skills.review -> plugins-agents-agents-chunk-2.reviewer (calls)`
- `plugins-forge-skills.document -> plugins-agents-agents-chunk-2.technical-writer (calls)`
- `plugins-forge-skills.validate -> plugins-agents-agents-chunk-3.validator (calls)`
- `plugins-forge-skills.triage -> plugins-agents-agents-chunk-3.triager (calls)`

## Type notes

- `.forge/` artifact presence is the sole routing state (plugins/forge/skills/forge/SKILL.md:152).
- Review and validate: later finisher queues freshen (plugins/forge/skills/review/SKILL.md:94).
- FIX items re-enter plan; at cap they become ESCALATE (plugins/forge/skills/triage/SKILL.md:70).
- Generator never commits; evaluator cannot edit (plugins/forge/skills/execute/SKILL.md:31-32).
- TEAM.md gates conditional agents in design and review (plugins/forge/skills/design/SKILL.md:28).

## External deps

- storyhook — `story` CLI + `storyhook_decompose_spec` MCP tool; owns story state
- jq — mandated for all shell JSON construction
- tmux — auto-resume capability gate in execute

## Gotchas

- `devils-advocate` is a role, not a shared agent file (plugins/forge/skills/design/SKILL.md:25).
- Same applies to `senior-engineer` and `ux-designer` (plugins/forge/skills/forge/SKILL.md:304,306).
- Role docs: plugins/forge/references/team-roles.md (plugins/forge/skills/forge/SKILL.md:19).
- Generator/evaluator spawn as `general-purpose` (plugins/forge/skills/execute/SKILL.md:101).
