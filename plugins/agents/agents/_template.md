# Agent Definition Template

This template codifies the standard for all agents in the shared library.

## YAML Frontmatter Schema

```yaml
---
name: <kebab-case identifier, must match filename>
description: <one-line description of role and core capabilities>
tools: <comma-separated list from: Read, Write, Edit, Bash, Grep, Glob, WebSearch, WebFetch>
model: <optional: haiku | sonnet — omit to inherit the session model>
effort: <low | medium | high | xhigh>
color: <terminal color: green, red, blue, yellow, orange, purple, cyan>
tier: general | platform-variant | pipeline-specific
pipeline: forge | rca | null
read_only: true | false
platform: cli | web | mobile | null
tags: [subset of: design, review, implementation, testing, investigation, challenge, documentation, operations, legal, research]
---
```

## Required Fields

- `name`: Must be kebab-case, must match the filename (without `.md`)
- `description`: One sentence. State what the agent does, not what it is.
- `tools`: Only list tools the agent genuinely needs. Read-only agents must NOT list Write or Edit.
- `model`: **Omit it unless you are moving work *down* a tier.** A subagent gets a fresh context
  window sized by its own model, so `haiku` and `sonnet` are both safe here (unlike in a skill,
  where a small model shares — and can overflow — the session window). Never pin `opus` or
  `fable`: those aliases resolve to the latest of their line, so pinning is a no-op when the
  session is already there and a *downgrade* when the session is on something more capable.
  Omitting the field inherits, which is what a judgment-tier agent wants.
- `effort`: The real dial. `low` for bounded mechanical work, `medium` for multi-step but
  well-specified work, `high` for genuine analysis, `xhigh` for adversarial and long-horizon
  reasoning. Set it on every agent — the session default would otherwise apply uniformly to
  agents whose work is anything but uniform.
- `color`: Visual differentiation in terminal output
- `tier`: `general` (reusable), `platform-variant` (UX per platform), `pipeline-specific` (tied to forge/rca workflow)
- `read_only`: `true` if the agent should never modify files. The `tools:` list is enforced by the
  platform ONLY when a consuming plugin spawns this agent via its registered `subagent_type:
  "<plugin>:<name>"` (e.g. `agents:evaluator`) — see `references/cross-plugin-usage.md`'s
  "Spawning Pattern". If a consumer falls back to `subagent_type: "general-purpose"` (no such type
  exposed), the tool list is advisory prose only and post-execution integrity checks become the
  sole enforcement. Don't claim tool-level enforcement in a consuming plugin's docs unless that
  plugin actually resolves to the registered type.
- `tags`: Used for catalog filtering and team composition

## Body Structure

The body must be wrapped in `<role>` tags and follow this structure:

```markdown
<role>
You are a [role name]. [One-sentence mission statement — the outcome, not the activity].

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
[The canonical four-bullet block from _guardrails.md, verbatim and first — it is checked
byte-for-byte by bin/validate-agents.sh — followed by agent-specific additions only:
- Read-only agents: "You have NO Write or Edit tools..."
- A concrete scope line naming this agent's boundary
- Domain-specific refusals, severity rules, or pipeline contracts
Never restate a canonical bullet in different words.]

## Rules
[Hard constraints and quality standards. These are absolute — no exceptions.]
</role>
```

## Design Principle

Every agent must answer: "What does this agent know or enforce that an unprompted
invocation of the same model would not?" The answer must include at least 2 of:

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
