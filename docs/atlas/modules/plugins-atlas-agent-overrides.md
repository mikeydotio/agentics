---
module: plugins/atlas/agent-overrides
summary: "Atlas-specific constraint injections that narrow shared agents (cartographer, map-verifier, map-repairer) to atlas pipeline rules"
read_when: "Changing atlas agent behavior, spawn constraints, or repair/verify protocols"
sources:
  - path: plugins/atlas/agent-overrides/cartographer-context.md
    blob: ef2975f57a95977b1c47f8c18566ccb38bb0d0ed
  - path: plugins/atlas/agent-overrides/map-repairer-context.md
    blob: 36b934944b5b80ae623280af602c4f7bed9a241a
  - path: plugins/atlas/agent-overrides/map-verifier-context.md
    blob: 7233cde0eb20367f4f0bd64eed2858d387df7839
references_modules: [plugins-agents-agents-chunk-1, plugins-agents-agents-chunk-2, plugins-atlas-references]
generator: cartographer/2
baseline: b4cedefaba8df96ee167877bf2ee9c3143ef0b08
---

# Module: plugins/atlas/agent-overrides

## Purpose

This module holds the atlas-specific constraint overlays that are prepended to shared agent
definitions when the atlas orchestrator spawns cartographer, map-verifier, and map-repairer.
Each file narrows a general-purpose agent role to the atlas pipeline's exact write targets,
frontmatter contracts, and return formats. Without these overrides the shared agents would
lack atlas-specific invariants (e.g., never write blob/sha, keep untouched lines byte-identical,
emit only JSON verdicts under 4KB).

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `cartographer-context.md` | override doc | `plugins/atlas/agent-overrides/cartographer-context.md:1` | Constrains cartographer: write target, frontmatter fields, budget limits, allowed relationship verbs, incremental discipline |
| `map-repairer-context.md` | override doc | `plugins/atlas/agent-overrides/map-repairer-context.md:1` | Constrains map-repairer: findings-only scope, fields it may/may not touch, drift-doc handling, byte-identical discipline |
| `map-verifier-context.md` | override doc | `plugins/atlas/agent-overrides/map-verifier-context.md:1` | Constrains map-verifier: verdict routing, persistent-failure behavior, sources-list completeness check, no-file-modify rule |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `Relationship verbs` | constraint block | `plugins/atlas/agent-overrides/cartographer-context.md:31` | Enumerates the only allowed edge verbs; lint L13 enforces this; both cartographer and map-repairer contexts repeat it |
| `Frontmatter contract` | constraint block | `plugins/atlas/agent-overrides/cartographer-context.md:8` | Defines the exact fields a cartographer writes and explicitly forbids blob/sha/baseline/verified — critical for ledger correctness |
| `Incremental discipline` | constraint block | `plugins/atlas/agent-overrides/map-repairer-context.md:39` | Byte-identical untouched-line rule prevents hash churn that defeats the ledger's purpose |

## Relationships

- `plugins-atlas-agent-overrides.cartographer-context.md -> plugins-agents-agents-chunk-1.cartographer (extends)` — override is injected alongside the shared cartographer role per `plugins/atlas/references/mapping-protocol.md:65`
- `plugins-atlas-agent-overrides.map-verifier-context.md -> plugins-agents-agents-chunk-2.map-verifier (extends)` — override is injected alongside the shared map-verifier role per `plugins/atlas/references/mapping-protocol.md:96`
- `plugins-atlas-agent-overrides.map-repairer-context.md -> plugins-agents-agents-chunk-2.map-repairer (extends)` — override is injected alongside the shared map-repairer role per `plugins/atlas/references/update-protocol.md:305`
- `plugins-atlas-references.update-protocol -> plugins-atlas-agent-overrides.map-repairer-context.md (reads)` — update-protocol names this file in the fixer-wave prompt assembly at `plugins/atlas/references/update-protocol.md:305`
- `plugins-atlas-references.mapping-protocol -> plugins-atlas-agent-overrides.cartographer-context.md (reads)` — mapping-protocol names this file in the cartographer `<files_to_read>` block at `plugins/atlas/references/mapping-protocol.md:66`

## Type notes

Each override file is a pure markdown document with no frontmatter; it is concatenated into
an agent spawn prompt, not executed. The cartographer-context and map-repairer-context both
carry the relationship-verb constraint (`calls, implements, conforms-to, extends, emits, owns,
reads, writes`) because both agents write or repair Relationships edges. The map-verifier-context
does not carry a write-target rule because verifiers never modify files
(`plugins/atlas/agent-overrides/map-verifier-context.md:18`). The `summary` and `read_when`
budget caps (≤120 and ≤90 chars respectively) are stated only in cartographer-context, not
map-repairer-context, because repair never re-derives frontmatter from scratch.

## External deps

None — these are plain markdown files consumed by atlas CLI orchestration at spawn time.

## Gotchas

- `map-repairer-context.md:20` forbids touching `sources` paths during repair; adding/removing a source is re-derivation, which belongs to `/atlas update` not repair.
- `cartographer-context.md:27` sets a `read_when` aim of ≤70 chars in practice, stricter than the ≤90 char hard limit, because long module ids consume the INDEX routing row budget.
