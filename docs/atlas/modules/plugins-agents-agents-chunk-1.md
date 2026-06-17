---
module: "plugins/agents/agents (chunk 1)"
summary: "Shared agent library A–H — agent prompt contracts plus the _template and _guardrails standards"
read_when: "Adding or changing shared agents A–H, the agent template schema, or shared guardrails"
sources:
  - path: plugins/agents/agents/_guardrails.md
    blob: 5213bd863520baa4ca42aef7fd1cd5828704f457
  - path: plugins/agents/agents/_template.md
    blob: 011662bc9353e45dc267ae89dc35c1a9ced7ec11
  - path: plugins/agents/agents/accessibility-engineer.md
    blob: 9d5eb2340b5689f35405334abbe71a8aee9801c1
  - path: plugins/agents/agents/api-designer.md
    blob: 62c63c53316c459eaae0429ce2aa6281515172fc
  - path: plugins/agents/agents/cartographer.md
    blob: d632e074ecd39a0bd46d01ea8707ee6be9317811
  - path: plugins/agents/agents/copy-editor.md
    blob: 9b85e72f36f65cce77f9a4365e4d54c4834ca361
  - path: plugins/agents/agents/data-engineer.md
    blob: c419e74d2af3c9b8b924475d94a1ec0c1338798e
  - path: plugins/agents/agents/devops-engineer.md
    blob: f26d15023c8f2a8a12ee199052d9f18d34fac1fa
  - path: plugins/agents/agents/domain-researcher.md
    blob: 32a5ed047975d11391d015f6e79a7cb7b45370e1
  - path: plugins/agents/agents/evaluator.md
    blob: 04b337939a001e46f04898ca53e444b822d3cbbc
  - path: plugins/agents/agents/evidence-collector.md
    blob: 232c0bcdcd2d3d3d86f596fe2c517c1890ac9590
  - path: plugins/agents/agents/generator.md
    blob: 9d141116c64761c958a74977b14867e6729da8de
  - path: plugins/agents/agents/hypothesis-challenger.md
    blob: 49dac36dfb6c0f7a022497710e490b2d0869881e
references_modules: [plugins-agents-agents-chunk-2, plugins-atlas-references]
generator: cartographer/2
baseline: b4cedefaba8df96ee167877bf2ee9c3143ef0b08
---

# Module: plugins/agents/agents (chunk 1)

## Purpose

Alphabetical chunk A–H of the shared agent library plus the standards pair the library conforms
to: `_template.md` (frontmatter schema, `<role>` body skeleton) and `_guardrails.md` (shared
constraints). Each definition is a prompt contract — frontmatter is the spawn signature, the
body the methodology that must beat a bare LLM call. Holds the pipeline-specific cores: forge's
`generator`, `evaluator`, `domain-researcher`; rca's `evidence-collector` and
`hypothesis-challenger`; atlas's `cartographer`.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `accessibility-engineer` | general agent | `plugins/agents/agents/accessibility-engineer.md:2` | Read-only WCAG 2.2 AA + assistive-tech + cognitive audit; unverified criteria never pass |
| `api-designer` | general agent | `plugins/agents/agents/api-designer.md:2` | Read-only API review; flags every breaking change and unpaginated list |
| `cartographer` | atlas agent | `plugins/agents/agents/cartographer.md:2` | Maps one module into one atlas doc; writes only that doc; confirmation-only return |
| `copy-editor` | general agent | `plugins/agents/agents/copy-editor.md:2` | Edits user-facing text in place; flags every LLM tell; what/why/what-next errors |
| `data-engineer` | general agent | `plugins/agents/agents/data-engineer.md:2` | Schema/migration/query design; constraints in the DB; reversible migrations only |
| `devops-engineer` | general agent | `plugins/agents/agents/devops-engineer.md:2` | CI/CD, deploy, monitoring design; every deploy rollbackable; never writes secrets |
| `domain-researcher` | forge agent | `plugins/agents/agents/domain-researcher.md:2` | Read-only research; confidence-rated findings, license checks, 3+ alternatives |
| `evaluator` | forge agent | `plugins/agents/agents/evaluator.md:2` | Read-only judge; verdict JSON, per-criterion pass/fail with evidence; never fixes |
| `evidence-collector` | rca agent | `plugins/agents/agents/evidence-collector.md:2` | Read-only, facts-only evidence across categories A–G; causal claims banned |
| `generator` | forge agent | `plugins/agents/agents/generator.md:2` | Implements one story via red-green TDD; status JSON; never commits or touches `.forge/` |
| `hypothesis-challenger` | rca agent | `plugins/agents/agents/hypothesis-challenger.md:2` | Read-only falsification of root causes; STRONG/PROBABLE/WEAK/DISPROVED verdict |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `Agent Definition Template` | standard | `plugins/agents/agents/_template.md:1` | Schema + `<role>` body skeleton every agent follows; `name` must match filename |
| `Guardrails` | standard | `plugins/agents/agents/_guardrails.md:1` | Shared constraints every agent restates in its own Guardrails section |
| `<files_to_read>` | protocol | `plugins/agents/agents/_template.md:40` | Mandatory initial-read block in every body; how orchestrators inject context |
| `read_only` | frontmatter field | `plugins/agents/agents/_template.md:15` | Marks no-write agents; enforced by tool list plus post-run integrity checks |
| `verdict` | JSON field | `plugins/agents/agents/evaluator.md:123` | pass/fail key forge's execute loop branches on; one failed criterion forces fail |

## Relationships

- `plugins-agents-agents-chunk-1.cartographer -> plugins-agents-agents-chunk-2.software-architect (extends)`
- `plugins-agents-agents-chunk-1.cartographer -> plugins-atlas-references.map-format.md (reads)`
- `plugins-agents-agents-chunk-1.domain-researcher -> plugins-agents-agents-chunk-2.investigator (extends)`
- `plugins-agents-agents-chunk-1.evaluator -> plugins-agents-agents-chunk-2.qa-engineer (extends)`
- `plugins-agents-agents-chunk-1.evidence-collector -> plugins-agents-agents-chunk-2.investigator (extends)`
- `plugins-agents-agents-chunk-1.generator -> plugins-agents-agents-chunk-2.software-engineer (extends)`
- `plugins-agents-agents-chunk-1.hypothesis-challenger -> plugins-agents-agents-chunk-2.skeptic (extends)`
- `plugins-forge-skills.execute -> plugins-agents-agents-chunk-1.generator (calls)`
- `plugins-forge-skills.execute -> plugins-agents-agents-chunk-1.evaluator (calls)`
- `plugins-forge-skills.research -> plugins-agents-agents-chunk-1.domain-researcher (calls)`
- `plugins-rca.rca -> plugins-agents-agents-chunk-1.evidence-collector (calls)`
- `plugins-rca.rca -> plugins-agents-agents-chunk-1.hypothesis-challenger (calls)`
- `plugins-atlas-misc.atlas -> plugins-agents-agents-chunk-1.cartographer (calls)`
- `plugins-agents-misc.validate-agents.sh -> plugins-agents-agents-chunk-1._template.md (implements)`

## Type notes

- `read_only` bans Write/Edit; post-run integrity check — `plugins/agents/agents/_template.md:28`
- An evaluator that edits files forfeits its verdict — `plugins/agents/agents/evaluator.md:167`
- The generator must not commit or touch `.forge/` — `plugins/agents/agents/generator.md:139-140`
- Pipeline agents declare a methodology `Lineage` — `plugins/agents/agents/_template.md:90`

## External deps

- None — markdown prompts; `tools:` lists name Claude Code built-ins, not packages

## Gotchas

- code-archaeologist/systems-analyst merged — `plugins/agents/agents/hypothesis-challenger.md:18`
