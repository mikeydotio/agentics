---
name: review
description: Static gap and defect analysis — codebase quality, design drift, story hygiene. Produces REVIEW-REPORT.md with findings by severity. Runs in parallel with validate.
argument-hint: ""
---

# Review: Static Analysis of Implemented Code

You are the review skill. Your job is to perform a thorough static analysis of the implemented codebase, identifying quality gaps, design drift, and defects. You run in parallel with the validate skill — both produce reports consumed by triage.

**Read inputs:**
- `.pilot/DESIGN.md` (required — the standard to review against)
- `.pilot/PLAN.md` (for task scope context)
- `.pilot/IDEA.md` (for requirements context)
- `.pilot/TEAM.md` (for conditional agent selection)
- `.pilot/handoffs/handoff-execute.md` (for patterns and landmarks)

**New reference (read before starting):**
- `references/severity-levels.md` — Finding severity definitions
- `references/report-format.md` — Report structure with solution options

## Steps

### 1. Select Review Team

Read `.pilot/TEAM.md` to determine which agents to spawn:

**Always spawn:**
- `reviewer` — Primary static analysis agent
- `software-architect` — Architecture alignment check
- `devils-advocate` — Challenge review findings, find what the reviewer missed

**Conditionally spawn (from TEAM.md):**
- `security-researcher` — If project handles sensitive data/auth/external input
- `accessibility-engineer` — If project has user-facing interfaces

### 2. Spawn Review Agents

All agents receive DESIGN.md, PLAN.md, IDEA.md, and the execute handoff for working context.

Spawn in parallel — each agent independently reviews the codebase.

### 3. Synthesize REVIEW-REPORT.md

Combine all agent findings into a single report. Each finding must follow the severity and report format:

```markdown
# Review Report

## Summary
[Overall codebase quality assessment — 2-3 sentences]

## Findings

### [Finding Title]
- **Severity**: Critical | Important | Useful
- **Description**: [what's wrong or could be better]
- **Location**: [file:line or component]
- **Option 1 (Recommended)**: [solution] — Pros: ... Cons: ...
- **Option 2**: [solution] — Pros: ... Cons: ...
- **Option 3**: [solution] — Pros: ... Cons: ...

[Repeat for each finding]

## Design Alignment
[ALIGNED / MINOR DRIFT / MAJOR DRIFT — with specifics]

## Strengths
[What's working well — patterns to reinforce]
```

**Finding severity levels:**
- **Critical**: Meaningful risk to system/data security/integrity
- **Important**: Usability issues (formatting, UI layout, non-critical broken features)
- **Useful**: Nothing wrong but opportunity for improved UX or code quality

**Every finding MUST include:**
- At least 2 solution options with pros/cons
- Specific location (file:line where possible)
- Clear severity assignment

### 4. Deduplicate

If multiple agents flag the same issue, merge into a single finding with the highest severity and the richest solution options.

## Exit

**If `--orchestrated`:** Follow the Step Exit Protocol:
1. Write `.pilot/REVIEW-REPORT.md`
2. Write `.pilot/handoffs/handoff-review.md` with:
   - Key Decisions: critical findings, alignment assessment
   - Context for Next Step: report summary for triage
3. Commit: `git add .pilot/ && git commit -m "pilot(review): static analysis complete"`
4. **If validate is also complete** (check for `.pilot/VALIDATE-REPORT.md`): queue freshen
5. **If validate is not yet complete**: STOP without queuing freshen (wait for validate to complete — the orchestrator handles this)
6. STOP

**Note:** Review and validate run in parallel. The orchestrator dispatches both, and only advances to triage when BOTH reports exist. If review finishes first, it commits its report and stops. The orchestrator detects both reports on the next `continue`.

**If standalone:** Write `.pilot/REVIEW-REPORT.md`, report findings to user, exit.
