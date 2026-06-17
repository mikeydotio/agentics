---
module: plugins/atlas/tests (chunk 1)
summary: Bash test harness for atlas-cli — fixture helpers, assertion primitives, and subcommand test suites
read_when: Changing atlas-cli or hook behavior, or writing/debugging atlas plugin tests
sources:
  - path: plugins/atlas/tests/helpers/setup.sh
  - path: plugins/atlas/tests/run-tests.sh
  - path: plugins/atlas/tests/test-branch.sh
  - path: plugins/atlas/tests/test-commit.sh
  - path: plugins/atlas/tests/test-config.sh
  - path: plugins/atlas/tests/test-diffpack.sh
  - path: plugins/atlas/tests/test-doc.sh
  - path: plugins/atlas/tests/test-edge-cases.sh
  - path: plugins/atlas/tests/test-ground.sh
  - path: plugins/atlas/tests/test-hook.sh
  - path: plugins/atlas/tests/test-index.sh
  - path: plugins/atlas/tests/test-init.sh
  - path: plugins/atlas/tests/test-ledger.sh
  - path: plugins/atlas/tests/test-lint.sh
  - path: plugins/atlas/tests/test-lock.sh
references_modules: [plugins-atlas-chunk-2]
generator: cartographer/2
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
