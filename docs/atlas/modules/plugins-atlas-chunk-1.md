---
module: "plugins/atlas (chunk 1)"
summary: "Atlas plugin identity and user-facing documentation — marketplace registration and README"
read_when: "Touching atlas plugin identity, README, or user-facing command reference"
sources:
  - path: plugins/atlas/.claude-plugin/plugin.json
    blob: 48214a1798f73c5934e857252cb034cac416d031
  - path: plugins/atlas/README.md
    blob: d229efbe05ad7e06be39004ef215089c6a66e509
references_modules: [root-misc]
generator: cartographer/2
baseline: b4cedefaba8df96ee167877bf2ee9c3143ef0b08
verified: true
---

# Module: plugins/atlas (chunk 1)

## Purpose

This module is the identity and documentation layer of the atlas plugin: the marketplace registration that makes the plugin installable and the README that explains every user-facing command, the on-disk map layout, how incremental updates work, and what the staleness tier system means. It defines what atlas *is* to the outside world. The implementation, skills, references, and tests live in sibling modules.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `atlas` | plugin name | `plugins/atlas/.claude-plugin/plugin.json:2` | Marketplace identity; `source` resolves to `./plugins/atlas` in marketplace.json |

## Load-bearing internals

No load-bearing internal symbols — the two source files are a JSON manifest and a Markdown reference doc; they contain no executable symbols worth ranking.

## Relationships

- `plugins-atlas-chunk-1.atlas -> root-misc (reads)` — `plugins/atlas` is registered as a plugin entry in `.claude-plugin/marketplace.json`; the root module owns that registry

## Type notes

The plugin description in `plugin.json` (line 3) is the string surfaced in the marketplace listing. The README is the authoritative reference for all user-facing commands (`/atlas map`, `/atlas update`, `/atlas status`, `/atlas verify`, `/atlas repair`, `/atlas init`, `/atlas remove`), the `docs/atlas/` disk layout, blob-SHA incremental update semantics, staleness tiers 0–3, merge conflict handling, `docs/atlas/config.yaml` schema, and runtime requirements. It explicitly points to `references/design.md` and `references/map-format.md` for deeper decision records and format rules (line 245–246).

## External deps

- git — blob invalidation via `ls-tree` and `hash-object` (README:241)
- python3 — stdlib-only deterministic CLI (README:242)
- jq — required by the SessionStart hook (README:243)

## Gotchas

- `INDEX.md` and `atlas-ledger.json` are derived files; hand edits are overwritten on the next rebuild (README:218–221). `merge=union` is explicitly forbidden for both (README:238–239).
- Atlas never writes `.gitattributes` on its own; the linguist-generated suggestions are advisory only (README:168).
- Map and update operations refuse while `MERGE_HEAD` exists; finish or abort any in-progress merge first (README:189–190).
