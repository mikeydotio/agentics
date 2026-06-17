---
module: "plugins/atlas (chunk 2)"
summary: "atlas-cli Python binary, router shell shim, session-start hook, and SKILL.md orchestrator"
read_when: "Touching atlas-cli subcommands, /atlas orchestration, the session hook, or blob ledger"
sources:
  - path: plugins/atlas/bin/atlas-cli
    blob: 5319d85232bbf150441f26313cae23ec37fb1ab7
  - path: plugins/atlas/bin/atlas-router.sh
    blob: 7cc697bb908645e35f61243ae97f94de8a23771e
  - path: plugins/atlas/hooks/hooks.json
    blob: 41851681fe5ce7fdd0fc14b33dd4868d38398e6a
  - path: plugins/atlas/hooks/session-start.sh
    blob: 4277ada1b6f54bba1034edf015c622f6a3a3eb94
  - path: plugins/atlas/skills/atlas/SKILL.md
    blob: db3276b24a74ac636026ebf545de22482603c5ff
references_modules: [plugins-atlas-references, plugins-atlas-agent-overrides, plugins-agents-agents-chunk-1, plugins-agents-agents-chunk-2]
generator: cartographer/2
baseline: b4cedefaba8df96ee167877bf2ee9c3143ef0b08
verified: true
---

# Module: plugins/atlas (chunk 2)

## Purpose

This module is the executable core of the atlas plugin: a stdlib-only Python CLI (`atlas-cli`) that owns every deterministic map operation, a thin bash shim (`atlas-router.sh`) that maps `/atlas` arguments to CLI subcommands, and a `SKILL.md` orchestrator that routes user commands and delegates all map-writing to cartographer agents. The design principle is a hard separation of concerns — deterministic work never leaks into LLM context, and LLM agents never touch the derived `INDEX.md` or `atlas-ledger.json` directly. The `session-start.sh` hook injects staleness-tier context at session start, but only when the project has an atlas map and the tier is non-zero.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `atlas-cli` | script | `plugins/atlas/bin/atlas-cli:1` | Deterministic CLI; all output is JSON `{ok, ...}`; exit 0=success 1=fail 2=usage |
| `atlas-router.sh` | script | `plugins/atlas/bin/atlas-router.sh:1` | Bash shim routing `/atlas <cmd>` to atlas-cli subcommands |
| `session-start.sh` | script | `plugins/atlas/hooks/session-start.sh:1` | SessionStart hook; emits `additionalContext` for tier≥1, no-ops for tier 0 or unmapped |
| `hooks.json` | config | `plugins/atlas/hooks/hooks.json:1` | Registers the SessionStart hook with a 10s timeout |
| `SKILL.md` | skill | `plugins/atlas/skills/atlas/SKILL.md:1` | `/atlas` command orchestrator; hard-routes all deterministic work through the router |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `compute_diff` | def | `plugins/atlas/bin/atlas-cli:758` | Core staleness engine: classifies every doc as stale/renamed/orphaned/unchanged and drives ripple invalidation |
| `build_index_text` | def | `plugins/atlas/bin/atlas-cli:1867` | Deterministic INDEX assembly — the single source of truth for what INDEX.md must contain; used by both `index rebuild` and lint's L10 check |
| `lint_map` | def | `plugins/atlas/bin/atlas-cli:2045` | Runs all structural checks (L1–L14); `--fast` subset used by status and hooks |
| `parse_yaml_subset` | def | `plugins/atlas/bin/atlas-cli:187` | Custom YAML parser (stdlib-only constraint); handles frontmatter, config, and ledger; quote-aware inline-comment stripping added in `strip_inline_comment` |
| `decide` | def | `plugins/atlas/bin/atlas-cli:2523` | Recursive partition algorithm: fits a subtree into a single dir module or recurses and coalesces under-min groups |
| `drift_cache_key` | def | `plugins/atlas/bin/atlas-cli:1244` | Fingerprints HEAD + git status (excluding `.atlas/`) for the status drift cache; same key gates verify-cache reuse |
| `cmd_status` | def | `plugins/atlas/bin/atlas-cli:1371` | Reads or writes the drift cache keyed by `drift_cache_key`; the session-start hook calls this with `--for-hook` |
| `majority` | def | `plugins/atlas/bin/atlas-cli:705` | Picks the lexicographically-first majority owner from a counts dict; used by `assign_new_files` to route new files deterministically |

## Relationships

- `plugins-atlas-chunk-2.SKILL.md -> plugins-atlas-references.mapping-protocol.md (reads)`
- `plugins-atlas-chunk-2.SKILL.md -> plugins-atlas-references.update-protocol.md (reads)`
- `plugins-atlas-chunk-2.SKILL.md -> plugins-atlas-references.map-format.md (reads)`
- `plugins-atlas-chunk-2.SKILL.md -> plugins-agents-agents-chunk-1.cartographer.md (reads)`
- `plugins-atlas-chunk-2.SKILL.md -> plugins-atlas-agent-overrides.cartographer-context.md (reads)`
- `plugins-atlas-chunk-2.session-start.sh -> plugins-atlas-chunk-2.atlas-cli (calls)`
- `plugins-atlas-chunk-2.atlas-router.sh -> plugins-atlas-chunk-2.atlas-cli (calls)`

## Type notes

`GlobSet` (`plugins/atlas/bin/atlas-cli:2334`) compiles a list of glob patterns to regexes; bare patterns (no slash) also match basenames. It is the only filtering type; `do_scan` and `apply_overrides` both instantiate it.

`_DirNode` (`plugins/atlas/bin/atlas-cli:2448`) is a lightweight tree node used only inside `build_tree`/`decide` for partition construction; it carries no state after `do_partition` returns.

The blob-SHA ledger (`atlas-ledger.json`) is a derived artifact rebuilt by `cmd_ledger_finalize`. The ledger's `paths` map (source path → doc_id) and `referenced_by` map (module_id → [doc_ids]) drive ripple invalidation in `compute_diff`. Cartographers never write blob hashes — `ledger finalize --refresh-hashes` computes them after agent runs.

`compute_status` wraps `compute_diff` with a configurable three-tier output and caches the result under `.atlas/drift-cache.json` keyed by `drift_cache_key`. The cache is invalidated on any HEAD or worktree change, excluding `.atlas/` itself.

The SKILL.md orchestrator never reads map doc content into its own context; it only reads assignment data from `atlas-cli ground` output and passes file paths to cartographer agents via `<files_to_read>` blocks.

## External deps

- `python3` stdlib only — `argparse`, `hashlib`, `json`, `os`, `re`, `shutil`, `subprocess`, `time`
- `git` — all repo operations use subprocess calls to the system git binary
- `jq` — used in `session-start.sh` for JSON extraction and output encoding

## Gotchas

- `atlas-cli` has no third-party imports; the YAML parser is custom and supports only the restricted subset documented at `plugins/atlas/bin/atlas-cli:126`. Full YAML (anchors, multi-line scalars, etc.) is not supported.
- `cmd_commit` refuses during mid-merge (`MERGE_HEAD` present) and is pathspec-scoped to `docs/atlas/`; never call `git add -A` from the orchestrator (`plugins/atlas/skills/atlas/SKILL.md:29`).
- `blob_to_worktree_diff` writes a temp file under `.atlas/diffs/` and cleans it up; if `git cat-file` cannot materialize the old blob, it returns a human-readable fallback string instead of a diff (`plugins/atlas/bin/atlas-cli:1050`).
- The session-start hook silently exits 0 on any failure (missing `python3`, missing `jq`, CLI error) to avoid breaking session start (`plugins/atlas/hooks/session-start.sh:32`).
