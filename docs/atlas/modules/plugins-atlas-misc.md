---
module: "plugins/atlas (misc)"
summary: "Atlas core — deterministic atlas-cli (scan/partition/ledger/INDEX/lint), /atlas skill, router, staleness hook"
read_when: "Touching atlas-cli subcommands, /atlas orchestration, the session hook, or blob ledger"
sources:
  - path: plugins/atlas/.claude-plugin/plugin.json
    blob: 48214a1798f73c5934e857252cb034cac416d031
  - path: plugins/atlas/README.md
    blob: b425bd2e7b2eab011326a8ac19091a0931b7729f
  - path: plugins/atlas/agent-overrides/cartographer-context.md
    blob: 958ae88df7fb648d7d0ef704546f4b22e8997a6f
  - path: plugins/atlas/agent-overrides/map-verifier-context.md
    blob: 7233cde0eb20367f4f0bd64eed2858d387df7839
  - path: plugins/atlas/bin/atlas-cli
    blob: b166e95ef0511153f34b03c6babda59cdc60da6b
  - path: plugins/atlas/bin/atlas-router.sh
    blob: 048600f5049437b86d10ca7252fee5e57452d5ca
  - path: plugins/atlas/hooks/hooks.json
    blob: 41851681fe5ce7fdd0fc14b33dd4868d38398e6a
  - path: plugins/atlas/hooks/session-start.sh
    blob: 4277ada1b6f54bba1034edf015c622f6a3a3eb94
  - path: plugins/atlas/skills/atlas/SKILL.md
    blob: 69a3df6cef90014ee2b8ea6cde4bc3c1f3862e13
references_modules: [plugins-agents-agents-chunk-1, plugins-agents-agents-chunk-2, plugins-atlas-references]
generator: cartographer/1
baseline: 0ce4ca44c3cc0b4a95d86862de8dc79914ffacbf
verified: true
---

# Module: plugins/atlas (misc)

## Purpose

Deterministic core of the atlas plugin: a stdlib-only Python CLI owns everything checkable
— scan, partitioning, grounding, the blob-SHA staleness ledger, the derived INDEX, lint,
locking, guarded commits — so LLM cartographers only ever write doc prose. The `/atlas`
skill routes deterministic work through the router; the SessionStart hook tells agents
how far to trust the INDEX via a staleness tier.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `atlas` | skill | `plugins/atlas/skills/atlas/SKILL.md:2` | /atlas orchestrator: status/map/update/verify/init/remove; writes no map content |
| `atlas-router.sh` | script | `plugins/atlas/bin/atlas-router.sh:2` | Routes /atlas args to atlas-cli; unknown commands get usage JSON |
| `cmd_commit` | def | `plugins/atlas/bin/atlas-cli:1186` | `commit`: stages only docs/atlas/ + --also paths; refuses mid-merge |
| `cmd_ground` | def | `plugins/atlas/bin/atlas-cli:1098` | `ground <id>`: file blobs, import lines, fan-in-ranked def candidates |
| `cmd_index_rebuild` | def | `plugins/atlas/bin/atlas-cli:1405` | `index rebuild`: INDEX.md from frontmatter; refuses past 7000 chars |
| `cmd_init` | def | `plugins/atlas/bin/atlas-cli:1245` | `init`: managed CLAUDE.md block + .atlas/ gitignore entry |
| `cmd_ledger_diff` | def | `plugins/atlas/bin/atlas-cli:748` | `ledger diff`: docs classified stale/renamed/orphaned/fingerprint-stale/ripple |
| `cmd_ledger_finalize` | def | `plugins/atlas/bin/atlas-cli:539` | `ledger finalize [--refresh-hashes]`: validates docs, stamps blobs/baseline, rewrites ledger |
| `cmd_ledger_set_verified` | def | `plugins/atlas/bin/atlas-cli:757` | `ledger set-verified <doc> true/false`: stamps the map-verifier verdict |
| `cmd_lint` | def | `plugins/atlas/bin/atlas-cli:1663` | `lint [--fast]`: checks L1-L11; ERROR = exit 1; --fast gates status integrity |
| `cmd_lock` | def | `plugins/atlas/bin/atlas-cli:809` | `lock acquire/heartbeat/release`: single-writer lock for map writes |
| `cmd_partition` | def | `plugins/atlas/bin/atlas-cli:1994` | `partition`: deterministic module split under file/byte caps |
| `cmd_remove` | def | `plugins/atlas/bin/atlas-cli:1283` | `remove`: strips the CLAUDE.md block; map files stay on disk |
| `cmd_scan` | def | `plugins/atlas/bin/atlas-cli:1795` | `scan`: git ls-files ∩ config globs, binary-sniffed; max_files ceiling |
| `cmd_status` | def | `plugins/atlas/bin/atlas-cli:1024` | `status [--for-hook]`: tier 0-3 + message; cached in .atlas/drift-cache.json |
| `main` | def | `plugins/atlas/bin/atlas-cli:2002` | argparse dispatcher; JSON-only stdout; exit 0/1/2 = ok/failed/usage |
| `SessionStart` | hook | `plugins/atlas/hooks/session-start.sh:2` | Registered in plugins/atlas/hooks/hooks.json; tier 1-3 staleness context, else silent |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `build_index_text` | def | `plugins/atlas/bin/atlas-cli:1346` | Sole producer of INDEX bytes; status and lint L10 byte-compare against it |
| `build_ledger` | def | `plugins/atlas/bin/atlas-cli:492` | Derives atlas-ledger.json (docs, path ownership, referenced_by) from frontmatter |
| `compute_diff` | def | `plugins/atlas/bin/atlas-cli:613` | Staleness engine: blob compare, renames, scope trees, ripple via references_modules |
| `compute_status` | def | `plugins/atlas/bin/atlas-cli:917` | Maps conflict markers, integrity failures, and drift onto tiers 0-3 |
| `current_blob_map` | def | `plugins/atlas/bin/atlas-cli:366` | HEAD blobs overridden by working-tree hashes of dirty paths |
| `do_partition` | def | `plugins/atlas/bin/atlas-cli:1956` | Config overrides, then recursive `decide`: dir buckets, stem clusters, greedy chunks |

## Relationships

- `plugins-atlas-misc.SKILL.md -> plugins-atlas-misc.atlas-router.sh (calls)`
- `plugins-atlas-misc.atlas-router.sh -> plugins-atlas-misc.atlas-cli (calls)`
- `plugins-atlas-misc.session-start.sh -> plugins-atlas-misc.cmd_status (calls)`
- `plugins-atlas-misc.SKILL.md -> plugins-atlas-references.mapping-protocol.md (reads)`
- `plugins-atlas-misc.SKILL.md -> plugins-atlas-references.update-protocol.md (reads)`
- `plugins-atlas-misc.SKILL.md -> plugins-atlas-references.map-format.md (reads)`
- `plugins-atlas-misc.SKILL.md -> plugins-agents-agents-chunk-1.cartographer (reads)`
- `plugins-atlas-misc.cartographer-context -> plugins-agents-agents-chunk-1.cartographer (extends)`
- `plugins-atlas-misc.map-verifier-context -> plugins-agents-agents-chunk-2.map-verifier (extends)`

## Type notes

- Doc frontmatter is canonical; the ledger JSON is derived (`plugins/atlas/bin/atlas-cli:234`).
- The map lock is an atomic mkdir with heartbeat TTL takeover (`plugins/atlas/bin/atlas-cli:818`).

## External deps

- git — hashing and repo state via plumbing subprocesses
- jq — hard dependency of the session hook (`plugins/atlas/hooks/session-start.sh:34`)
- python3 — stdlib only; no PyYAML anywhere

## Gotchas

- The map never maps itself: scan excludes `docs/atlas/**` (`plugins/atlas/bin/atlas-cli:38`).
- Only a restricted YAML subset parses; richer YAML misparses (`plugins/atlas/bin/atlas-cli:130`).
- INDEX merge conflicts: always rebuild, never hand-merge (`plugins/atlas/bin/atlas-cli:1308`).
