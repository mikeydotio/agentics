# Archetypes — The Shared Agent Library

Council members are not bespoke — they're drawn from the shared agent library at
`plugins/agents/agents/`. Each agent in that library is an **archetype**: a
research-backed specialist with a defined role, methodology, and tool set. The chair
composes a 3-member council by picking 3 archetypes from this roster.

## Source of truth

The authoritative roster lives in `plugins/agents/references/agent-catalog.md`. Always
consult that file before picking a panel — the catalog has the current list of
archetypes, their tools, and their tags. This doc only summarizes; it intentionally
does not duplicate the catalog so the two don't drift.

## Dispatching an archetype

Determine `subagent_type` from what the running environment exposes:

- **Preferred:** `agents:<archetype-name>` if the agentics agents plugin is installed
  (the catalog lists every available name).
- **Fallback:** `general-purpose` with the archetype's role injected explicitly in the
  prompt. Read `plugins/agents/agents/<archetype-name>.md` and paste the `<role>` block
  into the prompt under a "## Your role" heading before the council-specific prompt
  template from `council-protocol.md`.

The dispatch prompt always carries the same payload (context + question + member task),
regardless of whether you're using a native subagent_type or the fallback.

## Adding domain nuance on top of an archetype

Archetypes are **starting points**, not final specifications. The chair may inject
domain-specific context into a member's prompt to focus the archetype's expertise.

Example: when convening on "should the iOS onboarding CTA be a sheet or a full-screen
push?", the chair seats `ux-designer-mobile`. The archetype already knows mobile UX
broadly; the chair adds:

> Focus your analysis on iOS 17+ HIG guidance for primary CTAs in onboarding flows.
> The app is SwiftUI; assume the user is on iPhone (no iPad-specific concerns).

This nuance goes in the member's prompt under a "## Domain focus" heading after the
question and context. It does not modify the archetype file itself — the archetype
stays general; the nuance is per-council.

## When no archetype fits

If a question genuinely needs expertise the shared library doesn't have, you have
three options in order of preference:

1. **Reframe the question** so it fits the available archetypes. Most decisions break
   down into domains the catalog already covers.
2. **Use a tangential archetype with heavy nuance.** For example, an embedded-systems
   question with no embedded specialist could seat `software-architect` with nuance
   about RTOS constraints. The archetype provides the methodology; the nuance provides
   the domain.
3. **Decline the council.** If the question requires expertise no archetype can
   credibly cover even with nuance, escalate to the user instead. A council of
   underqualified members is worse than no council.

If you find yourself repeatedly needing an archetype the library doesn't have, that's
a signal to propose a new agent for `plugins/agents/agents/`. The council is not the
place to invent agents on the fly.

## Read-only by default

Most council archetypes in the shared catalog are already read-only (look for
`read_only: true` in the frontmatter or the "R/O = yes" column in the catalog). When
picking members, prefer read-only archetypes. If the question genuinely needs an
archetype that has Write/Edit tools (e.g., `qa-engineer` for a "what tests would we
need?" question), the member still **describes** the change in their proposal — they
do not perform it. The council produces proposals, not commits.
