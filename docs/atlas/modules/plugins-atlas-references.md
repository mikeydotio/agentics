---
module: plugins/atlas/references
summary: "Normative design record, map/doc format spec, and orchestration protocols for atlas v2's structure/judgment projection."
read_when: "Changing atlas's map format, protocols, or the CLAUDE.md injection contract"
sources:
  - path: plugins/atlas/references/claude-md-injection.md
    blob: 96ea2bd6d2dc31b25caac57c09099c298c1da0ec
  - path: plugins/atlas/references/design-v2.md
    blob: 17658b4dafbd2b35208f0f93ea1612eb3f61b21d
  - path: plugins/atlas/references/map-format.md
    blob: 180d8e724e10e9bfe42a4a9b314fb2c15eb6c9ee
  - path: plugins/atlas/references/mapping-protocol.md
    blob: 574b60d5b22e025b7bc34f165cbdb2fadc0b74c4
  - path: plugins/atlas/references/update-protocol.md
    blob: 7fbd5134f7bb12ed427d613759adb4ed0c593213
generator: cartographer/4
baseline: cb09ceb006e3fb4759a91d64d9e6655e67d04bf7
---

# Module: plugins/atlas/references

## Purpose

This is atlas's normative rulebook: design-v2.md is the authoritative design record justifying every architectural decision (extraction, judgment keying, projection, staleness tiers), while map-format.md, mapping-protocol.md, update-protocol.md, and claude-md-injection.md are the executable specs the /atlas skill dispatches to and that lint, cartographer, and map-verifier are held accountable against. The one idea holding it together: the skill stays a thin router precisely because these docs carry every detailed procedure and format rule out of it. If this module vanished, the orchestrator would have no step-by-step protocol to follow, cartographers would have no format contract to write cells against, and the rationale behind judgment-key derivation and staleness tiers would be lost.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

design-v2.md is authoritative over the retired v1 design.md, whose content is folded into its own 'v1 base' section rather than kept as a separate file (plugins/atlas/references/design-v2.md:499-501). map-format.md declares itself normative over an agent's own instinct when the two disagree (plugins/atlas/references/map-format.md:5-6). claude-md-injection.md defers ownership of the literal block text to bin/atlas-cli's CLAUDE_MD_BLOCK constant, treating itself as descriptive only (plugins/atlas/references/claude-md-injection.md:25-26). Both orchestration protocols encode a load-bearing step order rather than free ordering: /atlas map requires project before finalize before index rebuild, with init before finalize whenever CLAUDE.md or .gitignore is a mapped source (plugins/atlas/references/mapping-protocol.md:9-13), and /atlas update repeats the identical constraint (plugins/atlas/references/update-protocol.md:10-11).

## External deps


## Gotchas

claude-md-injection.md documents bin/atlas-cli's CLAUDE_MD_BLOCK constant but is not itself the source of truth: 'If they ever diverge, the CLI is authoritative' (plugins/atlas/references/claude-md-injection.md:25-26) — editing this doc alone never changes injected content. design-v2.md notes an explicit `--backend treesitter` request with no helper installed does NOT error; it still produces a valid index with `degraded: true`, 'a tested, first-class mode, not an error' (plugins/atlas/references/design-v2.md:106-108).
