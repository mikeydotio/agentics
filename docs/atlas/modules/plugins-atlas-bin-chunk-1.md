---
module: "plugins/atlas/bin (chunk 1)"
summary: "atlas-cli: the deterministic backend for scan, partition, ledger diff, Structure Index, and Judgment Cache projection."
read_when: "Touching atlas-cli subcommands, the extractor, Judgment Cache, or the projector"
sources:
  - path: plugins/atlas/bin/atlas-cli
    blob: 5ead7ce0d387e144659e37674d59533c09a7d8b1
references_modules: [plugins-atlas-helpers-ts-helper, plugins-atlas-tests-chunk-1, plugins-semver-misc]
generator: cartographer/4
baseline: 50c998d53e2ed58951ac5f794afd32bfa729f658
---

# Module: plugins/atlas/bin (chunk 1)

## Purpose

atlas-cli is the entire deterministic backend the /atlas skill drives: file discovery and partitioning (scan/partition), git-backed blob-ledger staleness tracking (ledger/diffpack/status/lint), the Structure Index extractor (regex plus an optional tree-sitter helper), the content-addressed Judgment Cache (judge-plan/judgment ingest/diff/prune/verify-set), and the deterministic projector that joins structure and judgments into committed docs (project/index rebuild). If it vanished, atlas would have no deterministic operations at all — every orchestrating skill step shells out to this one script.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `GlobSet` | class | `plugins/atlas/bin/atlas-cli:3890` | Compiles glob patterns (supporting `**`) into regexes; `.matches(path)` tests a repo-relative path against all of them. |
| `add` | def | `plugins/atlas/bin/atlas-cli:3552` | Nested inside lint_map: appends one {check, severity, file, message} finding; not part of the public CLI surface. |
| `apply_overrides` | def | `plugins/atlas/bin/atlas-cli:4112` | Claims scanned files matching config `modules:` globs (first match wins); returns (claimed_partitions, remaining_entries). |
| `assign_new_files` | def | `plugins/atlas/bin/atlas-cli:728` | Deterministically proposes existing-module or new-module homes for scanned files not yet owned by any doc's sources. |
| `assign_spans` | def | `plugins/atlas/bin/atlas-cli:1670` | Mutates `defs` in place: gives each parsed definition an end_line bounded by the next same/shallower-indent definition. |
| `blob_to_worktree_diff` | def | `plugins/atlas/bin/atlas-cli:1096` | Returns a unified diff from a recorded git blob to a path's current working-tree bytes, or a fallback message if unavailable. |
| `build_index_text` | def | `plugins/atlas/bin/atlas-cli:3353` | Deterministically assembles the full INDEX.md text from validated doc frontmatter and the overview's index-facts block. |
| `build_ledger` | def | `plugins/atlas/bin/atlas-cli:566` | Builds the v2 atlas-ledger.json dict (docs/paths/referenced_by plus optional structure/judgment_keys) from validated docs. |
| `build_tree` | def | `plugins/atlas/bin/atlas-cli:4012` | Builds a `_DirNode` trie of scanned file entries keyed by path segments, for `decide` to partition top-down. |
| `call_sites_from_helper` | def | `plugins/atlas/bin/atlas-cli:1940` | Converts one tree-sitter helper file entry's `calls` into extractor call-site records resolved to their enclosing symbol. |
| `canonical_doc_text` | def | `plugins/atlas/bin/atlas-cli:359` | Normalizes a doc's frontmatter (strips finalize-managed keys) so a fresh projection and its committed form compare equal. |
| `cell` | def | `plugins/atlas/bin/atlas-cli:2853` | Inside render_module_doc: looks up a module/symbol judgment cell by kind, recording it as consumed or missing. |
| `cell` | def | `plugins/atlas/bin/atlas-cli:2945` | Inside render_overview_doc: looks up an overview judgment cell by kind, recording it as consumed or missing. |
| `check_duplicate_ownership` | def | `plugins/atlas/bin/atlas-cli:605` | Returns (path, first_doc, second_doc) triples for any non-map source path claimed by more than one module doc's sources. |
| `claude_md_block_re` | def | `plugins/atlas/bin/atlas-cli:3246` | Compiles the regex matching the atlas-managed `<!-- atlas:start -->…<!-- atlas:end -->` CLAUDE.md block. |
| `cmd_branch_ensure` | def | `plugins/atlas/bin/atlas-cli:3172` | `atlas branch ensure`: creates/switches to a deterministic `atlas/<op>-<sha>` branch, no-op if already on one. |
| `cmd_commit` | def | `plugins/atlas/bin/atlas-cli:3115` | `atlas commit`: stages and commits only `docs/atlas/` (+ `--also` paths), refusing mid-merge or when nothing changed. |
| `cmd_diffpack` | def | `plugins/atlas/bin/atlas-cli:1126` | `atlas diffpack`: writes one doc's anchored-regeneration patch file under `.atlas/diffs/` for a cartographer to read. |
| `cmd_doc_apply_renames` | def | `plugins/atlas/bin/atlas-cli:1009` | `atlas doc apply-renames`: rewrites pure-renamed source paths inside affected map docs' frontmatter and body, no LLM. |
| `cmd_doc_remove` | def | `plugins/atlas/bin/atlas-cli:1049` | `atlas doc remove`: deletes named map docs (orphaned or conflict-corrupted); validates the whole batch before touching any. |
| `cmd_extract` | def | `plugins/atlas/bin/atlas-cli:2104` | `atlas extract`: builds/reuses the Structure Index and reports symbol/edge counts, optionally filtered to one module. |
| `cmd_index_rebuild` | def | `plugins/atlas/bin/atlas-cli:3405` | `atlas index rebuild`: regenerates INDEX.md from doc frontmatter, failing if it would exceed the char budget. |
| `cmd_init` | def | `plugins/atlas/bin/atlas-cli:3252` | `atlas init`: injects/replaces the CLAUDE.md atlas block and adds the `.atlas/` gitignore entry. |
| `cmd_judge_plan` | def | `plugins/atlas/bin/atlas-cli:2360` | `atlas judge-plan`: reports the judgment cells the current structure requires vs. what's cached, grouped by module. |
| `cmd_judgment_diff` | def | `plugins/atlas/bin/atlas-cli:2450` | `atlas judgment diff`: the v2 staleness engine — reports missing/orphaned judgment keys and docs whose projection would change. |
| `cmd_judgment_ingest` | def | `plugins/atlas/bin/atlas-cli:2385` | `atlas judgment ingest`: merges a JSON array of judgment cells from stdin into judgments.json, stamping provenance/verify defaults. |
| `cmd_judgment_prune` | def | `plugins/atlas/bin/atlas-cli:2485` | `atlas judgment prune`: deletes cached judgment cells the current structure no longer requires. |
| `cmd_judgment_verify_set` | def | `plugins/atlas/bin/atlas-cli:2556` | `atlas judgment verify-set`: `--plan` lists unverified high-consequence cells; otherwise stamps verdicts from stdin by key. |
| `cmd_ledger_diff` | def | `plugins/atlas/bin/atlas-cli:960` | `atlas ledger diff`: classifies every map doc against the repo as it exists now (stale/renamed/orphaned/ripple). |
| `cmd_ledger_finalize` | def | `plugins/atlas/bin/atlas-cli:622` | `atlas ledger finalize`: validates frontmatter, optionally refreshes blob hashes, and rebuilds atlas-ledger.json. |
| `cmd_ledger_set_verified` | def | `plugins/atlas/bin/atlas-cli:969` | `atlas ledger set-verified`: stamps a doc's `verified` frontmatter flag and rebuilds the ledger. |
| `cmd_lint` | def | `plugins/atlas/bin/atlas-cli:3843` | `atlas lint`: runs `lint_map` and reports ERROR/WARN findings; exits nonzero when any ERROR is present. |
| `cmd_lock` | def | `plugins/atlas/bin/atlas-cli:1212` | `atlas lock {acquire,heartbeat,release}`: an atomic-mkdir heartbeat lock with TTL-based stale-lock takeover. |
| `cmd_migrate_v1` | def | `plugins/atlas/bin/atlas-cli:2677` | `atlas migrate-v1`: one-time re-key of committed v1 doc prose into v2 Judgment Cache cells by symbol/module match. |
| `cmd_partition` | def | `plugins/atlas/bin/atlas-cli:4174` | `atlas partition`: emits the deterministic module partition of scanned files. |
| `cmd_project` | def | `plugins/atlas/bin/atlas-cli:3067` | `atlas project`: renders and writes every committed doc from the Structure Index + Judgment Cache, reporting missing cells. |
| `cmd_remove` | def | `plugins/atlas/bin/atlas-cli:3290` | `atlas remove`: strips the atlas-managed block from CLAUDE.md, leaving `.atlas/` and `docs/atlas/` untouched. |
| `cmd_scan` | def | `plugins/atlas/bin/atlas-cli:3975` | `atlas scan`: enumerates git-listed (tracked + untracked-non-ignored) files matching config globs, minus excludes/binaries, with sizes. |
| `cmd_status` | def | `plugins/atlas/bin/atlas-cli:1445` | `atlas status`: reports the map's cached or freshly-computed staleness tier (0-3) for the SessionStart hook. |
| `cmd_verify_cache_read` | def | `plugins/atlas/bin/atlas-cli:1560` | `atlas verify-cache read`: reports whether `.atlas/verify.json` is still valid for the current repo fingerprint. |
| `cmd_verify_cache_write` | def | `plugins/atlas/bin/atlas-cli:1507` | `atlas verify-cache write`: persists `/atlas verify` findings (lint + diff + stdin verdicts) to `.atlas/verify.json`. |
| `collect_files` | def | `plugins/atlas/bin/atlas-cli:4023` | Flattens a `_DirNode` subtree into a sorted list of (path, bytes) file entries. |
| `compute_diff` | def | `plugins/atlas/bin/atlas-cli:814` | Classifies every validated map doc's sources against the current blob map — the core of ledger diff/status/lint. |
| `compute_inputs_digest` | def | `plugins/atlas/bin/atlas-cli:1845` | sha256 over (path, blob) for every mappable file now — the Structure Index cache-validity fingerprint. |
| `compute_judgment_keys` | def | `plugins/atlas/bin/atlas-cli:2277` | Deterministically enumerates every judgment cell (module/symbol/overview/edge.semantic) the current structure requires. |
| `compute_status` | def | `plugins/atlas/bin/atlas-cli:1320` | Computes the map's staleness tier (0-3) from conflict markers, integrity checks, and compute_diff's affected-doc ratio. |
| `content_hash` | def | `plugins/atlas/bin/atlas-cli:1625` | Stable `sha256:`-prefixed digest over text/bytes, distinct in format from git blob OIDs. |
| `current_blob_map` | def | `plugins/atlas/bin/atlas-cli:440` | {path: blob} for the repo as it exists now — HEAD blobs overridden by working-tree hashes for every dirty path. |
| `decide` | def | `plugins/atlas/bin/atlas-cli:4079` | Recursively partitions a `_DirNode` subtree into modules honoring caps, coalescing small dirs into `(misc)` buckets. |
| `deepest_common_dir` | def | `plugins/atlas/bin/atlas-cli:3990` | The longest shared directory prefix across a set of paths, or `''` if any path is at the repo root. |
| `detect_visibility` | def | `plugins/atlas/bin/atlas-cli:1640` | Regex-backend visibility heuristic from a declaration's leading modifiers; defaults to `public`. |
| `discover_docs` | def | `plugins/atlas/bin/atlas-cli:495` | Lists map doc ids (`modules/*.md` then `overview/*.md`) under `docs/atlas/`, sorted. |
| `do_extract` | def | `plugins/atlas/bin/atlas-cli:1963` | Builds the Structure Index fresh: symbols, edges, imports, external deps and module membership for every scanned file. |
| `do_partition` | def | `plugins/atlas/bin/atlas-cli:4136` | Runs scan + config overrides + `decide` to produce the full deterministic module partition. |
| `do_scan` | def | `plugins/atlas/bin/atlas-cli:3918` | Enumerates git-listed files matching config include/exclude globs, filtering binaries/NUL files, enforcing the file ceiling. |
| `doc_display_names` | def | `plugins/atlas/bin/atlas-cli:1313` | Sorted, comma-joined module ids for a list of affected-doc entries, capped with a '+N more' suffix. |
| `doc_module_id` | def | `plugins/atlas/bin/atlas-cli:490` | `modules/<id>.md` → `<id>` — the module id used in `references_modules` and doc lookups. |
| `drift_cache_key` | def | `plugins/atlas/bin/atlas-cli:1300` | Fingerprint of HEAD + non-`.atlas/` `git status` output — the cache key gating `status`'s recomputation. |
| `edge_semantic_key` | def | `plugins/atlas/bin/atlas-cli:2269` | Content address of an `edge.semantic` cell, keyed on the calling symbol's span_hash plus the resolved target id. |
| `emit` | def | `plugins/atlas/bin/atlas-cli:80` | Prints `data` as indented JSON to stdout — the sole output channel every subcommand uses. |
| `emit_fail` | def | `plugins/atlas/bin/atlas-cli:91` | Emits `{ok:false, error, message, **fields}` and returns exit code 1 — the CLI's uniform failure contract. |
| `emit_ok` | def | `plugins/atlas/bin/atlas-cli:84` | Emits `{ok:true, **fields}` and returns exit code 0 — the CLI's uniform success contract. |
| `enclosing_symbol` | def | `plugins/atlas/bin/atlas-cli:1743` | The innermost indexed symbol whose span contains a given line — resolves a call site's `from`. |
| `extract_call_sites_regex` | def | `plugins/atlas/bin/atlas-cli:1754` | Regex-backend call-site extraction: {from, callee, line} records with no resolution target, skipping defs and keywords. |
| `extract_index_facts` | def | `plugins/atlas/bin/atlas-cli:3329` | Verbatim bullet lines from the overview doc's `<!-- atlas:index-facts -->` block, for INDEX assembly. |
| `extract_regex` | def | `plugins/atlas/bin/atlas-cli:1683` | Language-agnostic regex structure extraction: returns (symbols, import_lines, import_targets) for one file — the floor backend. |
| `extract_section` | def | `plugins/atlas/bin/atlas-cli:2632` | Prose under a `## <anchor>` markdown heading up to the next `## `, trimmed — used by v1→v2 migration. |
| `find_conflict_markers` | def | `plugins/atlas/bin/atlas-cli:1283` | Repo-relative paths of `.md` map docs containing unresolved git conflict markers. |
| `git_branch_exists` | def | `plugins/atlas/bin/atlas-cli:3165` | True when `refs/heads/<name>` exists in the repo. |
| `git_commit_exists` | def | `plugins/atlas/bin/atlas-cli:461` | True when `sha` resolves to a commit object in the repo. |
| `git_commits_behind` | def | `plugins/atlas/bin/atlas-cli:472` | Count of commits between `baseline` and HEAD, or None if unresolvable. |
| `git_current_branch` | def | `plugins/atlas/bin/atlas-cli:3157` | Short branch name for HEAD, or None when detached. |
| `git_hash_paths` | def | `plugins/atlas/bin/atlas-cli:418` | {path: blob_oid} for working-tree bytes via `git hash-object` (batched, with a per-file fallback on partial failure). |
| `git_head` | def | `plugins/atlas/bin/atlas-cli:373` | Current HEAD commit sha, or None when the repo has no commits yet. |
| `git_is_ancestor` | def | `plugins/atlas/bin/atlas-cli:466` | True when `ancestor` is an ancestor of `descendant` per `git merge-base --is-ancestor`. |
| `git_listed_files` | def | `plugins/atlas/bin/atlas-cli:117` | Sorted, deduped tracked + untracked-but-not-ignored file paths relative to `root`. |
| `git_ls_tree_blobs` | def | `plugins/atlas/bin/atlas-cli:380` | {path: blob_oid} for every blob in HEAD's tree; empty when there is no HEAD yet. |
| `git_status_paths` | def | `plugins/atlas/bin/atlas-cli:396` | All paths `git status` reports as differing from HEAD, including untracked and the pre-rename side of renames. |
| `git_toplevel` | def | `plugins/atlas/bin/atlas-cli:109` | Absolute repo root for `project_dir`, or None when not inside a git work tree. |
| `git_tree_oid` | def | `plugins/atlas/bin/atlas-cli:454` | The tree OID for `HEAD:<treepath>`, or None if it doesn't resolve. |
| `git_with_index_retry` | def | `plugins/atlas/bin/atlas-cli:3105` | Retries a git command up to `attempts` times on `index.lock` contention from concurrent user git activity. |
| `github_slug` | def | `plugins/atlas/bin/atlas-cli:3475` | GitHub-style markdown heading → anchor slug (lowercased, punctuation stripped, spaces to hyphens). |
| `gitignored_top_dirs` | def | `plugins/atlas/bin/atlas-cli:3457` | Top-level directory names covered by `.gitignore` — used by lint L6 to exempt runtime-artifact paths. |
| `glob_to_regex` | def | `plugins/atlas/bin/atlas-cli:3865` | Translates a glob (supporting `*`, `?`, `**`, `**/`) into an anchored regex over a repo-relative path. |
| `has_nul_prefix` | def | `plugins/atlas/bin/atlas-cli:3910` | True when the file's first SNIFF_BYTES contain a NUL byte (binary sniff), or the file is unreadable. |
| `incident_edge_digest` | def | `plugins/atlas/bin/atlas-cli:1831` | Content address of a symbol's incoming *resolved* edges only — the fan-in signal symbol.load_bearing re-judges on. |
| `is_load_bearing_candidate` | def | `plugins/atlas/bin/atlas-cli:2232` | True for non-public symbols with fan_in >= 1 — the set the LLM judges for symbol.load_bearing. |
| `join_structure_and_judgments` | def | `plugins/atlas/bin/atlas-cli:3009` | Renders every committed doc (modules + overview) from the Structure Index and Judgment Cache; returns (docs, consumed, missing). |
| `judgment_key` | def | `plugins/atlas/bin/atlas-cli:2171` | `<kind>/<24-hex>` content address: a kind-prefixed sha256 digest of the kind plus its identity/trigger inputs. |
| `judgment_key_delta` | def | `plugins/atlas/bin/atlas-cli:2435` | Classifies required judgment cells against the cache into `missing` (LLM delta) and `orphaned` (prunable). |
| `judgment_keys_by_doc` | def | `plugins/atlas/bin/atlas-cli:3028` | {doc_relpath: [judgment keys it consumes]} — the per-doc dependency the v2 ledger records. |
| `judgments_path` | def | `plugins/atlas/bin/atlas-cli:2167` | Path to `docs/atlas/judgments.json`, the Judgment Cache's on-disk store. |
| `lang_of` | def | `plugins/atlas/bin/atlas-cli:1959` | Lowercased file extension of a repo-relative path, or `''` if it has none. |
| `ledger_baseline` | def | `plugins/atlas/bin/atlas-cli:3345` | The `baseline` commit sha recorded in atlas-ledger.json, or None if absent/unreadable. |
| `lint_map` | def | `plugins/atlas/bin/atlas-cli:3549` | Runs all mechanical map-integrity checks (L1-L16); returns a list of {check, severity, file, message} findings. |
| `load_config` | def | `plugins/atlas/bin/atlas-cli:255` | Parses `docs/atlas/config.yaml` (restricted YAML subset) into a dict, or `{}` if absent. |
| `load_doc` | def | `plugins/atlas/bin/atlas-cli:508` | Reads one map doc, splitting frontmatter (parsed) from body text. |
| `load_judgments` | def | `plugins/atlas/bin/atlas-cli:2330` | Reads judgments.json, or an empty v2-shaped store if absent/corrupt. |
| `load_or_build_index` | def | `plugins/atlas/bin/atlas-cli:2078` | Returns (index, cached) — reuses the on-disk Structure Index when its commit+dirty-digest still match, else rebuilds. |
| `load_validated_docs` | def | `plugins/atlas/bin/atlas-cli:544` | Returns (docs, errors) — every discovered map doc, split into passing `validate_doc` and those with frontmatter errors. |
| `lock_paths` | def | `plugins/atlas/bin/atlas-cli:1188` | (lock_dir, lock_file) paths under `.atlas/lock/` for the heartbeat lock. |
| `main` | def | `plugins/atlas/bin/atlas-cli:4182` | argparse entry point: builds every subcommand parser and dispatches `args.command` to its `cmd_*` handler. |
| `majority` | def | `plugins/atlas/bin/atlas-cli:761` | Inside assign_new_files: the most-frequent (ties broken lexicographically) key in a {key: count} dict. |
| `make_partition` | def | `plugins/atlas/bin/atlas-cli:4031` | Builds one partition-proposal dict {id_seed, label, strategy, file_entries} shared by decide/split_bucket/apply_overrides. |
| `match_symbol` | def | `plugins/atlas/bin/atlas-cli:2706` | Inside cmd_migrate_v1: resolves a v1 doc's symbol/location cell to a current Structure Index symbol by name+file, or name-only. |
| `matches` | def | `plugins/atlas/bin/atlas-cli:3898` | `GlobSet.matches(path)`: true if any compiled pattern matches the full path or (for slash-free patterns) its basename. |
| `module_edge_kinds` | def | `plugins/atlas/bin/atlas-cli:2190` | Sorted set of structural edge kinds with either endpoint among a module's member symbol ids. |
| `module_external_deps` | def | `plugins/atlas/bin/atlas-cli:2795` | Sorted import targets for a module's files that resolve outside the repo (not a top-level repo directory). |
| `module_symbols` | def | `plugins/atlas/bin/atlas-cli:2179` | {module_id: [symbol, ...]} — Structure Index symbols grouped by their file's owning module. |
| `normalize_doc_id` | def | `plugins/atlas/bin/atlas-cli:999` | A valid `modules/<x>.md` or `overview/<x>.md` doc id after normalizing `doc_id`, or None if malformed. |
| `normalize_signature` | def | `plugins/atlas/bin/atlas-cli:1636` | Collapses a declaration line's whitespace runs to single spaces, for a stable signature_hash. |
| `overview_digest` | def | `plugins/atlas/bin/atlas-cli:2215` | Global digest of every module's public-surface digest plus the set of resolved cross-module edges. |
| `parse_import_target` | def | `plugins/atlas/bin/atlas-cli:1655` | Best-effort dependency token following an import-ish keyword on one line, or None. |
| `parse_index_facts` | def | `plugins/atlas/bin/atlas-cli:2668` | v1-migration helper: bullet lines from a body's `<!-- atlas:index-facts -->` block. |
| `parse_list` | def | `plugins/atlas/bin/atlas-cli:222` | Restricted-YAML-subset list parser: consecutive `- ` items at one indent, scalars or nested maps. |
| `parse_map` | def | `plugins/atlas/bin/atlas-cli:210` | Restricted-YAML-subset map parser: consecutive `key:` lines at one indent, scalar or nested block values. |
| `parse_relationship_edges` | def | `plugins/atlas/bin/atlas-cli:3532` | (lhs, rhs, verb) tuples parsed from a doc body's `## Relationships` section, for lint L13's verb-grammar check. |
| `parse_scalar` | def | `plugins/atlas/bin/atlas-cli:166` | Restricted-YAML-subset scalar parser: strips comments, decodes quoted strings/bools/null/ints/inline lists. |
| `parse_symbol_tables` | def | `plugins/atlas/bin/atlas-cli:3494` | (symbol, location) rows from a doc body's Public API / Load-bearing internals markdown tables. |
| `parse_table_rows` | def | `plugins/atlas/bin/atlas-cli:2645` | v1-migration helper: (symbol, location, contract-or-why) rows from a named markdown table section. |
| `parse_value_block` | def | `plugins/atlas/bin/atlas-cli:201` | Restricted-YAML-subset dispatcher: routes a nested block to `parse_list` or `parse_map` by its first line's shape. |
| `parse_yaml_subset` | def | `plugins/atlas/bin/atlas-cli:190` | Parses the restricted YAML subset (top-level scalars, one nesting level, list-of-maps) into a dict. |
| `partition_caps` | def | `plugins/atlas/bin/atlas-cli:264` | Merges config `partition:` overrides (min_files/max_files/max_bytes) onto DEFAULT_PARTITION. |
| `path_to_module` | def | `plugins/atlas/bin/atlas-cli:1854` | {path: module_id} reverse index built from a Structure Index's `modules` mapping. |
| `place` | def | `plugins/atlas/bin/atlas-cli:2696` | Inside cmd_migrate_v1: stores one migrated judgment cell under its computed key unless the value is empty/unmatched. |
| `plan_judgment_misses` | def | `plugins/atlas/bin/atlas-cli:2350` | Splits required judgment cells into cached (present) and not-yet-judged (missing) — the JUDGE delta. |
| `public_surface_digest` | def | `plugins/atlas/bin/atlas-cli:2199` | Order-independent digest of a module's public capability set (names/kinds/visibility + edge kinds) — the re-judge trigger. |
| `read_lock` | def | `plugins/atlas/bin/atlas-cli:1193` | Reads the lock file's JSON, or None if absent/corrupt. |
| `read_repo_file` | def | `plugins/atlas/bin/atlas-cli:3615` | Cached read of a repo file's text for lint's L7 fallback grep; None (and cached) on read failure. |
| `read_text` | def | `plugins/atlas/bin/atlas-cli:1600` | Reads a file's full text (utf-8, replacing errors), or None on any OSError. |
| `render_module_doc` | def | `plugins/atlas/bin/atlas-cli:2848` | Renders one module doc's full text from the Structure Index + Judgment Cache; returns (text, consumed_keys, missing_keys). |
| `render_overview_doc` | def | `plugins/atlas/bin/atlas-cli:2938` | Renders overview/ARCHITECTURE.md from module-granularity structure + overview judgment cells; returns (text, consumed, missing). |
| `render_relationships` | def | `plugins/atlas/bin/atlas-cli:2811` | Renders a module's resolved cross-module edges as `## Relationships` lines, substituting a judged semantic verb when present. |
| `resolve_edges` | def | `plugins/atlas/bin/atlas-cli:1776` | Resolves raw call sites to structural `calls` edges with a resolved/ambiguous/unresolved confidence tier, deduped and sorted. |
| `resolved_cross_module_edges` | def | `plugins/atlas/bin/atlas-cli:2239` | The resolved structural edges crossing a module boundary — the exhaustive set edge.semantic cells anchor to. |
| `run_git` | def | `plugins/atlas/bin/atlas-cli:100` | Runs a git command in `cwd`; returns (exit_code, stdout_bytes) with stderr suppressed. |
| `run_git_capture` | def | `plugins/atlas/bin/atlas-cli:3099` | Runs a git command capturing both stdout and stderr; returns (exit_code, stdout, stderr). |
| `run_ts_helper` | def | `plugins/atlas/bin/atlas-cli:1889` | Invokes the tree-sitter helper binary for a batch of paths; returns {relpath: {symbols, calls}} or None on any failure. |
| `sanitize_id` | def | `plugins/atlas/bin/atlas-cli:3983` | Collapses a path/label seed into a safe module id ([A-Za-z0-9._-]+), no repeated separators. |
| `serialize_frontmatter` | def | `plugins/atlas/bin/atlas-cli:312` | Serializes a frontmatter dict back to canonical `---`-delimited YAML-subset text with fixed key order. |
| `split_bucket` | def | `plugins/atlas/bin/atlas-cli:4038` | Splits an over-cap partition bucket into stem-name clusters first, then size/count-bounded greedy chunks. |
| `split_frontmatter` | def | `plugins/atlas/bin/atlas-cli:288` | Splits a doc's text into (frontmatter_text, body_text), or (None, text) when no `---` block is present. |
| `status_thresholds` | def | `plugins/atlas/bin/atlas-cli:1273` | Merges config `thresholds:` overrides onto DEFAULT_THRESHOLDS for the staleness-tier calculation. |
| `strip_finalize_fm` | def | `plugins/atlas/bin/atlas-cli:346` | Deep-copies a frontmatter dict and drops finalize-managed keys (baseline/verified/source blobs/scope shas). |
| `strip_inline_comment` | def | `plugins/atlas/bin/atlas-cli:135` | Strips a trailing ` # comment` from a YAML-subset value, respecting quotes and `[...]` so a legitimate `#` survives. |
| `structure_index_path` | def | `plugins/atlas/bin/atlas-cli:1632` | Path to `.atlas/structure/index.json`, the cached Structure Index. |
| `structure_ledger_block` | def | `plugins/atlas/bin/atlas-cli:3044` | The ledger's `structure` fingerprint block: a whole-index content digest plus per-path per-symbol hashes. |
| `symbol_location` | def | `plugins/atlas/bin/atlas-cli:2791` | `<file>:<start_line>` for a Structure Index symbol — the location string rendered in doc tables. |
| `symbols_from_helper` | def | `plugins/atlas/bin/atlas-cli:1911` | Converts one tree-sitter helper file entry's symbols into Structure Index symbol records with file-computed span hashes. |
| `table_cell` | def | `plugins/atlas/bin/atlas-cli:3325` | Sanitizes text for a markdown table cell: pipes and newlines replaced/collapsed. |
| `ts_helper_path` | def | `plugins/atlas/bin/atlas-cli:1881` | Resolves the tree-sitter helper binary via $ATLAS_TS_HELPER or atlas-ts-helper/tree-sitter on PATH, or None. |
| `validate_doc` | def | `plugins/atlas/bin/atlas-cli:517` | Returns a list of frontmatter validation error strings for one loaded doc (empty list means valid). |
| `verify_cache_path` | def | `plugins/atlas/bin/atlas-cli:1503` | Path to `.atlas/verify.json`, the persisted `/atlas verify` findings cache. |
| `verify_targets` | def | `plugins/atlas/bin/atlas-cli:2515` | The in-scope, not-yet-verified high-consequence judgment cells the map-verifier should sample. |
| `write_doc` | def | `plugins/atlas/bin/atlas-cli:560` | Serializes and writes one doc's frontmatter+body back to its file on disk. |
| `write_judgments` | def | `plugins/atlas/bin/atlas-cli:2343` | Writes the Judgment Cache dict to judgments.json, canonical (sorted, indented) JSON. |
| `write_lock` | def | `plugins/atlas/bin/atlas-cli:1201` | Writes the lock file's JSON (holder, acquired_at, heartbeat_at) for the current instant. |
| `write_structure_index` | def | `plugins/atlas/bin/atlas-cli:2071` | Writes the Structure Index dict to `.atlas/structure/index.json`, canonical JSON. |
| `yaml_scalar` | def | `plugins/atlas/bin/atlas-cli:299` | Serializes one Python value to a YAML-subset scalar (bare token or JSON-quoted string). |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

- `plugins-atlas-bin-chunk-1.apply_overrides -> plugins-semver-misc.get (calls)`
- `plugins-atlas-bin-chunk-1.assign_new_files -> plugins-semver-misc.get (calls)`
- `plugins-atlas-bin-chunk-1.blob_to_worktree_diff -> plugins-semver-misc.write (calls)`
- `plugins-atlas-bin-chunk-1.build_index_text -> plugins-semver-misc.get (calls)`
- `plugins-atlas-bin-chunk-1.build_ledger -> plugins-semver-misc.get (calls)`
- `plugins-atlas-bin-chunk-1.call_sites_from_helper -> plugins-semver-misc.get (calls)`
- `plugins-atlas-bin-chunk-1.cell -> plugins-semver-misc.get (calls)`
- `plugins-atlas-bin-chunk-1.cell -> plugins-semver-misc.set (calls)`
- `plugins-atlas-bin-chunk-1.check_duplicate_ownership -> plugins-semver-misc.get (calls)`
- `plugins-atlas-bin-chunk-1.cmd_diffpack -> plugins-semver-misc.get (calls)`
- `plugins-atlas-bin-chunk-1.cmd_diffpack -> plugins-semver-misc.write (calls)`
- `plugins-atlas-bin-chunk-1.cmd_doc_apply_renames -> plugins-semver-misc.get (calls)`
- `plugins-atlas-bin-chunk-1.cmd_doc_remove -> plugins-semver-misc.get (calls)`
- `plugins-atlas-bin-chunk-1.cmd_extract -> plugins-semver-misc.get (calls)`
- `plugins-atlas-bin-chunk-1.cmd_index_rebuild -> plugins-semver-misc.write (calls)`
- `plugins-atlas-bin-chunk-1.cmd_init -> plugins-semver-misc.write (calls)`
- `plugins-atlas-bin-chunk-1.cmd_judge_plan -> plugins-semver-misc.get (calls)`
- `plugins-atlas-bin-chunk-1.cmd_judgment_ingest -> plugins-semver-misc.get (calls)`
- `plugins-atlas-bin-chunk-1.cmd_judgment_prune -> plugins-semver-misc.get (calls)`
- `plugins-atlas-bin-chunk-1.cmd_judgment_verify_set -> plugins-semver-misc.get (calls)`
- `plugins-atlas-bin-chunk-1.cmd_ledger_finalize -> plugins-semver-misc.get (calls)`
- `plugins-atlas-bin-chunk-1.cmd_ledger_finalize -> plugins-semver-misc.set (calls)`
- `plugins-atlas-bin-chunk-1.cmd_ledger_finalize -> plugins-semver-misc.write (calls)`
- `plugins-atlas-bin-chunk-1.cmd_ledger_set_verified -> plugins-semver-misc.write (calls)`
- `plugins-atlas-bin-chunk-1.cmd_lock -> plugins-semver-misc.get (calls)`
- `plugins-atlas-bin-chunk-1.cmd_project -> plugins-semver-misc.set (calls)`
- `plugins-atlas-bin-chunk-1.cmd_project -> plugins-semver-misc.write (calls)`
- `plugins-atlas-bin-chunk-1.cmd_remove -> plugins-semver-misc.write (calls)`
- `plugins-atlas-bin-chunk-1.cmd_status -> plugins-semver-misc.get (calls)`
- `plugins-atlas-bin-chunk-1.cmd_status -> plugins-semver-misc.write (calls)`
- `plugins-atlas-bin-chunk-1.cmd_verify_cache_read -> plugins-semver-misc.get (calls)`
- `plugins-atlas-bin-chunk-1.cmd_verify_cache_write -> plugins-semver-misc.write (calls)`
- `plugins-atlas-bin-chunk-1.compute_diff -> plugins-semver-misc.get (calls)`
- `plugins-atlas-bin-chunk-1.compute_diff -> plugins-semver-misc.set (calls)`
- `plugins-atlas-bin-chunk-1.compute_inputs_digest -> plugins-semver-misc.get (calls)`
- `plugins-atlas-bin-chunk-1.compute_judgment_keys -> plugins-semver-misc.set (calls)`
- `plugins-atlas-bin-chunk-1.compute_status -> plugins-semver-misc.get (calls)`
- `plugins-atlas-bin-chunk-1.do_extract -> plugins-semver-misc.get (calls)`
- `plugins-atlas-bin-chunk-1.do_extract -> plugins-semver-misc.set (calls)`
- `plugins-atlas-bin-chunk-1.do_partition -> plugins-semver-misc.set (calls)`
- `plugins-atlas-bin-chunk-1.do_scan -> plugins-semver-misc.get (calls)`
- `plugins-atlas-bin-chunk-1.extract_regex -> plugins-semver-misc.set (calls)`
- `plugins-atlas-bin-chunk-1.git_listed_files -> plugins-semver-misc.Config (calls)`
- `plugins-atlas-bin-chunk-1.git_status_paths -> plugins-semver-misc.set (calls)`
- `plugins-atlas-bin-chunk-1.incident_edge_digest -> plugins-semver-misc.get (calls)`
- `plugins-atlas-bin-chunk-1.is_load_bearing_candidate -> plugins-semver-misc.get (calls)`
- `plugins-atlas-bin-chunk-1.join_structure_and_judgments -> plugins-semver-misc.get (calls)`
- `plugins-atlas-bin-chunk-1.judgment_key_delta -> plugins-semver-misc.get (calls)`
- `plugins-atlas-bin-chunk-1.judgment_key_delta -> plugins-semver-misc.set (calls)`
- `plugins-atlas-bin-chunk-1.judgment_keys_by_doc -> plugins-semver-misc.get (calls)`
- `plugins-atlas-bin-chunk-1.judgment_keys_by_doc -> plugins-semver-misc.set (calls)`
- `plugins-atlas-bin-chunk-1.ledger_baseline -> plugins-semver-misc.get (calls)`
- `plugins-atlas-bin-chunk-1.load_judgments -> plugins-semver-misc.get (calls)`
- `plugins-atlas-bin-chunk-1.load_or_build_index -> plugins-semver-misc.get (calls)`
- `plugins-atlas-bin-chunk-1.main -> plugins-atlas-tests-chunk-1.docs (calls)`
- `plugins-atlas-bin-chunk-1.majority -> plugins-semver-misc.get (calls)`
- `plugins-atlas-bin-chunk-1.match_symbol -> plugins-semver-misc.get (calls)`
- `plugins-atlas-bin-chunk-1.module_edge_kinds -> plugins-semver-misc.get (calls)`
- `plugins-atlas-bin-chunk-1.module_edge_kinds -> plugins-semver-misc.set (calls)`
- `plugins-atlas-bin-chunk-1.module_external_deps -> plugins-semver-misc.get (calls)`

## Type notes

All output flows through emit/emit_ok/emit_fail (plugins/atlas/bin/atlas-cli:80,84,91) — every subcommand's sole channel to stdout, so no cmd_* function prints directly. The process is stateless between invocations; its only persistent state is on-disk JSON under `.atlas/` (structure index, judgments, verify cache, lock) and the committed `docs/atlas/` doc tree — there is no in-process object graph carried across calls. The heartbeat lock (cmd_lock, plugins/atlas/bin/atlas-cli:1212) is the one concurrency primitive: an atomic `os.mkdir` claims ownership and write_lock (plugins/atlas/bin/atlas-cli:1201) stamps heartbeat_at so a stale holder's TTL can be judged from any other process. GlobSet and _DirNode (plugins/atlas/bin/atlas-cli:3890,4004) are the only classes — both immutable-after-construction value holders, not participants in any object lifecycle.

## External deps

- argparse — imported
- hashlib — imported
- json — imported
- of — imported
- os — imported
- re — imported
- shutil — imported
- subprocess — imported
- sys — imported
- time — imported

## Gotchas

Frontmatter quoting is asymmetric: parse_scalar decodes double-quoted values via json.loads to round-trip escapes, but single-quoted values are returned raw byte-for-byte — the code admits this corrupts non-ASCII frontmatter a little more on every write (plugins/atlas/bin/atlas-cli:171-180). cmd_ledger_finalize only advances a doc's `baseline` when its frontmatter snapshot actually changed, so a --refresh-hashes re-run with no real content change leaves `baseline` untouched (plugins/atlas/bin/atlas-cli:679-684). cmd_lock's stale-lock takeover falls back to the lock directory's mtime when lock.json is missing or torn, so a crashed acquire still ages out correctly (plugins/atlas/bin/atlas-cli:1229-1235).
