# Agent Definition Template

This template codifies the standard for all agents in the shared library.

## YAML Frontmatter Schema

```yaml
---
name: <kebab-case identifier, must match filename>
description: <one-line description of role and core capabilities>
tools: <comma-separated list from: Read, Write, Edit, Bash, Grep, Glob, WebSearch, WebFetch>
color: <terminal color: green, red, blue, yellow, orange, purple, cyan>
tier: general | platform-variant | pipeline-specific
pipeline: pilot | rca | null
read_only: true | false
platform: cli | web | mobile | null
tags: [subset of: design, review, implementation, testing, investigation, challenge, documentation, operations, legal, research]
---
```

## Required Fields

- `name`: Must be kebab-case, must match the filename (without `.md`)
- `description`: One sentence. State what the agent does, not what it is.
- `tools`: Only list tools the agent genuinely needs. Read-only agents must NOT list Write or Edit.
- `color`: Visual differentiation in terminal output
- `tier`: `general` (reusable), `platform-variant` (UX per platform), `pipeline-specific` (tied to pilot/rca workflow)
- `read_only`: `true` if the agent should never modify files. Enforced via tool list AND post-execution integrity checks.
- `tags`: Used for catalog filtering and team composition

## Body Structure

The body must be wrapped in `<role>` tags and follow this structure:

```markdown
<role>
You are a [role name]. [One-sentence mission statement — the outcome, not the activity].

**CRITICAL: Mandatory Initial Read**
If the prompt contains a `<files_to_read>` block, you MUST use the Read tool
to load every file listed there before performing any other actions.

## Mission
[What success looks like. Define the outcome this agent produces.
Not "review code" but "surface the gaps that would cause production failures."]

## Methodology
[Domain-specific frameworks, checklists, taxonomies.
THIS is where the agent's value over a bare LLM lives.
Be concrete and prescriptive, not generic.
Reference specific standards (OWASP, WCAG, SOLID) with actionable checks.]

## Anti-Patterns
[Specific patterns this agent must detect and reject.
Name them explicitly with examples of what they look like in code/design.]

## Output Format
[Structured contract.
- JSON for machine-readable outputs (generator status, evaluator verdict)
- Markdown with defined sections for human-readable reports
- Include a concrete example of the expected output structure]

## Guardrails
[Include the shared guardrails from _guardrails.md plus any agent-specific additions:
- Read-only agents: "You have NO Write or Edit tools..."
- Write agents: "Only modify files within scope..."
- Agent-specific limits]

## Rules
[Hard constraints and quality standards. These are absolute — no exceptions.]
</role>
```

## Design Principle

Every agent must answer: "What does this agent know or enforce that a bare
claude-sonnet invocation would not?" The answer must include at least 2 of:

1. **Domain expertise** — specific frameworks, checklists, taxonomies
2. **Methodology** — structured approach preventing common mistakes
3. **Output contract** — structured format consuming systems can parse
4. **Defensive constraints** — guardrails preventing harm
5. **Anti-pattern detection** — specific patterns to flag and reject

## Cross-Pollination

Pipeline-specific agents should explicitly draw methodology from related
general-purpose agents. Document the lineage in the agent's Mission section:

> **Lineage**: Draws methodology from Software Engineer (TDD protocol),
> Security Researcher (secure-by-default coding), and Software Architect
> (design adherence checks).

This makes the cross-pollination explicit and auditable.
