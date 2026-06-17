---
module: "plugins/atlas/tests (chunk 2)"
summary: "Scenario test files for partition, scan, status, update-flow, repair, and verify-cache"
read_when: "Changing atlas-cli or hook behavior, or writing/debugging atlas plugin tests"
sources:
  - path: plugins/atlas/tests/test-partition.sh
    blob: 4671fae665fdc132eabd409016d982e10c51501e
  - path: plugins/atlas/tests/test-repair.sh
    blob: 4650cd406baa0f22472e1d9f5ffc972f752b6c67
  - path: plugins/atlas/tests/test-scan.sh
    blob: 64fdfb8349fc9b8fc74817948c47ac664b123cae
  - path: plugins/atlas/tests/test-status.sh
    blob: fdde9f2ee86018efefcd6e1794a0a90d04cf1be0
  - path: plugins/atlas/tests/test-update-flow.sh
    blob: 7c4643183c99a2ff6ce20afa169e0e7fdd6baed7
  - path: plugins/atlas/tests/test-verify-cache.sh
    blob: 75505fe992ce5ec73dff0eb3c070eca5d0a0510b
references_modules: [plugins-atlas-chunk-2]
generator: cartographer/2
baseline: b4cedefaba8df96ee167877bf2ee9c3143ef0b08
---

# Module: plugins/atlas/tests (chunk 2)

## Purpose

Six scenario test files that pin the CLI contracts for the core atlas data pipeline: file
enumeration (scan), module partitioning strategies and caps, status tier thresholds, the
end-to-end incremental update protocol, the repair flow's ledger mechanics, and the
verify-cache round-trip. Cartographer output is simulated by fixture helpers; the CLI layer
is exercised exactly as the skill sequences it. If these tests vanish, drift in JSON shapes
and protocol ordering would ship silently.

## Public API

There is no exported symbol surface; each file contains only `test_*` functions discovered
and run by `run-tests.sh` from chunk-1. The meaningful public contracts are the fixture
builders private to each file.

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `test_partition_single_module_small_repo` | function | `plugins/atlas/tests/test-partition.sh:8` | Asserts dir strategy, module_count, and id for a 5-file flat repo |
| `test_partition_per_directory` | function | `plugins/atlas/tests/test-partition.sh:24` | Three dirs → three sorted module ids |
| `test_partition_coalesce_small_siblings` | function | `plugins/atlas/tests/test-partition.sh:41` | Dirs with one file are coalesced into a -misc module |
| `test_partition_flat_dir_stems` | function | `plugins/atlas/tests/test-partition.sh:66` | Filename-prefix stems produce stem strategy ids; leftovers chunk |
| `test_partition_byte_cap_splits` | function | `plugins/atlas/tests/test-partition.sh:91` | Two 70KB files exceed max_bytes=120000 and split to two chunks |
| `test_partition_override_wins` | function | `plugins/atlas/tests/test-partition.sh:106` | config.yaml module override claims files; remainder forms one module |
| `test_partition_deterministic` | function | `plugins/atlas/tests/test-partition.sh:148` | Two consecutive runs produce byte-identical output |
| `test_partition_unassigned_invariant` | function | `plugins/atlas/tests/test-partition.sh:175` | sum(module.files) equals scan total; .unassigned is empty |
| `test_scan_lists_tracked_sorted` | function | `plugins/atlas/tests/test-scan.sh:4` | Sorted .files[], total_files, ok:true |
| `test_scan_respects_gitignore` | function | `plugins/atlas/tests/test-scan.sh:36` | Gitignored files excluded; .gitignore itself included |
| `test_scan_default_excludes` | function | `plugins/atlas/tests/test-scan.sh:53` | lockfiles, images, minified files never reach scan |
| `test_scan_excludes_atlas_dirs` | function | `plugins/atlas/tests/test-scan.sh:88` | docs/atlas/ and .atlas/ are never mapped |
| `test_scan_ceiling_exceeded` | function | `plugins/atlas/tests/test-scan.sh:141` | Exceeding max_files exits 1, error=ceiling_exceeded |
| `test_status_unmapped_repo` | function | `plugins/atlas/tests/test-status.sh:21` | No ledger → mapped:false, tier:0 |
| `test_status_t0_clean` | function | `plugins/atlas/tests/test-status.sh:35` | All blobs current → tier 0 |
| `test_status_t1_one_stale_doc` | function | `plugins/atlas/tests/test-status.sh:46` | 20% stale → tier 1; message names the module |
| `test_status_t2_quarter_stale` | function | `plugins/atlas/tests/test-status.sh:62` | 40% stale → tier 2; message recommends /atlas update |
| `test_status_t3_half_stale` | function | `plugins/atlas/tests/test-status.sh:78` | 60% stale → tier 3; message tells agents to disregard |
| `test_status_t3_conflict_markers` | function | `plugins/atlas/tests/test-status.sh:95` | Conflict markers in any doc force tier 3 |
| `test_status_second_run_cached` | function | `plugins/atlas/tests/test-status.sh:107` | Second run hits .atlas/ drift cache; cached:true |
| `test_status_cache_invalidated_by_edit` | function | `plugins/atlas/tests/test-status.sh:120` | Any worktree edit invalidates the drift cache |
| `test_status_for_hook_is_trimmed` | function | `plugins/atlas/tests/test-status.sh:135` | --for-hook shape: tier/message/mapped only; no files/stale_docs |
| `test_update_flow_edit_touches_only_affected_docs` | function | `plugins/atlas/tests/test-update-flow.sh:48` | Hash-gating: untouched module doc is byte-identical after update |
| `test_update_flow_rename_needs_no_llm` | function | `plugins/atlas/tests/test-update-flow.sh:104` | doc apply-renames rewrites body locations without an LLM |
| `test_update_flow_delete_removes_orphan_and_index_row` | function | `plugins/atlas/tests/test-update-flow.sh:140` | doc remove + ledger finalize + index rebuild clears the orphan |
| `test_update_flow_conflict_marker_quarantine` | function | `plugins/atlas/tests/test-update-flow.sh:182` | Conflict-marked doc is quarantined; sources resurface as new_files |
| `test_update_flow_corrupt_frontmatter_quarantine` | function | `plugins/atlas/tests/test-update-flow.sh:221` | Missing required key causes ledger diff to exit 1; doc remove unblocks |
| `test_update_flow_clean_map_has_zero_plan_entries` | function | `plugins/atlas/tests/test-update-flow.sh:242` | Clean map: all diff arrays empty; type guards prevent vacuous passes |
| `test_repair_branch_op_value` | function | `plugins/atlas/tests/test-repair.sh:40` | branch ensure --op repair → atlas/repair-<sha>; re-run is idempotent |
| `test_repair_except_preserves_drift_blob_and_refreshes_overview` | function | `plugins/atlas/tests/test-repair.sh:60` | --except keeps stale blob on drift doc; overview blob advances |
| `test_repair_finalize_without_except_advances_blob` | function | `plugins/atlas/tests/test-repair.sh:97` | Contrast: plain finalize silently marks drift doc current |
| `test_repair_blob_clean_lint_break_is_repair_target` | function | `plugins/atlas/tests/test-repair.sh:123` | Blob-clean + lint-failing doc (L13) is the repair domain |
| `test_repair_corrupt_frontmatter_defers` | function | `plugins/atlas/tests/test-repair.sh:173` | Corrupt frontmatter → ledger diff exits 1 with invalid_frontmatter |
| `test_verify_cache_write_then_read_valid` | function | `plugins/atlas/tests/test-verify-cache.sh:38` | Round-trip: write verdicts stdin → .atlas/verify.json; read returns valid:true |
| `test_verify_cache_invalidated_by_committed_edit` | function | `plugins/atlas/tests/test-verify-cache.sh:61` | HEAD move invalidates cache; stale_reason=fingerprint |
| `test_verify_cache_ignores_atlas_runtime_churn` | function | `plugins/atlas/tests/test-verify-cache.sh:91` | .atlas/ write activity must not invalidate the cache it lives in |
| `test_verify_cache_version_mismatch_is_invalid` | function | `plugins/atlas/tests/test-verify-cache.sh:118` | Cache version != 1 → valid:false, stale_reason=version |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `_update_fixture` | function | `plugins/atlas/tests/test-update-flow.sh:13` | Three-module+overview map; src-core is the byte-identical control; src-api references src-auth for ripple coverage |
| `_status_fixture` | function | `plugins/atlas/tests/test-status.sh:6` | Five modules sets tier percentage boundaries at 20/40/60% exactly |
| `_rep_fixture` | function | `plugins/atlas/tests/test-repair.sh:14` | Two-module finalized map; starting point for all repair invariant tests |
| `_vc_fixture` | function | `plugins/atlas/tests/test-verify-cache.sh:9` | Finalized two-module map; needed for verify-cache round-trip tests |
| `_vc_write` | function | `plugins/atlas/tests/test-verify-cache.sh:27` | Pipes verdicts via stdin to verify-cache write (run_atlas cannot pipe stdin) |
| `_rep_blob` | function | `plugins/atlas/tests/test-repair.sh:31` | Reads a source's recorded blob from atlas-ledger.json for before/after comparison |
| `_doc_hash` | function | `plugins/atlas/tests/test-update-flow.sh:37` | git hash-object snapshot used to prove byte-identity after update operations |

## Relationships

- `plugins-atlas-tests-chunk-2.test-partition.sh -> plugins-atlas-chunk-2.atlas-cli (calls)`
- `plugins-atlas-tests-chunk-2.test-scan.sh -> plugins-atlas-chunk-2.atlas-cli (calls)`
- `plugins-atlas-tests-chunk-2.test-status.sh -> plugins-atlas-chunk-2.atlas-cli (calls)`
- `plugins-atlas-tests-chunk-2.test-update-flow.sh -> plugins-atlas-chunk-2.atlas-cli (calls)`
- `plugins-atlas-tests-chunk-2.test-repair.sh -> plugins-atlas-chunk-2.atlas-cli (calls)`
- `plugins-atlas-tests-chunk-2.test-verify-cache.sh -> plugins-atlas-chunk-2.atlas-cli (calls)`

## Type notes

- `_vc_write` uses a direct `python3 "$CLI"` pipe rather than `run_atlas` because `run_atlas`
  has no stdin; all other calls go through `run_atlas` (plugins/atlas/tests/test-verify-cache.sh:31).
- Repair tests pin two distinct regimes: blob-stale docs (update's job) and blob-clean+lint-failing
  docs (repair's job); `test_repair_blob_clean_lint_break_is_repair_target` is the boundary marker
  (plugins/atlas/tests/test-repair.sh:123).
- `--except <doc>` on `ledger finalize` is the mechanism that keeps a drift doc flagged while still
  advancing the overview; the contrast test at line 97 of test-repair.sh proves why it exists.
- Status tier thresholds pinned by `_status_fixture`: T1=20%, T2=40%, T3=60% stale fraction
  (plugins/atlas/tests/test-status.sh:6).
- `_doc_hash` uses `git hash-object` (not `sha256sum`) so the hash matches git's blob registry
  (plugins/atlas/tests/test-update-flow.sh:37).
- Verify-cache fingerprint is the same drift_cache_key that `status` uses; .atlas/ churn is
  explicitly excluded from the fingerprint (plugins/atlas/tests/test-verify-cache.sh:91).
- The chunk-2 test files do not source `setup.sh` or `run-tests.sh` directly; fixture helpers
  (`create_fixture_repo`, `run_atlas`, etc.) are injected at runtime by `run-tests.sh` in
  chunk-1, which sources `helpers/setup.sh` once before executing the test functions.

## External deps

- jq — all JSON assertions throughout these test files
- git — fixture repo init, rename/delete/conflict operations, hash-object identity checks
- python3 — runs atlas-cli; inline heredoc in test-verify-cache.sh version-bump test
