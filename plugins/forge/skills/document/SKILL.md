---
name: document
description: Comprehensive project documentation. Works even with ESCALATE stories pending. Spawns technical-writer agent. Produces DOCUMENTATION.md.
argument-hint: ""
model: sonnet
effort: medium
---

# Document: Project Documentation

You are the document skill. Your job is to produce comprehensive project documentation covering architecture decisions, API usage, setup guides, and implementation notes. This step runs regardless of whether ESCALATE stories are pending — documentation is always valuable.

**Read inputs:**
- `.forge/IDEA.md` (required — original requirements)
- `.forge/DESIGN.md` (required — architecture)
- `.forge/PLAN.md` (for implementation context)
- `.forge/REVIEW-REPORT.md` (for quality findings)
- `.forge/VALIDATE-REPORT.md` (for test coverage)
- `.forge/TRIAGE.md` (for known issues)
- `.forge/handoffs/handoff-triage.md` (for context)
- `references/team-roles.md` (before spawning — "Resolving subagent_type" governs the
  `technical-writer` spawn below; this agent has no forge override)

## Steps

### 1. Spawn Documentation Agent

Spawn `technical-writer` agent with all planning artifacts and the implemented codebase as context.
Resolve `subagent_type` per `references/team-roles.md` (`agents:technical-writer` preferred;
`general-purpose` + inlined `technical-writer.md` only as fallback).

The technical writer:
- Reads the entire codebase
- Cross-references with IDEA.md requirements and DESIGN.md architecture
- Documents how to use, understand, and change the project
- Records architecture decision records (ADRs) for key design choices
- Notes known issues from TRIAGE.md (both FIX'd and ESCALATE'd items)

### 2. Review Documentation

Present documentation sections to the user as **plain text**. For key sections, use AskUserQuestion:

- **header:** "Docs OK?"
- **question:** "Does this documentation capture everything important?"
- **options:**
  - "Looks good (Recommended)" / "Documentation is comprehensive and accurate. Pros: moves to deployment review. Cons: undiscovered gaps ship with the project."
  - "Missing something" / "There's a topic or section not covered. Pros: fills documentation gaps before release. Cons: adds a writing cycle."
  - "Needs revision" / "Existing content needs corrections or restructuring. Pros: improves doc quality. Cons: revision takes time."

If changes needed, revise and re-present.

### 3. Write Documentation

Write `.forge/DOCUMENTATION.md`:

```markdown
# Project Documentation

## Overview
[What this project does and why — from IDEA.md]

## Getting Started
[Setup instructions, prerequisites, first run]

## Architecture
[System overview from DESIGN.md, component diagram, data flow]

## API / Interface Reference
[Public interfaces, their contracts, usage examples]

## Configuration
[All configuration options and their effects]

## Development
[How to develop, test, and contribute]

## Architecture Decision Records
### ADR-001: [Decision Title]
- **Context**: [why this decision was needed]
- **Decision**: [what was decided]
- **Alternatives**: [what was considered]
- **Consequences**: [trade-offs]

## Known Issues
[From TRIAGE.md — FIX'd issues and their resolutions, pending ESCALATE items]

## Test Coverage
[Summary from VALIDATE-REPORT.md]
```

The technical writer may also create or update other documentation files (README.md, API docs, etc.) as appropriate for the project.

## Exit

**If `--orchestrated`:** Follow the Step Exit Protocol (`references/step-handoff.md`):
1. Write `.forge/DOCUMENTATION.md` (and any other doc files)
2. Write `.forge/handoffs/handoff-document.md` (content: see step-handoff.md's Document Handoff
   table)
3. ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/bin/forge-step-exit.sh --step document \
     --summary "project documentation" --next "/forge continue"
   ```
   If the technical writer created or updated files outside `.forge/` (README.md, API docs, etc.
   per Step 1 above), pass each as its own `--extra-path` so they ride along in the same commit.
4. STOP

The orchestrator enters the **post-document pause** on next `continue` — it ALWAYS pauses here for user review, never auto-advances to deploy.

**If standalone:** Write documentation, report to user, exit.
