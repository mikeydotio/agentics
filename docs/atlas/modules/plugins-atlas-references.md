---
module: plugins/atlas/references
summary: "Normative canon for atlas — design rationale, map file format, full-map and update orchestration, CLAUDE.md delivery"
read_when: "Changing atlas behavior, map format, orchestration steps, or the CLAUDE.md block"
sources:
  - path: plugins/atlas/references/claude-md-injection.md
  - path: plugins/atlas/references/design.md
  - path: plugins/atlas/references/map-format.md
  - path: plugins/atlas/references/mapping-protocol.md
  - path: plugins/atlas/references/update-protocol.md
references_modules: [plugins-agents-agents-chunk-1, plugins-agents-agents-chunk-2, plugins-atlas-chunk-2, plugins-atlas-agent-overrides]
generator: cartographer/2
---

# Module: plugins/atlas/references

## Purpose

The atlas plugin's written constitution, split by authority: design.md records the locked
decisions and their rationale, map-format.md prescribes the exact shape of every file atlas
writes, mapping-protocol.md sequences the full-map run, update-protocol.md sequences the
incremental update and verify flows, and claude-md-injection.md specifies
delivery into a project's CLAUDE.md. Agents receive these docs by reference in
`<files_to_read>` at spawn time, so editing this module changes mapper behavior without
touching any code. Without it the pipeline has no normative format, no step ordering, and no
injection contract.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `Atlas Design Record` | doc | `plugins/atlas/references/design.md:1` | Locked decisions, invalidation rationale, staleness tiers, atlas-cli surface, partitioning + new-file assignment specs |
| `Atlas Map Format` | doc | `plugins/atlas/references/map-format.md:1` | Normative shape of everything atlas writes; wins over agent instinct when they disagree |
| `CLAUDE.md Managed Block` | doc | `plugins/atlas/references/claude-md-injection.md:1` | Marker-delimited block carrying the `@docs/atlas/INDEX.md` import; inject/remove are idempotent |
| `Full-Map Protocol` | doc | `plugins/atlas/references/mapping-protocol.md:1` | Step-ordered `/atlas map` run: agents write docs, the CLI does the deterministic work |
| `Incremental Update Protocol` | doc | `plugins/atlas/references/update-protocol.md:1` | Step-ordered `/atlas update` run; unchanged docs never reach an LLM; includes the read-only `/atlas verify` and surgical `/atlas repair` flows |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `<!-- atlas:index-facts -->` | marker | `plugins/atlas/references/map-format.md:201` | Overview block extracted verbatim into the INDEX; spends the INDEX's 7,000-char budget |
| `<!-- atlas:start -->` | marker | `plugins/atlas/references/claude-md-injection.md:11` | Managed-block delimiter; `init` and `remove` key on the exact marker pair |
| `Failure discipline` | section | `plugins/atlas/references/mapping-protocol.md:140` | Every abort path releases the lock; a map that fails lint is never committed; never `git add -A` |
| `Generator fingerprint` | section | `plugins/atlas/references/map-format.md:234` | Prompt-version + model stamp; a bump marks every doc fingerprint-stale on the next ledger diff |
| `Partitioning algorithm` | section | `plugins/atlas/references/design.md:170` | Deterministic partitioning keeps module identity — and therefore doc identity — stable |
| `Staleness tiers` | section | `plugins/atlas/references/design.md:108` | T0–T3 trust ladder; the T3 "disregard the imported INDEX" suppression is load-bearing, not polish |
| `Step order is load-bearing` | rule | `plugins/atlas/references/update-protocol.md:10` | Verify before overview, wave A before ripple wave B, every mutation before the final finalize |

## Relationships

- `plugins-atlas-references.claude-md-injection -> plugins-atlas-chunk-2.atlas-cli (reads)`
- `plugins-atlas-references.mapping-protocol -> plugins-agents-agents-chunk-1.cartographer (reads)`
- `plugins-atlas-references.mapping-protocol -> plugins-agents-agents-chunk-2.map-verifier (reads)`
- `plugins-atlas-references.mapping-protocol -> plugins-atlas-chunk-2.atlas-router.sh (calls)`
- `plugins-atlas-references.mapping-protocol -> plugins-atlas-agent-overrides.cartographer-context (reads)`
- `plugins-atlas-references.mapping-protocol -> plugins-atlas-agent-overrides.map-verifier-context (reads)`
- `plugins-atlas-references.mapping-protocol -> plugins-atlas-references.map-format (reads)`
- `plugins-atlas-references.update-protocol -> plugins-agents-agents-chunk-1.cartographer (reads)`
- `plugins-atlas-references.update-protocol -> plugins-agents-agents-chunk-2.map-verifier (reads)`
- `plugins-atlas-references.update-protocol -> plugins-agents-agents-chunk-2.map-repairer (reads)`
- `plugins-atlas-references.update-protocol -> plugins-atlas-agent-overrides.map-repairer-context (reads)`
- `plugins-atlas-references.update-protocol -> plugins-atlas-references.mapping-protocol (reads)`

## Type notes

Authority is asymmetric by design. For map content, map-format.md wins over agent instinct
(plugins/atlas/references/map-format.md:6); for the managed block, `CLAUDE_MD_BLOCK` inside
the CLI is canonical and the doc only records it
(plugins/atlas/references/claude-md-injection.md:25).
Frontmatter ownership is split: cartographers write `module`, `summary`, `read_when`,
`sources` (paths only), and `references_modules`; `ledger finalize` adds `blob`, `baseline`,
`verified`, and normalizes `generator` (plugins/atlas/references/map-format.md:38).
Full-map step order is load-bearing: verification precedes the overview pass because
`ledger set-verified` rewrites module-doc frontmatter that the overview's ledger entries hash
(plugins/atlas/references/mapping-protocol.md:8).
The repair flow (update-protocol.md §R0–R8) differs from update: driven by verify findings,
not the ledger diff; uses map-repairer (targeted Edit) instead of cartographer (full
re-derivation); `ledger finalize --except <drift-ids>` keeps drift docs flagged after body
fixes (plugins/atlas/references/update-protocol.md:314).
Design lineage: the no-PID heartbeat lock adopts the forge plugin's session-locking rationale
(plugins/atlas/references/design.md:29); the marker-block pattern follows the semver plugin
(plugins/atlas/references/claude-md-injection.md:4).

## External deps

- git plumbing — blob-SHA invalidation (`ls-tree`, `hash-object`) that the design record relies on
- Claude Code `@import` — INDEX delivery uses the native CLAUDE.md import; readers need no plugin

## Gotchas

- Changing map-format.md or the cartographer prompt without a generator-version bump freezes
  stale docs in place (plugins/atlas/references/map-format.md:239)
- INDEX.md and atlas-ledger.json conflicts are resolved by rebuilding, never hand-merged;
  `merge=union` corrupts map files (plugins/atlas/references/map-format.md:230)
