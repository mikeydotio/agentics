# Forge Plugin

Unified idea-to-deployment pipeline for Claude Code. Takes a raw idea through interrogation, research, design, planning, autonomous execution, review, validation, triage, documentation, and deployment — with freshen-based context clearing between every step.

## Overview

Forge replaces the separate ideate and forge plugins with a single unified pipeline:

```
Interrogate -> Research -> Design -> Plan -> Decompose -> Execute
                                                            |
                                                 Review || Validate (parallel)
                                                            |
                                                         Triage
                                                            |
                                              FIX items? -> Plan (loop, max 3 / 10 yolo)
                                              No FIX    -> Document
                                                            |
                                                         PAUSE (always)
                                                            |
                                              ESCALATE? -> User reviews -> Plan
                                              None      -> Deploy (with permission)
```

## Commands

| Command | Purpose |
|---------|---------|
| `/forge` | Detect state and continue pipeline |
| `/forge continue` | Same as above |
| `/forge <step>` | Invoke a specific step standalone |
| `/forge status` | Pipeline dashboard |
| `/forge stop` | Graceful stop with handoff |
| `/forge --yolo` | FIX everything, never ESCALATE |

## Pipeline Steps (11)

| # | Step | Input | Output |
|---|------|-------|--------|
| 1 | Interrogate | User's idea | `IDEA.md` |
| 2 | Research | `IDEA.md` | `research/SUMMARY.md` + `TEAM.md` |
| 3 | Design | `IDEA.md`, research | `DESIGN.md` |
| 4 | Plan | `IDEA.md`, `DESIGN.md` | `PLAN.md` |
| 5 | Decompose | `PLAN.md`, `DESIGN.md` | stories + `plan-mapping.json` |
| 6 | Execute | stories, mapping | Implemented code |
| 7 | Review | code, `DESIGN.md` | `REVIEW-REPORT.md` |
| 8 | Validate | code, `PLAN.md` | `VALIDATE-REPORT.md` |
| 9 | Triage | reports | `TRIAGE.md` |
| 10 | Document | all artifacts | `DOCUMENTATION.md` |
| 11 | Deploy | approval | `COMPLETION.md` |

## Architecture

### State Machine Router

The orchestrator detects pipeline state from artifacts on disk and dispatches to the correct step. No conversation state is needed — everything is derived from `.forge/` contents.

### Step Exit Protocol

Every step follows the same pattern:
1. Write artifacts to `.forge/`
2. Write handoff to `.forge/handoffs/handoff-<step>.md`
3. Commit
4. Queue freshen (`/clear` + `/forge continue`)
5. STOP

### Agent Roster (15 agents)

12 migrated from ideate + forge, 3 new:
- **reviewer** — static gap/defect analysis
- **validator** — test hardening
- **triager** — FIX/ESCALATE deliberation

### FIX/ESCALATE Loop

After execution, Review + Validate run in parallel. Triage deliberates on findings:
- **FIX**: auto-fix via Plan -> Decompose -> Execute -> Review -> Validate -> Triage (max 3 cycles, 10 in yolo mode)
- **ESCALATE**: user reviews context and recommendations for each item

### Safety

- Runaway safeguards: max sessions, max retries, max fix cycles
- Deploy: never without explicit user permission
- Always pauses after Document step for user review


## Codex

Forge exposes the same twelve public skills on Claude Code and Codex. Invoke
`$forge:forge` with the existing command arguments in Codex. Public skill files
select the native implementation; Claude registration metadata and original skill
bodies are preserved under `claude/skills/`.

Codex uses native specialist tools and the Agents library, with inherited runtime
permissions and explicit integrity checks. Freshen owns automatic reset delivery
inside a Codex CLI tmux pane. Without that capability, Forge persists a handoff and
returns manual continuation instructions. The app can resume those same artifacts.
Installed dependencies resolve by enabled identity and exact version; explicit
`AGENTS_PLUGIN_ROOT`, `FRESHEN_PLUGIN_ROOT`, and `HOOK_GUARD_PLUGIN_ROOT` overrides
are validated and authoritative.

Shared step-exit and research-explore helpers accept `--host claude|codex` and default
to Claude for existing callers. Codex exploration uses a disposable worktree and
native workspace sandboxing; `--timeout` defaults to 300 seconds (maximum 3600).
No host permissions, hook trust, model selection, or installed cache is changed.

The existing Forge Bats runner includes native instruction, dependency, hook,
explorer, packaging and lifecycle tests. The lifecycle fixture substitutes only the
external terminal and accepted-input events; it runs production Forge/Freshen hooks.
These tests do not claim live model compliance or a live Codex TUI end-to-end result.
