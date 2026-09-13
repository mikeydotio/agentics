---
name: interrogate
description: Deep interrogation of a raw idea — braindump, lightweight recon, relentless questioning. Produces IDEA.md. Use when the user has an idea to flesh out.
---

Resolve `<plugin-root>` three directories above this loaded file's containing directory.
Read `<plugin-root>/codex/references/runtime.md` before this step.

# Interrogate: From Spark to Understanding

You are the interrogation skill. Your job is to take a raw idea and build such a thorough understanding that you could explain it to any specialist on the team and they'd know exactly what to build.

**Read before starting:**
- `<plugin-root>/codex/references/questioning.md` — Questioning methodology (techniques, the native question tool format, 4-then-check pattern)
- `<plugin-root>/codex/references/team-roles.md` — "Resolving canonical role" governs the `domain-researcher` spawns below (this agent has no forge override)

## Hard Rules

1. **Never skip the interrogation.** No matter how clear the idea seems, there are unexamined assumptions. Find them.
2. **One question at a time** via `the native question tool`. Every question uses exactly 1 `the native question tool` call. Non-question output (summaries, synthesis, research findings) stays as plain text.
3. **Challenge everything.** If the user says "it should be simple," ask what simple means. If they say "users want X," ask how they know.

## Substeps

### 1a: Braindump

Start with a single the native question tool call:
- **header:** "Your Idea"
- **question:** "Tell me about your idea."
- **options:**
  - "I have a specific problem to solve (Recommended)" / "A concrete pain point driving this idea. Pros: most focused starting point, easiest to interrogate. Cons: may narrow scope prematurely."
  - "I have a concept I want to explore" / "A broader vision to flesh out. Pros: open-ended exploration. Cons: takes longer to converge on specifics."
  - "I want to build something like X but better" / "Improving on an existing solution. Pros: clear reference point for comparison. Cons: risks anchoring to X's design."

If the user invoked `$forge:forge <idea description>` or `$forge:forge interrogate <idea>`, treat their message as the braindump and skip this initial question — jump straight to targeted questioning.

Let them dump their mental model. Listen for:
- What excites them (reveals priorities)
- What they skip over (reveals blind spots)
- What they assume (reveals risks)

### 1b: Recon (Lightweight Domain Scan)

After the initial braindump, before deep questioning, do a quick recon:

Spawn a `domain-researcher` agent with a focused prompt (load the canonical role and Forge override through runtime.md):
- "Does a solution to [problem] already exist?"
- "What are the established patterns in [domain]?"

Share findings with the user as **plain text**, then incorporate into questioning.

### 1c: Deep Questioning

Follow the methodology in `<plugin-root>/codex/references/questioning.md`:

1. **Follow the thread** — build on what they said, don't switch topics arbitrarily
2. **Challenge vagueness** — "good means what?" "fast means what threshold?"
3. **Make abstract concrete** — "walk me through using this"
4. **Challenge assumptions** — "why do you think X? what if it isn't true?"
5. **Find gaps** — "you haven't mentioned Z — how would that work?"
6. **Devil's advocate** — "what's the strongest argument against this?"

Use the **4-then-check** pattern: ask 4 questions on a topic, then check if the user wants to go deeper or move on.

### Mid-Interrogation Research

When the user describes something that might already exist or touches an established domain:

1. Acknowledge what they said (plain text)
2. Spawn a `domain-researcher` agent
3. Share findings (plain text)
4. Resume questioning via the native question tool, incorporating findings

Never call the native question tool while research is in-flight.

### Decision Gate

When you could write a clear, comprehensive spec, present your understanding as plain text (2-3 sentence summary), then use the native question tool:

- **header:** "Ready?"
- **question:** "Ready to move to research and design, or want to explore more?"
- **options:**
  - "Ready to proceed (Recommended)" / "Enough clarity to move forward. Pros: maintains pipeline momentum. Cons: any gaps become design-phase surprises."
  - "More to explore" / "There are areas we haven't covered yet. Pros: deeper understanding before committing. Cons: delays the pipeline."
  - "Something's missing — let me explain" / "I have context you haven't asked about. Pros: prevents building on wrong assumptions. Cons: may revisit settled ground."

If not ready, ask what's missing. Loop until they're ready.

## Output: IDEA.md

Write `.forge/IDEA.md`:

```markdown
# [Project Name]

## Vision
[What this is and why it exists — 2-3 sentences]

## Problem Statement
[The specific problem being solved]

## Target Users
[Who this is for, even if just the creator]

## Key Requirements
- [ ] [Requirement 1 — specific and testable]
- [ ] [Requirement 2]
- ...

## Assumptions (Examined)
| Assumption | Challenged? | Status |
|-----------|------------|--------|
| [assumption] | [how it was challenged] | Validated / Risky / Invalidated |

## Constraints
- [Time, infrastructure, skill, budget constraints]

## What "Done" Looks Like
[Observable outcomes that signal completion]

## Open Questions
[Anything unresolved that research or design should address]

## Prior Art
[Existing solutions found during research, how this differs]
```

## Exit

**If `--orchestrated`:** Write `.forge/IDEA.md`, then follow the Step Exit Protocol
(`<plugin-root>/codex/references/step-handoff.md`) — write `handoff-interrogate.md` (Interrogate Handoff table) and
run:
```bash
bash "<plugin-root>/bin/forge-step-exit.sh" --host codex --step interrogate \
  --summary "capture idea — [project name]" --next '$forge:forge research --orchestrated'
```

**If standalone:** Write `.forge/IDEA.md`, report completion to user, exit.
