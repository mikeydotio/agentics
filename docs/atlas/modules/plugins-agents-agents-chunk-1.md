---
module: "plugins/agents/agents (chunk 1)"
summary: "Shared agent contract (template + guardrails) plus 11 agents, accessibility-engineer through hypothesis-challenger."
read_when: "Adding or changing shared agents A–H, the agent template schema, or shared guardrails"
sources:
  - path: plugins/agents/agents/_guardrails.md
    blob: 5213bd863520baa4ca42aef7fd1cd5828704f457
  - path: plugins/agents/agents/_template.md
    blob: 2f02ce72b5fbd726c335a17c23fa886e62e12608
  - path: plugins/agents/agents/accessibility-engineer.md
    blob: 9d5eb2340b5689f35405334abbe71a8aee9801c1
  - path: plugins/agents/agents/api-designer.md
    blob: 62c63c53316c459eaae0429ce2aa6281515172fc
  - path: plugins/agents/agents/cartographer.md
    blob: 95c8a9bf0cd580cf5ce1fe316f33ab8a835fcdbe
  - path: plugins/agents/agents/copy-editor.md
    blob: 9b85e72f36f65cce77f9a4365e4d54c4834ca361
  - path: plugins/agents/agents/data-engineer.md
    blob: c419e74d2af3c9b8b924475d94a1ec0c1338798e
  - path: plugins/agents/agents/devops-engineer.md
    blob: f26d15023c8f2a8a12ee199052d9f18d34fac1fa
  - path: plugins/agents/agents/domain-researcher.md
    blob: 32a5ed047975d11391d015f6e79a7cb7b45370e1
  - path: plugins/agents/agents/evaluator.md
    blob: 082350b18419ec31b4dd2d700dee1239012f56ad
  - path: plugins/agents/agents/evidence-collector.md
    blob: 232c0bcdcd2d3d3d86f596fe2c517c1890ac9590
  - path: plugins/agents/agents/generator.md
    blob: ce5e3ff4fc21bb701db1910eb780382945291489
  - path: plugins/agents/agents/hypothesis-challenger.md
    blob: 49dac36dfb6c0f7a022497710e490b2d0869881e
generator: cartographer/4
baseline: 50c998d53e2ed58951ac5f794afd32bfa729f658
---

# Module: plugins/agents/agents (chunk 1)

## Purpose

This slice of the shared agent library holds the two governing documents — `_template.md`'s frontmatter/body schema and `_guardrails.md`'s non-negotiable constraints — plus 11 of the agent definitions every consuming plugin (forge, rca, atlas, council) spawns from. Each agent pairs a narrow mission (evaluator's pass/fail verdict, generator's TDD implementation, evidence-collector's facts-only reporting, cartographer's module mapping) with an explicit Lineage line crediting the general-purpose techniques it draws from, making cross-pollination auditable rather than implicit. Without this chunk, forge loses generator/evaluator/domain-researcher, rca loses evidence-collector/hypothesis-challenger, atlas loses cartographer, and the rest of the agent library loses its structural template and guardrail baseline.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

- `_template.md` and `_guardrails.md` are non-executable governance docs, not agents: every other file in this chunk follows `_template.md`'s frontmatter/body schema (plugins/agents/agents/_template.md:5-78) and is expected to fold in `_guardrails.md`'s six guardrail categories, though each agent hand-writes its own Guardrails section rather than importing the shared text verbatim (compare plugins/agents/agents/evaluator.md:205-212 to plugins/agents/agents/_guardrails.md:1-41).
- Frontmatter fields are load-bearing metadata, not decoration: `tools` is enforced by the platform only when a consuming plugin spawns the agent via its registered `subagent_type` (e.g. `agents:evaluator`); falling back to `subagent_type: "general-purpose"` demotes the tool list to advisory prose only (plugins/agents/agents/_template.md:28-34).
- `read_only: true` agents in this chunk (accessibility-engineer, api-designer, domain-researcher, evaluator, evidence-collector, hypothesis-challenger) all omit Write/Edit from `tools` and restate "You have NO Write or Edit tools" in their own Guardrails section (e.g. plugins/agents/agents/evidence-collector.md:173, plugins/agents/agents/hypothesis-challenger.md:217); evaluator.md additionally notes the orchestrator runs a post-execution integrity check that discards the verdict if files were touched (plugins/agents/agents/evaluator.md:212).
- Every agent's body opens with a "Mandatory Initial Read" clause requiring a `<files_to_read>` block be fully read before any other action — repeated across all 11 role files (e.g. plugins/agents/agents/generator.md:18-19, plugins/agents/agents/cartographer.md:18-19).
- generator.md and evaluator.md share one verdict schema by cross-reference rather than duplication: evaluator.md declares its JSON verdict "the single authoritative evaluator verdict schema" that other docs must reference rather than redefine (plugins/agents/agents/evaluator.md:119-123), and generator.md's "On Retry" section consumes the compact `{verdict, failures}` projection of that exact schema (plugins/agents/agents/generator.md:107-112).

## External deps


## Gotchas

- The `tools:` frontmatter field looks like a hard restriction but is advisory-only prose unless the consuming plugin actually spawns the agent via its registered `subagent_type`; a fallback to `subagent_type: "general-purpose"` leaves post-execution integrity checks as the sole enforcement (plugins/agents/agents/_template.md:28-34).
- generator.md is explicitly forbidden from committing its own work — "CRITICAL: Do NOT commit. Write code only. The orchestrator commits after evaluation passes" — a constraint distinct from every other write-capable agent in this chunk (plugins/agents/agents/generator.md:144).
- evaluator.md's verdict is deliberately stored in two different shapes to resolve a size conflict: the full object (every field, no truncation) is logged to `.forge/verdicts.jsonl` with no size limit, while only a compact `{verdict, failures}` projection becomes the storyhook retry comment — `failures[]` itself must never be truncated to make the compact form fit (plugins/agents/agents/evaluator.md:194-203).
