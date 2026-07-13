---
module: "plugins/atlas/bin (chunk 1)"
summary: "Deterministic Python CLI implementing atlas v2's structure extraction, judgment cache, ledger, and markdown projector."
read_when: "Touching atlas-cli extraction, cache, or projector"
sources:
  - path: plugins/atlas/bin/atlas-cli
    blob: 3da1639b285c31b022b8c287941539ace3e1708b
references_modules: [plugins-semver-bin-chunk-1]
generator: cartographer/4
baseline: 7387d3614aaae8d5a5bc156cf01c251d22b1dd45
---

# Module: plugins/atlas/bin (chunk 1)

## Purpose

atlas-cli is the deterministic backbone of atlas v2: one Python script that scans/partitions the repo, extracts structure (regex or an optional tree-sitter helper) into a JSON index, and drives a content-addressed Judgment Cache (judgments.json) whose keys hash a cell's identity plus only the structural input that should trigger re-judgment (plugins/atlas/bin/atlas-cli:2261) — so unchanged code reuses cached LLM prose and body-only edits cost nothing. Its projector (render_module_doc/render_overview_doc, plugins/atlas/bin/atlas-cli:2973) assembles every committed doc purely from structure plus cached cells, so a no-change rebuild calls no model. If it vanished, atlas would lose its extract/cache/project pipeline and fall back to full LLM re-authoring of every module doc on every update.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `GlobSet` | class | `plugins/atlas/bin/atlas-cli:4022` | Compiles glob patterns (supporting `**`) into regexes; `.matches(path)` tests a repo-relative path against all of them. |
| `add` | def | `plugins/atlas/bin/atlas-cli:3684` | Nested inside lint_map: appends one {check, severity, file, message} finding; not part of the public CLI surface. |
| `apply_overrides` | def | `plugins/atlas/bin/atlas-cli:4244` | Claims scanned files matching config `modules:` globs (first match wins); returns (claimed_partitions, remaining_entries). |
| `assign_new_files` | def | `plugins/atlas/bin/atlas-cli:735` | Deterministically proposes existing-module or new-module homes for scanned files not yet owned by any doc's sources. |
| `assign_spans` | def | `plugins/atlas/bin/atlas-cli:1749` | Mutates `defs` in place: gives each parsed definition an end_line bounded by the next same/shallower-indent definition. |
| `blob_to_worktree_diff` | def | `plugins/atlas/bin/atlas-cli:1112` | Returns a unified diff from a recorded git blob to a path's current working-tree bytes, or a fallback message if unavailable. |
| `build_index_text` | def | `plugins/atlas/bin/atlas-cli:3483` | Deterministically assembles the full INDEX.md text from validated doc frontmatter and the overview's index-facts block. |
| `build_ledger` | def | `plugins/atlas/bin/atlas-cli:559` | Builds the v2 atlas-ledger.json dict (docs/paths/referenced_by plus optional structure/judgment_keys) from validated docs. |
| `build_tree` | def | `plugins/atlas/bin/atlas-cli:4144` | Builds a `_DirNode` trie of scanned file entries keyed by path segments, for `decide` to partition top-down. |
| `call_sites_from_helper` | def | `plugins/atlas/bin/atlas-cli:2065` | Converts one tree-sitter helper file entry's `calls` into extractor call-site records resolved to their enclosing symbol. |
| `canonical_doc_text` | def | `plugins/atlas/bin/atlas-cli:359` | Normalizes a doc's frontmatter (strips finalize-managed keys) so a fresh projection and its committed form compare equal. |
| `cell` | def | `plugins/atlas/bin/atlas-cli:2978` | Inside render_module_doc: looks up a module/symbol judgment cell by kind, recording it as consumed or missing. |
| `cell` | def | `plugins/atlas/bin/atlas-cli:3070` | Inside render_overview_doc: looks up an overview judgment cell by kind, recording it as consumed or missing. |
| `check_duplicate_ownership` | def | `plugins/atlas/bin/atlas-cli:598` | Returns (path, first_doc, second_doc) triples for any non-map source path claimed by more than one module doc's sources. |
| `claude_md_block_re` | def | `plugins/atlas/bin/atlas-cli:3376` | Compiles the regex matching the atlas-managed `<!-- atlas:start -->…<!-- atlas:end -->` CLAUDE.md block. |
| `cmd_branch_ensure` | def | `plugins/atlas/bin/atlas-cli:3297` | `atlas branch ensure`: creates/switches to a deterministic `atlas/<op>-<sha>` branch, no-op if already on one. |
| `cmd_commit` | def | `plugins/atlas/bin/atlas-cli:3240` | `atlas commit`: stages and commits only `docs/atlas/` (+ `--also` paths), refusing mid-merge or when nothing changed. |
| `cmd_covers` | def | `plugins/atlas/bin/atlas-cli:1525` | Reports each queried path's mapped doc/module and ledger freshness in one ok result array; pure read, no LLM or git-history walk. |
| `cmd_diffpack` | def | `plugins/atlas/bin/atlas-cli:1142` | `atlas diffpack`: writes one doc's anchored-regeneration patch file under `.atlas/diffs/` for a cartographer to read. |
| `cmd_doc_apply_renames` | def | `plugins/atlas/bin/atlas-cli:1025` | `atlas doc apply-renames`: rewrites pure-renamed source paths inside affected map docs' frontmatter and body, no LLM. |
| `cmd_doc_remove` | def | `plugins/atlas/bin/atlas-cli:1065` | `atlas doc remove`: deletes named map docs (orphaned or conflict-corrupted); validates the whole batch before touching any. |
| `cmd_extract` | def | `plugins/atlas/bin/atlas-cli:2229` | `atlas extract`: builds/reuses the Structure Index and reports symbol/edge counts, optionally filtered to one module. |
| `cmd_index_rebuild` | def | `plugins/atlas/bin/atlas-cli:3537` | `atlas index rebuild`: regenerates INDEX.md from doc frontmatter, failing if it would exceed the char budget. |
| `cmd_init` | def | `plugins/atlas/bin/atlas-cli:3382` | `atlas init`: injects/replaces the CLAUDE.md atlas block and adds the `.atlas/` gitignore entry. |
| `cmd_judge_plan` | def | `plugins/atlas/bin/atlas-cli:2485` | `atlas judge-plan`: reports the judgment cells the current structure requires vs. what's cached, grouped by module. |
| `cmd_judgment_diff` | def | `plugins/atlas/bin/atlas-cli:2575` | `atlas judgment diff`: the v2 staleness engine — reports missing/orphaned judgment keys and docs whose projection would change. |
| `cmd_judgment_ingest` | def | `plugins/atlas/bin/atlas-cli:2510` | `atlas judgment ingest`: merges a JSON array of judgment cells from stdin into judgments.json, stamping provenance/verify defaults. |
| `cmd_judgment_prune` | def | `plugins/atlas/bin/atlas-cli:2610` | `atlas judgment prune`: deletes cached judgment cells the current structure no longer requires. |
| `cmd_judgment_verify_set` | def | `plugins/atlas/bin/atlas-cli:2681` | `atlas judgment verify-set`: `--plan` lists unverified high-consequence cells; otherwise stamps verdicts from stdin by key. |
| `cmd_ledger_diff` | def | `plugins/atlas/bin/atlas-cli:976` | `atlas ledger diff`: classifies every map doc against the repo as it exists now (stale/renamed/orphaned/ripple). |
| `cmd_ledger_finalize` | def | `plugins/atlas/bin/atlas-cli:615` | `atlas ledger finalize`: validates frontmatter, optionally refreshes blob hashes, and rebuilds atlas-ledger.json. |
| `cmd_ledger_set_verified` | def | `plugins/atlas/bin/atlas-cli:985` | `atlas ledger set-verified`: stamps a doc's `verified` frontmatter flag and rebuilds the ledger. |
| `cmd_lint` | def | `plugins/atlas/bin/atlas-cli:3975` | `atlas lint`: runs `lint_map` and reports ERROR/WARN findings; exits nonzero when any ERROR is present. |
| `cmd_lock` | def | `plugins/atlas/bin/atlas-cli:1228` | `atlas lock {acquire,heartbeat,release}`: an atomic-mkdir heartbeat lock with TTL-based stale-lock takeover. |
| `cmd_migrate_v1` | def | `plugins/atlas/bin/atlas-cli:2802` | `atlas migrate-v1`: one-time re-key of committed v1 doc prose into v2 Judgment Cache cells by symbol/module match. |
| `cmd_partition` | def | `plugins/atlas/bin/atlas-cli:4306` | `atlas partition`: emits the deterministic module partition of scanned files. |
| `cmd_project` | def | `plugins/atlas/bin/atlas-cli:3192` | `atlas project`: renders and writes every committed doc from the Structure Index + Judgment Cache, reporting missing cells. |
| `cmd_remove` | def | `plugins/atlas/bin/atlas-cli:3420` | `atlas remove`: strips the atlas-managed block from CLAUDE.md, leaving `.atlas/` and `docs/atlas/` untouched. |
| `cmd_scan` | def | `plugins/atlas/bin/atlas-cli:4107` | `atlas scan`: enumerates git-listed (tracked + untracked-non-ignored) files matching config globs, minus excludes/binaries, with sizes. |
| `cmd_status` | def | `plugins/atlas/bin/atlas-cli:1461` | `atlas status`: reports the map's cached or freshly-computed staleness tier (0-3) for the SessionStart hook. |
| `cmd_verify_cache_read` | def | `plugins/atlas/bin/atlas-cli:1639` | `atlas verify-cache read`: reports whether `.atlas/verify.json` is still valid for the current repo fingerprint. |
| `cmd_verify_cache_write` | def | `plugins/atlas/bin/atlas-cli:1586` | `atlas verify-cache write`: persists `/atlas verify` findings (lint + diff + stdin verdicts) to `.atlas/verify.json`. |
| `collect_files` | def | `plugins/atlas/bin/atlas-cli:4155` | Flattens a `_DirNode` subtree into a sorted list of (path, bytes) file entries. |
| `compute_diff` | def | `plugins/atlas/bin/atlas-cli:821` | Classifies every validated map doc's sources against the current blob map — the core of ledger diff/status/lint. |
| `compute_inputs_digest` | def | `plugins/atlas/bin/atlas-cli:1957` | sha256 over (path, blob) for every mappable file now — the Structure Index cache-validity fingerprint. |
| `compute_judgment_keys` | def | `plugins/atlas/bin/atlas-cli:2402` | Deterministically enumerates every judgment cell (module/symbol/overview/edge.semantic) the current structure requires. |
| `compute_status` | def | `plugins/atlas/bin/atlas-cli:1336` | Computes the map's staleness tier (0-3) from conflict markers, integrity checks, and compute_diff's affected-doc ratio. |
| `content_hash` | def | `plugins/atlas/bin/atlas-cli:1704` | Stable `sha256:`-prefixed digest over text/bytes, distinct in format from git blob OIDs. |
| `current_blob_map` | def | `plugins/atlas/bin/atlas-cli:440` | {path: blob} for the repo as it exists now — HEAD blobs overridden by working-tree hashes for every dirty path. |
| `decide` | def | `plugins/atlas/bin/atlas-cli:4211` | Recursively partitions a `_DirNode` subtree into modules honoring caps, coalescing small dirs into `(misc)` buckets. |
| `deepest_common_dir` | def | `plugins/atlas/bin/atlas-cli:4122` | The longest shared directory prefix across a set of paths, or `''` if any path is at the repo root. |
| `detect_visibility` | def | `plugins/atlas/bin/atlas-cli:1719` | Regex-backend visibility heuristic from a declaration's leading modifiers; defaults to `public`. |
| `discover_docs` | def | `plugins/atlas/bin/atlas-cli:488` | Lists map doc ids (`modules/*.md` then `overview/*.md`) under `docs/atlas/`, sorted. |
| `do_extract` | def | `plugins/atlas/bin/atlas-cli:2088` | Builds the Structure Index fresh: symbols, edges, imports, external deps and module membership for every scanned file. |
| `do_partition` | def | `plugins/atlas/bin/atlas-cli:4268` | Runs scan + config overrides + `decide` to produce the full deterministic module partition. |
| `do_scan` | def | `plugins/atlas/bin/atlas-cli:4050` | Enumerates git-listed files matching config include/exclude globs, filtering binaries/NUL files, enforcing the file ceiling. |
| `doc_display_names` | def | `plugins/atlas/bin/atlas-cli:1329` | Sorted, comma-joined module ids for a list of affected-doc entries, capped with a '+N more' suffix. |
| `doc_module_id` | def | `plugins/atlas/bin/atlas-cli:483` | `modules/<id>.md` → `<id>` — the module id used in `references_modules` and doc lookups. |
| `drift_cache_key` | def | `plugins/atlas/bin/atlas-cli:1316` | Fingerprint of HEAD + non-`.atlas/` `git status` output — the cache key gating `status`'s recomputation. |
| `edge_semantic_key` | def | `plugins/atlas/bin/atlas-cli:2394` | Content address of an `edge.semantic` cell, keyed on the calling symbol's span_hash plus the resolved target id. |
| `emit` | def | `plugins/atlas/bin/atlas-cli:80` | Prints `data` as indented JSON to stdout — the sole output channel every subcommand uses. |
| `emit_fail` | def | `plugins/atlas/bin/atlas-cli:91` | Emits `{ok:false, error, message, **fields}` and returns exit code 1 — the CLI's uniform failure contract. |
| `emit_ok` | def | `plugins/atlas/bin/atlas-cli:84` | Emits `{ok:true, **fields}` and returns exit code 0 — the CLI's uniform success contract. |
| `enclosing_symbol` | def | `plugins/atlas/bin/atlas-cli:1822` | The innermost indexed symbol whose span contains a given line — resolves a call site's `from`. |
| `extract_call_sites_regex` | def | `plugins/atlas/bin/atlas-cli:1833` | Regex-backend call-site extraction: {from, callee, line} records with no resolution target, skipping defs and keywords. |
| `extract_index_facts` | def | `plugins/atlas/bin/atlas-cli:3459` | Verbatim bullet lines from the overview doc's `<!-- atlas:index-facts -->` block, for INDEX assembly. |
| `extract_regex` | def | `plugins/atlas/bin/atlas-cli:1762` | Language-agnostic regex structure extraction: returns (symbols, import_lines, import_targets) for one file — the floor backend. |
| `extract_section` | def | `plugins/atlas/bin/atlas-cli:2757` | Prose under a `## <anchor>` markdown heading up to the next `## `, trimmed — used by v1→v2 migration. |
| `find_conflict_markers` | def | `plugins/atlas/bin/atlas-cli:1299` | Repo-relative paths of `.md` map docs containing unresolved git conflict markers. |
| `git_branch_exists` | def | `plugins/atlas/bin/atlas-cli:3290` | True when `refs/heads/<name>` exists in the repo. |
| `git_commit_exists` | def | `plugins/atlas/bin/atlas-cli:454` | True when `sha` resolves to a commit object in the repo. |
| `git_commits_behind` | def | `plugins/atlas/bin/atlas-cli:465` | Count of commits between `baseline` and HEAD, or None if unresolvable. |
| `git_current_branch` | def | `plugins/atlas/bin/atlas-cli:3282` | Short branch name for HEAD, or None when detached. |
| `git_hash_paths` | def | `plugins/atlas/bin/atlas-cli:418` | {path: blob_oid} for working-tree bytes via `git hash-object` (batched, with a per-file fallback on partial failure). |
| `git_head` | def | `plugins/atlas/bin/atlas-cli:373` | Current HEAD commit sha, or None when the repo has no commits yet. |
| `git_is_ancestor` | def | `plugins/atlas/bin/atlas-cli:459` | True when `ancestor` is an ancestor of `descendant` per `git merge-base --is-ancestor`. |
| `git_listed_files` | def | `plugins/atlas/bin/atlas-cli:117` | Sorted, deduped tracked + untracked-but-not-ignored file paths relative to `root`. |
| `git_ls_tree_blobs` | def | `plugins/atlas/bin/atlas-cli:380` | {path: blob_oid} for every blob in HEAD's tree; empty when there is no HEAD yet. |
| `git_status_paths` | def | `plugins/atlas/bin/atlas-cli:396` | All paths `git status` reports as differing from HEAD, including untracked and the pre-rename side of renames. |
| `git_toplevel` | def | `plugins/atlas/bin/atlas-cli:109` | Absolute repo root for `project_dir`, or None when not inside a git work tree. |
| `git_with_index_retry` | def | `plugins/atlas/bin/atlas-cli:3230` | Retries a git command up to `attempts` times on `index.lock` contention from concurrent user git activity. |
| `github_slug` | def | `plugins/atlas/bin/atlas-cli:3607` | GitHub-style markdown heading → anchor slug (lowercased, punctuation stripped, spaces to hyphens). |
| `gitignored_top_dirs` | def | `plugins/atlas/bin/atlas-cli:3589` | Top-level directory names covered by `.gitignore` — used by lint L6 to exempt runtime-artifact paths. |
| `glob_to_regex` | def | `plugins/atlas/bin/atlas-cli:3997` | Translates a glob (supporting `*`, `?`, `**`, `**/`) into an anchored regex over a repo-relative path. |
| `has_nul_prefix` | def | `plugins/atlas/bin/atlas-cli:4042` | True when the file's first SNIFF_BYTES contain a NUL byte (binary sniff), or the file is unreadable. |
| `incident_edge_digest` | def | `plugins/atlas/bin/atlas-cli:1932` | Content address of a symbol's incoming *resolved* edges only — the fan-in signal symbol.load_bearing re-judges on. |
| `is_load_bearing_candidate` | def | `plugins/atlas/bin/atlas-cli:2357` | True for non-public symbols with fan_in >= 1 — the set the LLM judges for symbol.load_bearing. |
| `join_structure_and_judgments` | def | `plugins/atlas/bin/atlas-cli:3134` | Renders every committed doc (modules + overview) from the Structure Index and Judgment Cache; returns (docs, consumed, missing). |
| `judgment_key` | def | `plugins/atlas/bin/atlas-cli:2296` | `<kind>/<24-hex>` content address: a kind-prefixed sha256 digest of the kind plus its identity/trigger inputs. |
| `judgment_key_delta` | def | `plugins/atlas/bin/atlas-cli:2560` | Classifies required judgment cells against the cache into `missing` (LLM delta) and `orphaned` (prunable). |
| `judgment_keys_by_doc` | def | `plugins/atlas/bin/atlas-cli:3153` | {doc_relpath: [judgment keys it consumes]} — the per-doc dependency the v2 ledger records. |
| `judgments_path` | def | `plugins/atlas/bin/atlas-cli:2292` | Path to `docs/atlas/judgments.json`, the Judgment Cache's on-disk store. |
| `lang_of` | def | `plugins/atlas/bin/atlas-cli:2084` | Lowercased file extension of a repo-relative path, or `''` if it has none. |
| `ledger_baseline` | def | `plugins/atlas/bin/atlas-cli:3475` | The `baseline` commit sha recorded in atlas-ledger.json, or None if absent/unreadable. |
| `lint_map` | def | `plugins/atlas/bin/atlas-cli:3681` | Runs all mechanical map-integrity checks (L1-L16); returns a list of {check, severity, file, message} findings. |
| `load_config` | def | `plugins/atlas/bin/atlas-cli:255` | Parses `docs/atlas/config.yaml` (restricted YAML subset) into a dict, or `{}` if absent. |
| `load_doc` | def | `plugins/atlas/bin/atlas-cli:501` | Reads one map doc, splitting frontmatter (parsed) from body text. |
| `load_judgments` | def | `plugins/atlas/bin/atlas-cli:2455` | Reads judgments.json, or an empty v2-shaped store if absent/corrupt. |
| `load_ledger` | def | `plugins/atlas/bin/atlas-cli:1516` | Returns the parsed docs/atlas ledger dict, or None if missing/invalid JSON — never raises, so callers can treat None as 'unmapped'. |
| `load_or_build_index` | def | `plugins/atlas/bin/atlas-cli:2203` | Returns (index, cached) — reuses the on-disk Structure Index when its commit+dirty-digest still match, else rebuilds. |
| `load_validated_docs` | def | `plugins/atlas/bin/atlas-cli:537` | Returns (docs, errors) — every discovered map doc, split into passing `validate_doc` and those with frontmatter errors. |
| `lock_paths` | def | `plugins/atlas/bin/atlas-cli:1204` | (lock_dir, lock_file) paths under `.atlas/lock/` for the heartbeat lock. |
| `main` | def | `plugins/atlas/bin/atlas-cli:4314` | argparse entry point: builds every subcommand parser and dispatches `args.command` to its `cmd_*` handler. |
| `majority` | def | `plugins/atlas/bin/atlas-cli:768` | Inside assign_new_files: the most-frequent (ties broken lexicographically) key in a {key: count} dict. |
| `make_partition` | def | `plugins/atlas/bin/atlas-cli:4163` | Builds one partition-proposal dict {id_seed, label, strategy, file_entries} shared by decide/split_bucket/apply_overrides. |
| `match_symbol` | def | `plugins/atlas/bin/atlas-cli:2831` | Inside cmd_migrate_v1: resolves a v1 doc's symbol/location cell to a current Structure Index symbol by name+file, or name-only. |
| `matches` | def | `plugins/atlas/bin/atlas-cli:4030` | `GlobSet.matches(path)`: true if any compiled pattern matches the full path or (for slash-free patterns) its basename. |
| `module_edge_kinds` | def | `plugins/atlas/bin/atlas-cli:2315` | Sorted set of structural edge kinds with either endpoint among a module's member symbol ids. |
| `module_external_deps` | def | `plugins/atlas/bin/atlas-cli:2920` | Sorted import targets for a module's files that resolve outside the repo (not a top-level repo directory). |
| `module_symbols` | def | `plugins/atlas/bin/atlas-cli:2304` | {module_id: [symbol, ...]} — Structure Index symbols grouped by their file's owning module. |
| `normalize_doc_id` | def | `plugins/atlas/bin/atlas-cli:1015` | A valid `modules/<x>.md` or `overview/<x>.md` doc id after normalizing `doc_id`, or None if malformed. |
| `normalize_signature` | def | `plugins/atlas/bin/atlas-cli:1715` | Collapses a declaration line's whitespace runs to single spaces, for a stable signature_hash. |
| `overview_digest` | def | `plugins/atlas/bin/atlas-cli:2340` | Global digest of every module's public-surface digest plus the set of resolved cross-module edges. |
| `parse_import_target` | def | `plugins/atlas/bin/atlas-cli:1734` | Best-effort dependency token following an import-ish keyword on one line, or None. |
| `parse_index_facts` | def | `plugins/atlas/bin/atlas-cli:2793` | v1-migration helper: bullet lines from a body's `<!-- atlas:index-facts -->` block. |
| `parse_list` | def | `plugins/atlas/bin/atlas-cli:222` | Restricted-YAML-subset list parser: consecutive `- ` items at one indent, scalars or nested maps. |
| `parse_map` | def | `plugins/atlas/bin/atlas-cli:210` | Restricted-YAML-subset map parser: consecutive `key:` lines at one indent, scalar or nested block values. |
| `parse_relationship_edges` | def | `plugins/atlas/bin/atlas-cli:3664` | (lhs, rhs, verb) tuples parsed from a doc body's `## Relationships` section, for lint L13's verb-grammar check. |
| `parse_scalar` | def | `plugins/atlas/bin/atlas-cli:166` | Restricted-YAML-subset scalar parser: strips comments, decodes quoted strings/bools/null/ints/inline lists. |
| `parse_symbol_tables` | def | `plugins/atlas/bin/atlas-cli:3626` | (symbol, location) rows from a doc body's Public API / Load-bearing internals markdown tables. |
| `parse_table_rows` | def | `plugins/atlas/bin/atlas-cli:2770` | v1-migration helper: (symbol, location, contract-or-why) rows from a named markdown table section. |
| `parse_value_block` | def | `plugins/atlas/bin/atlas-cli:201` | Restricted-YAML-subset dispatcher: routes a nested block to `parse_list` or `parse_map` by its first line's shape. |
| `parse_yaml_subset` | def | `plugins/atlas/bin/atlas-cli:190` | Parses the restricted YAML subset (top-level scalars, one nesting level, list-of-maps) into a dict. |
| `partition_caps` | def | `plugins/atlas/bin/atlas-cli:264` | Merges config `partition:` overrides (min_files/max_files/max_bytes) onto DEFAULT_PARTITION. |
| `path_to_module` | def | `plugins/atlas/bin/atlas-cli:1979` | {path: module_id} reverse index built from a Structure Index's `modules` mapping. |
| `paths_digest` | def | `plugins/atlas/bin/atlas-cli:1948` | sha256 digest of sorted (path,blob) pairs; empty set hashes to one stable constant, so convergence-to-empty never thrashes cache keys. |
| `place` | def | `plugins/atlas/bin/atlas-cli:2821` | Inside cmd_migrate_v1: stores one migrated judgment cell under its computed key unless the value is empty/unmatched. |
| `plan_judgment_misses` | def | `plugins/atlas/bin/atlas-cli:2475` | Splits required judgment cells into cached (present) and not-yet-judged (missing) — the JUDGE delta. |
| `public_surface_digest` | def | `plugins/atlas/bin/atlas-cli:2324` | Order-independent digest of a module's public capability set (names/kinds/visibility + edge kinds) — the re-judge trigger. |
| `read_lock` | def | `plugins/atlas/bin/atlas-cli:1209` | Reads the lock file's JSON, or None if absent/corrupt. |
| `read_repo_file` | def | `plugins/atlas/bin/atlas-cli:3747` | Cached read of a repo file's text for lint's L7 fallback grep; None (and cached) on read failure. |
| `read_text` | def | `plugins/atlas/bin/atlas-cli:1679` | Reads a file's full text (utf-8, replacing errors), or None on any OSError. |
| `render_module_doc` | def | `plugins/atlas/bin/atlas-cli:2973` | Renders one module doc's full text from the Structure Index + Judgment Cache; returns (text, consumed_keys, missing_keys). |
| `render_overview_doc` | def | `plugins/atlas/bin/atlas-cli:3063` | Renders overview/ARCHITECTURE.md from module-granularity structure + overview judgment cells; returns (text, consumed, missing). |
| `render_relationships` | def | `plugins/atlas/bin/atlas-cli:2936` | Renders a module's resolved cross-module edges as `## Relationships` lines, substituting a judged semantic verb when present. |
| `resolve_edges` | def | `plugins/atlas/bin/atlas-cli:1870` | Resolves raw call sites to structural `calls` edges with a resolved/ambiguous/unresolved confidence tier, deduped and sorted. |
| `resolved_cross_module_edges` | def | `plugins/atlas/bin/atlas-cli:2364` | The resolved structural edges crossing a module boundary — the exhaustive set edge.semantic cells anchor to. |
| `run_git` | def | `plugins/atlas/bin/atlas-cli:100` | Runs a git command in `cwd`; returns (exit_code, stdout_bytes) with stderr suppressed. |
| `run_git_capture` | def | `plugins/atlas/bin/atlas-cli:3224` | Runs a git command capturing both stdout and stderr; returns (exit_code, stdout, stderr). |
| `run_ts_helper` | def | `plugins/atlas/bin/atlas-cli:2014` | Invokes the tree-sitter helper binary for a batch of paths; returns {relpath: {symbols, calls}} or None on any failure. |
| `sanitize_id` | def | `plugins/atlas/bin/atlas-cli:4115` | Collapses a path/label seed into a safe module id ([A-Za-z0-9._-]+), no repeated separators. |
| `scope_digest` | def | `plugins/atlas/bin/atlas-cli:1964` | Content-addresses a scope's mappable files (docs/atlas/**, .atlas/** already excluded), so the map's own output never self-invalidates it. |
| `serialize_frontmatter` | def | `plugins/atlas/bin/atlas-cli:312` | Serializes a frontmatter dict back to canonical `---`-delimited YAML-subset text with fixed key order. |
| `split_bucket` | def | `plugins/atlas/bin/atlas-cli:4170` | Splits an over-cap partition bucket into stem-name clusters first, then size/count-bounded greedy chunks. |
| `split_frontmatter` | def | `plugins/atlas/bin/atlas-cli:288` | Splits a doc's text into (frontmatter_text, body_text), or (None, text) when no `---` block is present. |
| `status_thresholds` | def | `plugins/atlas/bin/atlas-cli:1289` | Merges config `thresholds:` overrides onto DEFAULT_THRESHOLDS for the staleness-tier calculation. |
| `strip_finalize_fm` | def | `plugins/atlas/bin/atlas-cli:346` | Deep-copies a frontmatter dict and drops finalize-managed keys (baseline/verified/source blobs/scope shas). |
| `strip_inline_comment` | def | `plugins/atlas/bin/atlas-cli:135` | Strips a trailing ` # comment` from a YAML-subset value, respecting quotes and `[...]` so a legitimate `#` survives. |
| `structure_index_path` | def | `plugins/atlas/bin/atlas-cli:1711` | Path to `.atlas/structure/index.json`, the cached Structure Index. |
| `structure_ledger_block` | def | `plugins/atlas/bin/atlas-cli:3169` | The ledger's `structure` fingerprint block: a whole-index content digest plus per-path per-symbol hashes. |
| `symbol_location` | def | `plugins/atlas/bin/atlas-cli:2916` | `<file>:<start_line>` for a Structure Index symbol — the location string rendered in doc tables. |
| `symbols_from_helper` | def | `plugins/atlas/bin/atlas-cli:2036` | Converts one tree-sitter helper file entry's symbols into Structure Index symbol records with file-computed span hashes. |
| `table_cell` | def | `plugins/atlas/bin/atlas-cli:3455` | Sanitizes text for a markdown table cell: pipes and newlines replaced/collapsed. |
| `ts_helper_path` | def | `plugins/atlas/bin/atlas-cli:2006` | Resolves the tree-sitter helper binary via $ATLAS_TS_HELPER or atlas-ts-helper/tree-sitter on PATH, or None. |
| `validate_doc` | def | `plugins/atlas/bin/atlas-cli:510` | Returns a list of frontmatter validation error strings for one loaded doc (empty list means valid). |
| `verify_cache_path` | def | `plugins/atlas/bin/atlas-cli:1582` | Path to `.atlas/verify.json`, the persisted `/atlas verify` findings cache. |
| `verify_targets` | def | `plugins/atlas/bin/atlas-cli:2640` | The in-scope, not-yet-verified high-consequence judgment cells the map-verifier should sample. |
| `write_doc` | def | `plugins/atlas/bin/atlas-cli:553` | Serializes and writes one doc's frontmatter+body back to its file on disk. |
| `write_judgments` | def | `plugins/atlas/bin/atlas-cli:2468` | Writes the Judgment Cache dict to judgments.json, canonical (sorted, indented) JSON. |
| `write_lock` | def | `plugins/atlas/bin/atlas-cli:1217` | Writes the lock file's JSON (holder, acquired_at, heartbeat_at) for the current instant. |
| `write_structure_index` | def | `plugins/atlas/bin/atlas-cli:2196` | Writes the Structure Index dict to `.atlas/structure/index.json`, canonical JSON. |
| `yaml_scalar` | def | `plugins/atlas/bin/atlas-cli:299` | Serializes one Python value to a YAML-subset scalar (bare token or JSON-quoted string). |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

- `plugins-atlas-bin-chunk-1.git_listed_files -> plugins-semver-bin-chunk-1.Config (calls)`

## Type notes

Judgment Cache keys (plugins/atlas/bin/atlas-cli:2261) are `<kind>/<24-hex>` hashes of the cell's identity anchor (symbol/module id) plus only the structural input that should trigger re-judgment — e.g. symbol.contract keys on signature_hash but never body text, so body-only edits are free and reuse cached prose. compute_judgment_keys/_key_index (plugins/atlas/bin/atlas-cli:2906) is the single source of truth mapping (kind, module, symbol) -> key for both judge-plan and the projector. VERIFY_KINDS (plugins/atlas/bin/atlas-cli:2285) restricts map-verifier sampling to the falsifiable, act-to-your-peril prose kinds (symbol.contract, symbol.load_bearing, module.gotchas, edge.semantic); cmd_judgment_verify_set (plugins/atlas/bin/atlas-cli:2681) only stamps pass/fail verdicts onto existing keys and never originates a cell's value. cmd_judgment_prune (plugins/atlas/bin/atlas-cli:2610) is the sole cache-shrink path — idempotent and git-reversible, dropping only orphaned keys. Partitioning (build_tree/decide/split_bucket, plugins/atlas/bin/atlas-cli:4144) is a deterministic recursive tree walk: directories under the file/byte caps become one partition, undersized directories coalesce into a '(misc)' bucket, and oversized buckets split by filename stem before falling back to greedy byte-capped chunking.

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

- scope_digest deliberately excludes docs/atlas/** and .atlas/** from a scope's content address (plugins/atlas/bin/atlas-cli:1964-1976) — a raw tree OID previously let the map's own committed output self-invalidate the ARCHITECTURE overview (issue #79); it now hashes only do_scan's mappable-file set.
- incident_edge_digest hashes only *resolved* incoming call edges, dropping ambiguous ones on purpose (plugins/atlas/bin/atlas-cli:1932-1945) — common names like `run`/`get` defined in many files would otherwise thrash a symbol's load-bearing digest on every unrelated same-named definition.
