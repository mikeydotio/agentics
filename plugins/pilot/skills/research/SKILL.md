---
name: research
description: Full domain research plus agent team roster recommendation. Produces research/SUMMARY.md and TEAM.md. Spawns domain-researcher agents for parallel investigation.
argument-hint: ""
---

# Research: Domain Investigation + Team Roster

You are the research skill. Your job is to investigate the problem space thoroughly and recommend the agent team roster for downstream steps.

**Read before starting:**
- `references/team-roles.md` — Agent team roles and spawning philosophy

**Read inputs:**
- `.pilot/IDEA.md` (required)
- `.pilot/handoffs/handoff-interrogate.md` (if orchestrated — for context)

## Steps

### 1. Research Scope

From IDEA.md, identify 1-3 research tracks:
1. **Existing solutions** — What already solves this? Gaps in existing tools?
2. **Best practices** — Established patterns in this domain?
3. **Technology landscape** — Best-of-breed stack for this?
4. **Common pitfalls** — What do people typically get wrong?

### 2. Spawn Researchers

Spawn 1-3 `domain-researcher` agents in parallel, one per research track. Each receives IDEA.md and a focused research prompt.

Each researcher writes findings to `.pilot/research/`. File naming: `.pilot/research/<topic>.md`.

### 3. Synthesize

After all researchers complete, synthesize findings into `.pilot/research/SUMMARY.md`:

```markdown
# Research Summary

## Key Findings
[Top 3-5 findings that should influence design]

## Existing Solutions
[What exists, strengths/weaknesses, gaps]

## Recommended Technology Stack
[Stack with rationale — why each choice]

## Patterns to Follow
[Established best practices relevant to this project]

## Pitfalls to Avoid
[Common mistakes and how to prevent them]

## Open Questions
[Questions research could not resolve — design must address]
```

### 4. Present to User

Present key findings as **plain text**:
- "Here's what I found. [Existing tool X] does [thing] — do you still want to build this, or would using/extending X be better?"
- "The standard architecture for this is [pattern]. I recommend we follow it."
- "Common pitfall: [thing]. Our design should account for this."

Use AskUserQuestion for significant decision points (e.g., whether to use an existing solution vs. build new).

### 5. Recommend Team Roster

Based on the project type identified in IDEA.md and research findings, write `.pilot/TEAM.md`:

```markdown
# Agent Team Roster

## Project Type
[CLI tool | Web application | Library/SDK | Data pipeline | Infrastructure | Other]

## Active Agents
### Always Active
- domain-researcher
- software-architect
- senior-engineer
- qa-engineer
- project-manager
- devils-advocate
- technical-writer
- generator
- evaluator
- reviewer
- validator
- triager

### Conditionally Activated
- ux-designer: [YES/NO — reason]
- security-researcher: [YES/NO — reason]
- accessibility-engineer: [YES/NO — reason]

## Rationale
[Why each conditional agent was included or excluded]
```

## Exit

**If `--orchestrated`:** Follow the Step Exit Protocol:
1. Write `.pilot/research/SUMMARY.md` and `.pilot/TEAM.md`
2. Write `.pilot/handoffs/handoff-research.md` with:
   - Key Decisions: existing solutions user chose to use/ignore, technology preferences
   - Context for Next Step: research summary, recommended stack, patterns to follow, pitfalls, team roster
   - Open Questions: design questions research could not resolve
3. Commit: `git add .pilot/ && git commit -m "pilot(research): domain research + team roster"`
4. Queue freshen: `bash plugins/freshen/bin/freshen.sh queue "/pilot continue" --source pilot`
5. STOP

**If standalone:** Write outputs, report completion to user, exit.
