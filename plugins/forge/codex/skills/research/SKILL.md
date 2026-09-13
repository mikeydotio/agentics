---
name: research
description: Full domain research plus agent team roster recommendation. Produces research/SUMMARY.md and TEAM.md. Spawns domain-researcher agents for parallel investigation.
---

Resolve `<plugin-root>` three directories above this loaded file's containing directory.
Read `<plugin-root>/codex/references/runtime.md` before this step.

<!-- AGE-104 DELIVERY BEGIN -->
Read `<plugin-root>/references/delivery.md` completely before this step, including standalone entry.
The local helper owns all specialist dispatch/wait/retry/cleanup; persist intent before
native dispatch and use the state-derived result envelope. On delivery_recovery, inspect
and recover existing batches before any fresh dispatch, artifact-based advancement or
cleanup. Preserve partial changes and write an incomplete handoff on failure; never
convert delivery failure into an evaluator verdict or a fresh generator retry.
In Plan mode inspect only; do not initialize delivery state or dispatch writers.
<!-- AGE-104 DELIVERY END -->

# Research: Domain Investigation + Team Roster

You are the research skill. Your job is to investigate the problem space thoroughly and recommend the agent team roster for downstream steps.

**Read before starting:**
- `<plugin-root>/codex/references/team-roles.md` — Agent team roles and spawning philosophy

**Read inputs:**
- `.forge/IDEA.md` (required)
- `.forge/handoffs/handoff-interrogate.md` (if orchestrated — for context)

## Steps

### 1. Research Scope

From IDEA.md, identify 1-3 research tracks:
1. **Existing solutions** — What already solves this? Gaps in existing tools?
2. **Best practices** — Established patterns in this domain?
3. **Technology landscape** — Best-of-breed stack for this?
4. **Common pitfalls** — What do people typically get wrong?

### 2. Spawn Researchers

Spawn 1-3 `domain-researcher` agents in parallel, one per research track. Resolve `canonical role`
per `<plugin-root>/codex/references/team-roles.md`'s "Resolving canonical role" (load the canonical role and Forge override through runtime.md). Each receives IDEA.md and a focused research prompt.

Each researcher writes findings to `.forge/research/`. File naming: `.forge/research/<topic>.md`.

### 2b. Governed codebase exploration (optional)

When the idea builds on an **existing codebase** and `.forge/config.json` has
`"governed_explorer": true`, complement the (web/domain) researchers above with a
Codex explorer that runs code in a disposable worktree to answer a grounded question.
The native workspace sandbox confines experimental writes; no approval escalation or
permission bypass is used. The current configured Codex model provides the findings.

For each codebase question (1–2 is plenty), call the deterministic seam:

```bash
bash "<plugin-root>/bin/forge-research-explore.sh" --host codex \
  --topic "<short-slug>" --task "<the concrete codebase question>"
# → JSON: {enabled, ran, topic, out, launcher}
```

Branch on the JSON: if `.enabled` is `false` (flag off) or `.ran` is `false`
(launch, execution or cleanup failed), record the diagnostic and continue with the ordinary researchers.
Exclude that attempted output path from current synthesis even if an older findings file
still exists; preserve that earlier evidence. This capability is strictly additive.
When it runs, findings land in `.forge/research/codebase-<topic>.md`, which Step
3's synthesis folds in like any other researcher's file. This sub-phase runs
entirely before the step Exit, so the disposable worktree is already gone by the
time `.forge/` is committed; nothing extra to stage.

### 3. Synthesize

After all researchers complete, synthesize findings into `.forge/research/SUMMARY.md`:

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

Use the native question tool for significant decision points (e.g., whether to use an existing solution vs. build new). When constructing options, follow the format from `<plugin-root>/codex/references/questioning.md`: include pros and cons in each option's description, and mark the recommended option (the one the system would choose in autonomous mode) with `(Recommended)` in its label.

### 5. Recommend Team Roster

Based on the project type identified in IDEA.md and research findings, write `.forge/TEAM.md`.
Every name below must be a real file in `plugins/agents/agents/` (cross-check against
`<plugin-root>/codex/references/team-roles.md` if unsure — this is exactly the roster that downstream steps will try
to spawn, so a wrong name here breaks every step that reads it):

```markdown
# Agent Team Roster

## Project Type
[CLI tool | Web application | Mobile app | Library/SDK | Data pipeline | Infrastructure | Other]

## Active Agents
### Always Active
- domain-researcher
- software-architect
- software-engineer
- qa-engineer
- project-manager
- skeptic
- technical-writer
- generator
- evaluator
- reviewer
- validator
- triager

### Conditionally Activated
- ux-designer-{cli|web|mobile}: [YES/NO — if YES, which variant and why. Match the Project Type
  above (CLI tool → ux-designer-cli, Web application → ux-designer-web, Mobile app →
  ux-designer-mobile). If Project Type is Library/SDK, Data pipeline, Infrastructure, or Other with
  no user-facing surface, this is normally NO. If the project spans platforms or the type is
  ambiguous, default to ux-designer-web and say so explicitly here.]
- security-researcher: [YES/NO — reason]
- accessibility-engineer: [YES/NO — reason]

## Rationale
[Why each conditional agent was included or excluded]
```

## Exit

**If `--orchestrated`:** Write `.forge/research/SUMMARY.md` and `.forge/TEAM.md`, then follow the
Step Exit Protocol (`<plugin-root>/codex/references/step-handoff.md`) — write `handoff-research.md` (Research Handoff
table) and run:
```bash
bash "<plugin-root>/bin/forge-step-exit.sh" --host codex --step research \
  --summary "domain research + team roster" --next '$forge:forge design --orchestrated'
```

**If standalone:** Write outputs, report completion to user, exit.
