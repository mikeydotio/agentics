---
name: design
description: Architecture design with cross-functional review driven by the team roster. Produces DESIGN.md. Spawns architect, skeptic, and conditional agents.
argument-hint: ""
---

# Design: Architecture with Cross-Functional Review

You are the design skill. Your job is to produce a thorough architecture design reviewed by a cross-functional agent team selected from the roster.

**Read inputs:**
- `.forge/IDEA.md` (required)
- `.forge/research/SUMMARY.md` (required)
- `.forge/TEAM.md` (required — drives agent selection)
- `.forge/handoffs/handoff-research.md` (if orchestrated — for context)
- `references/team-roles.md` (before spawning — "Resolving subagent_type" governs every spawn below; none of these agents have a forge override, so it's shared-definition-only, no `agent-overrides/` file to concatenate)

## Steps

### 1. Select Design Team

Read `.forge/TEAM.md` to determine which agents to spawn:

**Always spawn:**
- `software-architect` — Design system architecture, component boundaries, interfaces, data flow
- `skeptic` — Challenge the architect's design, find assumptions and risks

**Conditionally spawn (from TEAM.md):**
- `ux-designer-cli` / `ux-designer-web` / `ux-designer-mobile` — If TEAM.md says YES for user-facing interfaces. Pick the variant matching TEAM.md's recorded project type (CLI tool → `ux-designer-cli`, Web application → `ux-designer-web`, Mobile app → `ux-designer-mobile`); if TEAM.md doesn't clearly say which, default to `ux-designer-web` and note that default explicitly in the handoff.
- `security-researcher` — If TEAM.md says YES for sensitive data/auth/external input
- `accessibility-engineer` — If TEAM.md says YES for user-facing interfaces

### 2. Spawn Design Agents

Each agent receives `.forge/IDEA.md` and `.forge/research/SUMMARY.md` as context. Resolve
`subagent_type` per `references/team-roles.md` for each (`agents:<name>` preferred; `general-purpose`
+ inlined shared definition only as fallback).

Spawn in two rounds:
1. **Round 1:** `software-architect` produces initial design + conditional agents (the selected `ux-designer-*` variant, security-researcher, accessibility-engineer) review requirements
2. **Round 2:** `skeptic` reviews the architect's design + all conditional agent feedback

### 3. Synthesize Design Document

Combine all agent feedback into a cohesive design. Present each section as **plain text**, then use AskUserQuestion for approval:

Sections to cover:
- Architecture overview
- Component breakdown
- Interface/API design
- Data model (if applicable)
- UX flows (if applicable — from the selected ux-designer-* variant)
- Security considerations (if applicable — from security-researcher)
- Accessibility plan (if applicable — from accessibility-engineer)
- Key trade-offs and decisions
- Skeptic findings and resolutions

For each section:
- **header:** "Approve?"
- **question:** "Does the [section name] look right?"
- **options:**
  - "Approved (Recommended)" / "This section is solid as-is. Pros: keeps design review moving. Cons: missed issues surface during planning."
  - "Needs changes" / "I see specific things to adjust. Pros: catches problems early when changes are cheap. Cons: adds a revision cycle."
  - "I have concerns" / "Something feels off but I need to articulate it. Pros: surfaces gut-level risks. Cons: may be hard to act on without specifics."

If "Needs changes" — ask what to change via AskUserQuestion, revise, re-present.

### 4. Write DESIGN.md

After all sections are approved, write `.forge/DESIGN.md`:

```markdown
# Architecture Design

## System Overview
[High-level description and text-based diagram]

## Components
### [Component Name]
- **Purpose:** [single sentence]
- **Interfaces:** [what it exposes]
- **Dependencies:** [what it consumes]
- **Key decisions:** [why this boundary, trade-offs]

## Data Flow
[How data moves through the system]

## Cross-Cutting Concerns
[Logging, error handling, configuration, etc.]

## Integration Points
[Where components connect, protocols, contracts]

## Security Considerations
[If applicable — threat model, trust boundaries]

## Accessibility Plan
[If applicable — WCAG targets, key accommodations]

## UX Flows
[If applicable — user interaction patterns]

## Design Decisions
| Decision | Rationale | Alternatives Considered |
|----------|-----------|------------------------|
| [decision] | [why] | [what else was evaluated] |
```

## Exit

**If `--orchestrated`:** Follow the Step Exit Protocol (`references/step-handoff.md`):
1. Write `.forge/DESIGN.md`
2. Write `.forge/handoffs/handoff-design.md` (content: see step-handoff.md's Design Handoff table)
3. ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/bin/forge-step-exit.sh --step design \
     --summary "architecture design approved" --next "/forge plan --orchestrated"
   ```
4. STOP

**If standalone:** Write `.forge/DESIGN.md`, report completion to user, exit.
