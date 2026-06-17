---
module: "plugins/atlas/tests (chunk 1)"
summary: "Bash test harness for atlas-cli — fixture helpers, assertion primitives, and subcommand test suites"
read_when: "Changing atlas-cli or hook behavior, or writing/debugging atlas plugin tests"
sources:
  - path: plugins/atlas/tests/helpers/setup.sh
    blob: 67dcb11d42fa2aa4316c6d95170130c6e0169ee8
  - path: plugins/atlas/tests/run-tests.sh
    blob: febae8f36c0646a382a834d4bb81fac24f7ba8fb
  - path: plugins/atlas/tests/test-branch.sh
    blob: 2445f98bad189f0e3461ab325f2b02324d1e0e53
  - path: plugins/atlas/tests/test-commit.sh
    blob: e5409959bdfdd6ce369bef3f40d7ff0374b5ae22
  - path: plugins/atlas/tests/test-config.sh
    blob: 3e6b9d603355aaf173afd3f738637f4bb78f429d
  - path: plugins/atlas/tests/test-diffpack.sh
    blob: a3bce143e30dbdef734d31c870c6ebbf696d6ced
  - path: plugins/atlas/tests/test-doc.sh
    blob: a8fb82305896d7e1549bd0e213205fb5357c7012
  - path: plugins/atlas/tests/test-edge-cases.sh
    blob: 70a071fe0b9a69631fc40ce7a103cb03670d4cc9
  - path: plugins/atlas/tests/test-ground.sh
    blob: ad33b9b1e3d65b5dc128a68c9579572be600db30
  - path: plugins/atlas/tests/test-hook.sh
    blob: 5545302a4317791ae60c63e45833dc34b822636f
  - path: plugins/atlas/tests/test-index.sh
    blob: 2874a1bcef0889b9e18d91f93c60b3737404f665
  - path: plugins/atlas/tests/test-init.sh
    blob: 1f85b244ea31d8dae57fbb880aad83337d1938f1
  - path: plugins/atlas/tests/test-ledger.sh
    blob: 64f3e8c235303750f1b3e11c73d01c90000dd0fa
  - path: plugins/atlas/tests/test-lint.sh
    blob: 5c60931acf78c01f489503de029aad0bfc0053a0
  - path: plugins/atlas/tests/test-lock.sh
    blob: 9b6c39e83aab4b0db326b19e51dd4111553d463b
references_modules: [plugins-atlas-chunk-2]
generator: cartographer/2
baseline: b4cedefaba8df96ee167877bf2ee9c3143ef0b08
verified: true
---

# Module: plugins/atlas/tests (chunk 1)

## Purpose

This module is the complete test harness for the atlas plugin — a mock-free bash
suite that exercises real atlas-cli and hook behavior in throwaway `/tmp` git
repos. It owns both the shared fixture/assertion library (`helpers/setup.sh`) and
the per-subcommand test files. Without it there is no automated verification of
atlas-cli's JSON contract, ledger semantics, lint checks, or hook behavior.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `create_fixture_repo` | function | `plugins/atlas/tests/helpers/setup.sh:12` | Creates an isolated git repo under `/tmp`; callers must `cleanup_fixture_repo` |
| `run_atlas` | function | `plugins/atlas/tests/helpers/setup.sh:58` | Invokes atlas-cli inside a repo; sets `OUTPUT` and `EXIT_CODE` for assertions |
| `run_test_file` | function | `plugins/atlas/tests/run-tests.sh:26` | Sources a `test-*.sh`, discovers `test_*` functions, runs each in a subshell |
| `write_full_module_doc` | function | `plugins/atlas/tests/helpers/setup.sh:146` | Writes a complete lint-clean module doc (full skeleton + Public API row) |
| `write_module_doc` | function | `plugins/atlas/tests/helpers/setup.sh:78` | Writes a minimal module doc fixture (frontmatter + stub body) |
| `write_overview_doc` | function | `plugins/atlas/tests/helpers/setup.sh:109` | Writes an overview doc fixture with index-facts block |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `backdate_lock` | function | `plugins/atlas/tests/helpers/setup.sh:203` | Rewrites `.atlas/lock/lock.json` heartbeat to simulate stale lock expiry; needed by all lock-takeover tests |
| `cleanup_fixture_repo` | function | `plugins/atlas/tests/helpers/setup.sh:67` | Guards `/tmp` cleanup with a path-prefix check to prevent accidental deletion |
| `seed_file` | function | `plugins/atlas/tests/helpers/setup.sh:27` | Produces deterministic-content files via python3 inline script; never triggers binary sniff |

## Relationships

- `plugins-atlas-tests-chunk-1.run_atlas -> plugins-atlas-chunk-2.atlas-cli (calls)`

## Type notes

`run_atlas` sets the shell-level globals `OUTPUT` and `EXIT_CODE`; every test
function reads those globals immediately after a `run_atlas` call. All fixture
repos land under `/tmp/atlas-tests-*` (not `$TMPDIR`) to avoid macOS Spotlight
indexing stalls; `cleanup_fixture_repo` enforces the prefix before calling
`rm -rf`. The `write_config` helper reads config body from stdin, decoupling
YAML content from the helper signature.

## External deps

- `jq` — all JSON assertion helpers parse CLI output via jq filters
- `python3` — `seed_file`, `backdate_lock`, and `test-config.sh` parser tests use inline python3 scripts; no third-party packages

## Gotchas

- `run_tests.sh` unsets discovered `test_*` functions after each file to prevent cross-file contamination (`plugins/atlas/tests/run-tests.sh:65`).
- `test-hook.sh` bypasses `run_atlas` and invokes `session-start.sh` directly, setting `OUTPUT`/`EXIT_CODE` via `run_hook` (`plugins/atlas/tests/test-hook.sh:27`).
- `test-config.sh` directly `exec`s atlas-cli as a Python module (not via `run_atlas`) to unit-test the `parse_yaml_subset` function in isolation (`plugins/atlas/tests/test-config.sh:54`).
