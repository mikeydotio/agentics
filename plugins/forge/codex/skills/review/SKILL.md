---
name: review
description: Static gap and defect analysis — codebase quality, design drift, story hygiene. Produces REVIEW-REPORT.md with findings by severity. Runs in parallel with validate.
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

# Review: Static Analysis of Implemented Code

You are the review skill. Your job is to perform a thorough static analysis of the implemented codebase, identifying quality gaps, design drift, and defects. You run in parallel with the validate skill — both produce reports consumed by triage.

**Read inputs:**
- `.forge/DESIGN.md` (required — the standard to review against)
- `.forge/PLAN.md` (for task scope context)
- `.forge/IDEA.md` (for requirements context)
- `.forge/TEAM.md` (for conditional agent selection)
- `.forge/handoffs/handoff-execute.md` (for patterns and landmarks)

**New reference (read before starting):**
- `<plugin-root>/codex/references/severity-levels.md` — Finding severity definitions
- `<plugin-root>/codex/references/report-format.md` — Report structure with solution options
- `<plugin-root>/codex/references/team-roles.md` — "Resolving canonical role" — governs every spawn below; `reviewer`
  has a forge override (`<plugin-root>/codex/agent-overrides/reviewer-context.md`) to concatenate in, the others don't

## Steps

### 1. Select Review Team

Read `.forge/TEAM.md` to determine which agents to spawn:

**Always spawn:**
- `reviewer` — Primary static analysis agent (has a forge override — see above)
- `software-architect` — Architecture alignment check
- `skeptic` — Challenge review findings, find what the reviewer missed

**Conditionally spawn (from TEAM.md):**
- `security-researcher` — If project handles sensitive data/auth/external input
- `accessibility-engineer` — If project has user-facing interfaces

### 2. Spawn Review Agents

All agents receive DESIGN.md, PLAN.md, IDEA.md, and the execute handoff for working context.
Resolve `canonical role` per `<plugin-root>/codex/references/team-roles.md` for each (load the canonical role and Forge override through runtime.md).

**`reviewer` is `read_only: true` — it has no Write/Edit tools and does NOT write
`.forge/REVIEW-REPORT.md` itself.** It returns its findings as its response, in the Output Format
`reviewer.md` specifies. This step (the orchestrator) is what writes the file, by combining every
agent's returned findings — see Step 3.

Spawn in parallel — each agent independently reviews the codebase.

### 3. Synthesize REVIEW-REPORT.md

Combine all agents' returned findings into a single report — this is the orchestrator's job, not
any individual agent's (see Step 2's note on `reviewer` being read-only). Each finding must follow the severity and report format:

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

**If `--orchestrated`:** Write `.forge/REVIEW-REPORT.md`, then follow the Step Exit Protocol
(`<plugin-root>/codex/references/step-handoff.md`) — write `handoff-review.md` (Review Handoff table) and run:
```bash
bash "<plugin-root>/bin/forge-step-exit.sh" --host codex --step review \
  --summary "static analysis complete" --next '$forge:forge continue'
```

**Note:** Review never checks for `.forge/VALIDATE-REPORT.md` before deciding whether to queue
freshen — that file-presence "whoever finishes second queues" coordination previously deadlocked
the pipeline (review would STOP without queuing when validate hadn't finished yet, so validate
never got dispatched). `forge-state.sh` is the single source of truth for whether review, validate,
or both still need to run — see `<plugin-root>/codex/skills/forge/SKILL.md`'s **Review+Validate Parallel Dispatch**.
When the orchestrator dispatches `review_validate --orchestrated`, it spawns review's and
validate's agents together in one message and queues one freshen after synthesizing both reports
— it does not invoke this skill's own Exit twice. This Exit section applies when review runs alone
(`dispatch: "review --orchestrated"`, i.e. validate's report already exists).

**If standalone:** Write `.forge/REVIEW-REPORT.md`, report findings to user, exit.
