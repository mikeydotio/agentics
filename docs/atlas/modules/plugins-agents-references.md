---
module: plugins/agents/references
summary: "Contract docs for the shared agent library — roster catalog, design quality bar, spawn protocol, tool audit"
read_when: "Choosing/staffing shared agents, writing agent-overrides, or auditing plugin tool design"
sources:
  - path: plugins/agents/references/agent-catalog.md
    blob: f93292a997df80ef3a018c3b1471854af9ec9cb1
  - path: plugins/agents/references/agent-design-principles.md
    blob: 5403c125a741fe7f632141b408ed8605da796133
  - path: plugins/agents/references/cross-plugin-usage.md
    blob: 0085451323188046cb2513c52c2f0d3a500d48d3
  - path: plugins/agents/references/tool-audit.md
    blob: b16db34d0e9301d6a9177aab1bb9a49cd664549c
generator: cartographer/4
baseline: 50c998d53e2ed58951ac5f794afd32bfa729f658
---

# Module: plugins/agents/references

## Purpose

These four references form the shared agent library's contract surface: the catalog indexes the roster and per-project-type staffing matrix, the design principles set the existence bar (at least 2 of 5 value dimensions) and canonical failure-mode mitigations every library agent must satisfy, and the cross-plugin usage guide pins the spawn-resolution order (`agents:<name>` preferred, `general-purpose` plus inlined definition as fallback) and override-layering contract that forge, rca, and other consumers concatenate into their prompts. The tool audit closes the loop by scoring the ecosystem's actual tool surfaces (storyhook, freshen, greenlight, semver, forge) against those same five design principles. Without this module, consuming plugins would have no shared definition of how to safely resolve, spawn, and layer context onto shared agents, and each pipeline's SKILL.md would have to reinvent the spawn protocol independently.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

- Spawn resolution is preference-ordered: try `agents:<name>` as `subagent_type` first (`plugins/agents/references/cross-plugin-usage.md:37`), falling back to `general-purpose` with the shared role definition inlined into the prompt only in that fallback case (`plugins/agents/references/cross-plugin-usage.md:42`).
- `AGENTS_PLUGIN_ROOT` must be derived as a sibling of the consuming plugin's own root; `${CLAUDE_PLUGIN_ROOT}` resolves to the consumer's own directory, never to the shared `agents` plugin (`plugins/agents/references/cross-plugin-usage.md:10`).
- Override layering is transparent concatenation, not inheritance — a pipeline override adds to the shared role definition and never replaces it (`plugins/agents/references/cross-plugin-usage.md:107`).
- The `<plugin>:<agent>` notation (e.g. `agents:software-architect`) is documentation shorthand for the Preferred/Fallback/Don't-guess resolution, not a literal path or a shortcut around it (`plugins/agents/references/cross-plugin-usage.md:135`).
- An agent may only exist in the library if it demonstrates value across at least 2 of 5 dimensions (domain expertise, methodology, output contract, defensive constraints, anti-pattern detection); otherwise it shouldn't exist as a dedicated agent (`plugins/agents/references/agent-design-principles.md:111`).

## External deps


## Gotchas

- tool-audit.md flags forge's `storyhook-contract.md` "Commands That DO NOT Exist" section as actively stale/misleading — it claims tools that actually exist do not (`plugins/agents/references/tool-audit.md:316`).
- cross-plugin-usage.md's own example override directory breaks its own `<name>-context.md` naming convention: the RCA listing includes `investigator-rca.md` and `architect-rca.md` instead of `investigator-context.md`/`architect-context.md` (`plugins/agents/references/cross-plugin-usage.md:95`).
