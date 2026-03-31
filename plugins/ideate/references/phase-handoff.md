# Phase Handoff Format

Specification for handoff documents written between ideate phases to enable cold-start resumption after context clearing.

## Purpose

Each phase writes a handoff document before instructing the user to `/clear`. The next phase reads this document on resumption to restore essential context without re-reading all prior conversation history.

**The handoff is mandatory, not best-effort.** After `/clear`, it is the only source of session knowledge. If the handoff is missing on resumption, the orchestrator MUST pause and ask the user how to proceed via `AskUserQuestion` rather than continuing with degraded context.

## File Naming

`.planning/handoff-phase-N.md` where N is the phase number that just completed.

## Common Structure

All phase handoffs share this structure:

```markdown
# Phase N Handoff: [Phase Name] Complete

## Timestamp
[ISO 8601]

## Artifacts Produced
- [list of files written this phase]

## Key Decisions
[Decisions made during this phase that downstream phases must respect.
Not a recap of everything discussed — only the load-bearing decisions.]

## Context for Next Phase
[What the next phase specifically needs to know. This is the most important
section — it replaces the context that would have been in the conversation window.]

## Open Questions
[Unresolved items that the next phase should address.]
```

## Phase-Specific Content

### Phase 1 → 2 Handoff (`handoff-phase-1.md`)

| Section | Content |
|---------|---------|
| Key Decisions | Vision statement (2-3 sentences), core problem and who it affects, scope boundaries |
| Context for Next Phase | Top 5-7 requirements (not the full IDEA.md list), assumptions challenged and their status, specific domains/areas research should investigate, existing solutions mentioned during interrogation, user-expressed preferences or constraints |
| Open Questions | Questions that research should answer, assumptions still unvalidated |

### Phase 2 → 3 Handoff (`handoff-phase-2.md`)

| Section | Content |
|---------|---------|
| Key Decisions | Which existing solutions the user decided to use/extend/ignore and why, technology stack preferences expressed |
| Context for Next Phase | Research summary (key findings, not the full research/ directory), recommended technology stack with rationale, patterns to follow from established best practices, pitfalls to avoid, user's reactions to research findings |
| Open Questions | Design questions that research could not resolve |

### Phase 3 → 4 Handoff (`handoff-phase-3.md`)

| Section | Content |
|---------|---------|
| Key Decisions | Architecture overview (3-5 sentences), key trade-offs and why they were resolved as they were, user approvals per design section (which needed revision and why) |
| Context for Next Phase | Component count and responsibilities, interface contracts between components, security and accessibility requirements (if applicable), areas of high complexity that need careful task breakdown, dependencies between components |
| Open Questions | Implementation questions that design deferred to planning |

### Phase 4 → Pilot Invitation Handoff (`handoff-phase-4.md`)

| Section | Content |
|---------|---------|
| Key Decisions | Plan approved by user, wave count and task count, test strategy approach |
| Context for Next Phase | Plan structure summary (waves, dependencies, estimated complexity), critical inter-wave dependencies, risk register highlights (top 3 from devil's advocate), whether pilot plugin is available |
| Open Questions | Any execution preferences the user expressed during planning |

## Triggering the Clear

After writing the handoff and committing, the orchestrator queues an automatic context clear:

```bash
bash plugins/freshen/bin/freshen.sh queue "/ideate" --source ideate
```

The freshen hooks handle `/clear` and re-invocation automatically via tmux.

If freshen fails (no tmux), fall back to manual instructions:

```
---
**Phase N complete.** All artifacts committed.

To continue with fresh context:
1. Run `/clear`
2. Run `/ideate`

I'll pick up right where we left off.
---
```

Then STOP — do not proceed to the next phase.

## Missing Handoff on Resumption

If the orchestrator resumes and the expected handoff file is missing:

1. Do NOT silently continue with degraded context
2. Use `AskUserQuestion`:
   - **header:** "Missing Handoff"
   - **question:** "The handoff document from the previous phase is missing (`.planning/handoff-phase-N.md`). Without it, I'll be working with limited context about decisions and rationale from the prior phase. The artifacts themselves are intact."
   - **options:**
     - "Continue anyway" / "Proceed using only the artifact files — I can fill in context if needed"
     - "Let me create it" / "I'll write the handoff document manually, then re-invoke"
     - "Start this phase over" / "Re-run the previous phase to regenerate the handoff"
3. If "Continue anyway" → proceed but note in plain text which context may be incomplete
