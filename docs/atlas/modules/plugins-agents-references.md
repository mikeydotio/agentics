---
module: plugins/agents/references
summary: "Contract docs for the shared agent library — roster catalog, design quality bar, spawn protocol, tool audit"
read_when: "Choosing/staffing shared agents, writing agent-overrides, or auditing plugin tool design"
sources:
  - path: plugins/agents/references/agent-catalog.md
    blob: 9e433b3006aa9f81c3e7ecb912c4adeca7b62d6c
  - path: plugins/agents/references/agent-design-principles.md
    blob: 5403c125a741fe7f632141b408ed8605da796133
  - path: plugins/agents/references/cross-plugin-usage.md
    blob: ce6e63ac20b5e43778b1dee78955d334d6bb3b1b
  - path: plugins/agents/references/tool-audit.md
    blob: b16db34d0e9301d6a9177aab1bb9a49cd664549c
references_modules: [plugins-agents-agents-chunk-1, plugins-agents-agents-chunk-2, plugins-agents-agents-chunk-3, plugins-agents-agents-ux, plugins-forge-references, plugins-forge-skills, plugins-freshen, plugins-greenlight, plugins-rca, plugins-semver-misc]
generator: cartographer/2
baseline: b4cedefaba8df96ee167877bf2ee9c3143ef0b08
---

# Module: plugins/agents/references

## Purpose

These docs are the agent library's contract surface: how plugins discover, vet, and spawn agents.
The catalog indexes the roster and staffing matrix; the design principles gate what may exist.
The usage guide pins the inline-spawn and override-layering protocol that forge and rca follow;
the tool audit records five-principle findings across the plugin ecosystem.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `Agent Design Principles` | doc | `plugins/agents/references/agent-design-principles.md:1` | Quality bar and orchestration patterns every library agent definition must satisfy |
| `Cross-Plugin Usage Guide` | doc | `plugins/agents/references/cross-plugin-usage.md:1` | Spawn contract: path convention, override layering, namespace notation, migration checklist |
| `Shared Agent Catalog` | doc | `plugins/agents/references/agent-catalog.md:1` | Roster index — tools, read-only flag, tags per agent — plus team matrix by project type |
| `Tool Design Audit` | doc | `plugins/agents/references/tool-audit.md:1` | Five-principle audit of storyhook, freshen, greenlight, semver, and forge with priorities |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `Agent Definition Quality Bar` | section | `plugins/agents/references/agent-design-principles.md:100` | Existence gate — an agent must show at least 2 of 5 value dimensions or it should not exist |
| `Cross-Pollination Principle` | section | `plugins/agents/references/agent-design-principles.md:113` | Pipeline agents must name the general-purpose lineage their methodology draws from |
| `Migration Checklist` | section | `plugins/agents/references/cross-plugin-usage.md:137` | Six-step port of a consuming plugin onto shared agents; ends by deleting its local agents/ dir |
| `Override Layering` | section | `plugins/agents/references/cross-plugin-usage.md:58` | Prompt = shared definition + pipeline override + dynamic context; concatenation, not inheritance |
| `Preventing Failure Modes` | section | `plugins/agents/references/agent-design-principles.md:71` | Canonical mitigations: deadlock, runaway loops, denial-of-wallet, feedback amplification |
| `Team Composition by Project Type` | section | `plugins/agents/references/agent-catalog.md:61` | Staffing matrix; Skeptic and Investigator recommended for every project type |

## Relationships

- `plugins-agents-references.agent-catalog -> plugins-agents-agents-chunk-1.generator (reads)`
- `plugins-agents-references.agent-catalog -> plugins-agents-agents-chunk-2.skeptic (reads)`
- `plugins-agents-references.agent-catalog -> plugins-agents-agents-chunk-3.triager (reads)`
- `plugins-agents-references.agent-catalog -> plugins-agents-agents-ux.ux-designer-cli (reads)`
- `plugins-agents-references.cross-plugin-usage -> plugins-rca.investigator-rca (reads)`
- `plugins-agents-references.tool-audit -> plugins-forge-references.storyhook-contract (reads)`
- `plugins-agents-references.tool-audit -> plugins-forge-skills.SKILL.md (reads)`
- `plugins-agents-references.tool-audit -> plugins-freshen.freshen.sh (reads)`
- `plugins-agents-references.tool-audit -> plugins-greenlight.greenlight.sh (reads)`
- `plugins-agents-references.tool-audit -> plugins-semver-misc.SKILL.md (reads)`

## Type notes

- Spawning is inlining (`plugins/agents/references/cross-plugin-usage.md:17`); no registry.
- Overrides add, never replace (`plugins/agents/references/cross-plugin-usage.md:66`).
- Overrides carry pipeline-only content (`plugins/agents/references/cross-plugin-usage.md:70`).
- `<plugin>:<agent>` is docs notation only (`plugins/agents/references/cross-plugin-usage.md:93`).
- Plugins use Anthropic patterns 4-7 (`plugins/agents/references/agent-design-principles.md:24`).

## External deps

- storyhook — external story tracker (`story` CLI + MCP tools); chief subject of the tool audit
- Anthropic "Building Effective Agents" + Agentailor article — sources for the principles

## Gotchas

- Audit flags forge's storyhook contract as stale (`plugins/agents/references/tool-audit.md:316`).
- rca override names vary from -context.md (`plugins/agents/references/cross-plugin-usage.md:54`).
