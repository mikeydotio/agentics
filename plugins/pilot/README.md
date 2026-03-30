# Pilot Plugin

Autonomous execution harness for Claude Code. Decomposes implementation plans into storyhook stories, then executes them through a generator-evaluator loop with session persistence and auto-resume.

## Overview

Work replaces manual execution with a fire-and-forget workflow:

1. **Plan** → Decompose a PLAN.md into storyhook stories with dependencies
2. **Run** → Generator writes code, evaluator verifies, stories advance through states
3. **Resume** → Sessions end naturally; crontab triggers restart automatically
4. **Complete** → All stories done, tests pass, completion artifact written

## Commands

| Command | Purpose |
|---------|---------|
| `/pilot init` | Validate storyhook, add required states |
| `/pilot plan [file]` | Decompose PLAN.md into stories |
| `/pilot run [--interval 15m] [--dry-run]` | Start autonomous execution |
| `/pilot resume` | Resume after session boundary |
| `/pilot status` | Dashboard: stories, retries, blockers |
| `/pilot stop` | Graceful stop with handoff |
| `/pilot ideate` | Invoke ideate with pilot-aware hints |

## Architecture

```
User → /ideate → PLAN.md → /pilot plan → Stories → /pilot run
                                                              │
                                          Generator ←→ Evaluator (loop)
                                                              │
                                              pass → commit → next story
                                              fail → retry or block
                                                              │
                                          Session ends → auto-resume → continue
```

### Generator-Evaluator Pattern

- **Generator**: Implements one story at a time (has Write/Edit tools)
- **Evaluator**: Verifies implementation (read-only, skeptical, debiased)
- **Deterministic pre-checks**: Tests, linter, stub grep run before evaluator
- **Isolated subagents**: Fresh context per story, no cross-contamination

### State Management

| File | Tracked | Purpose |
|------|---------|---------|
| `config.json` | Yes | User limits (max_retries, session limits) |
| `plan-mapping.json` | Yes | Story-to-task mapping |
| `state.json` | No | Runtime state (counters, status) |
| `lock.json` | No | Session lock with heartbeat |
| `handoff.md` | No | Human-readable session narrative |
| `verdicts.jsonl` | No | Evaluator verdict history |

### Safety Features

- **Canary mode**: First N stories require user approval
- **Runaway safeguards**: Max sessions and max total retries
- **Session locking**: Heartbeat-based, prevents duplicate work
- **Integrity checks**: Post-generator and post-evaluator verification
- **Architectural drift detection**: Periodic architect review
