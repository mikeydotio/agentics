---
module: plugins/atlas/tests
summary: "Bash regression suite pinning atlas-cli JSON contracts and the session hook via throwaway /tmp git repos"
read_when: "Changing atlas-cli or hook behavior, or writing/debugging atlas plugin tests"
sources:
  - path: plugins/atlas/tests/helpers/setup.sh
    blob: 43e023c777e86119e2569cb7062e6d8a83da8afc
  - path: plugins/atlas/tests/run-tests.sh
    blob: febae8f36c0646a382a834d4bb81fac24f7ba8fb
  - path: plugins/atlas/tests/test-commit.sh
    blob: e5409959bdfdd6ce369bef3f40d7ff0374b5ae22
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
    blob: abe078f0fd272c428a003fad154a15c54fea57d6
  - path: plugins/atlas/tests/test-lint.sh
    blob: dfea42963e14496622975a31988ff8420d5e5656
  - path: plugins/atlas/tests/test-lock.sh
    blob: 9b6c39e83aab4b0db326b19e51dd4111553d463b
  - path: plugins/atlas/tests/test-partition.sh
    blob: 4671fae665fdc132eabd409016d982e10c51501e
  - path: plugins/atlas/tests/test-scan.sh
    blob: 64fdfb8349fc9b8fc74817948c47ac664b123cae
  - path: plugins/atlas/tests/test-status.sh
    blob: fdde9f2ee86018efefcd6e1794a0a90d04cf1be0
  - path: plugins/atlas/tests/test-update-flow.sh
    blob: 7c4643183c99a2ff6ce20afa169e0e7fdd6baed7
references_modules: [plugins-atlas-misc]
generator: cartographer/1
baseline: dc00e9cd63fa7cd062a89006bbf54e8ca17cff21
verified: true
---

# Module: plugins/atlas/tests

## Purpose

Black-box regression suite for the atlas plugin: every test builds a throwaway git repo under
/tmp, runs `atlas-cli` or the SessionStart hook as a subprocess, and asserts on the JSON
envelope and exit code. `plugins/atlas/tests/helpers/setup.sh` is the de-facto testing API
every test file consumes; `plugins/atlas/tests/run-tests.sh` discovers and isolates
tests. If the suite vanished, drift in envelopes, error codes, and tiers would ship silently.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `CLI` | variable | `plugins/atlas/tests/helpers/setup.sh:6` | Path to plugins/atlas/bin/atlas-cli; run via python3 |
| `PLUGIN_ROOT` | variable | `plugins/atlas/tests/helpers/setup.sh:5` | Plugin root; anchors the CLI and hook under test |
| `assert_eq` | function | `plugins/atlas/tests/helpers/setup.sh:219` | Returns 1 + FAIL diff on mismatch |
| `assert_exit_code` | function | `plugins/atlas/tests/helpers/setup.sh:231` | assert_eq for exit codes; pair with EXIT_CODE |
| `assert_file_exists` | function | `plugins/atlas/tests/helpers/setup.sh:283` | Fails unless the path is a regular file |
| `assert_json_contains` | function | `plugins/atlas/tests/helpers/setup.sh:258` | jq array filter must contain the value |
| `assert_json_field` | function | `plugins/atlas/tests/helpers/setup.sh:242` | jq -r filter output must equal expected |
| `assert_json_not_contains` | function | `plugins/atlas/tests/helpers/setup.sh:271` | Inverse of assert_json_contains |
| `backdate_lock` | function | `plugins/atlas/tests/helpers/setup.sh:203` | Rewinds .atlas/lock/lock.json heartbeat N seconds back |
| `cleanup_fixture_repo` | function | `plugins/atlas/tests/helpers/setup.sh:67` | rm -rf guarded to /tmp/atlas-tests-* paths only |
| `commit_all` | function | `plugins/atlas/tests/helpers/setup.sh:43` | git add -A plus quiet commit |
| `create_fixture_repo` | function | `plugins/atlas/tests/helpers/setup.sh:12` | Echoes a fresh git repo under /tmp/atlas-tests-XXXXXX, gpgsign off |
| `run-tests.sh` | script | `plugins/atlas/tests/run-tests.sh:1` | Entry point; arg substring-filters test files; exit status = failure count |
| `run_atlas` | function | `plugins/atlas/tests/helpers/setup.sh:58` | Runs the CLI inside the repo; sets OUTPUT/EXIT_CODE; drops stderr |
| `seed_file` | function | `plugins/atlas/tests/helpers/setup.sh:27` | Deterministic ~N-byte text file (default 100); never binary-sniffed |
| `write_config` | function | `plugins/atlas/tests/helpers/setup.sh:50` | stdin to docs/atlas/config.yaml inside the fixture |
| `write_full_module_doc` | function | `plugins/atlas/tests/helpers/setup.sh:146` | Full canonical-skeleton doc passing lint L1; claims the symbol at line 1 of its source; optional refs-csv + extra sources |
| `write_module_doc` | function | `plugins/atlas/tests/helpers/setup.sh:78` | Minimal blobless doc (ledger finalize stamps hashes); ATLAS_TEST_SUMMARY overrides summary |
| `write_overview_doc` | function | `plugins/atlas/tests/helpers/setup.sh:109` | Overview doc: doc-path sources, tree scope, index-facts block |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `run_test_file` | function | `plugins/atlas/tests/run-tests.sh:26` | Sources a test file, finds test_* via declare -F, runs each in a set -e subshell |
| `OUTPUT` | variable | `plugins/atlas/tests/helpers/setup.sh:62` | Stdout global from run_atlas/run_hook; twin EXIT_CODE alongside; globals force sequential runs |
| `run_hook` | function | `plugins/atlas/tests/test-hook.sh:27` | Pipes a SessionStart cwd event into the hook with CLAUDE_PROJECT_DIR scrubbed |
| `_status_fixture` | function | `plugins/atlas/tests/test-status.sh:6` | Five-module map puts stale-doc ratios exactly on tier boundaries (20/40/60%) |
| `_update_fixture` | function | `plugins/atlas/tests/test-update-flow.sh:13` | Full-coverage three-module + overview map; src-core is the must-stay-byte-identical control |

## Relationships

- `plugins-atlas-tests.run_atlas -> plugins-atlas-misc.atlas-cli (calls)`
- `plugins-atlas-tests.run_hook -> plugins-atlas-misc.session-start.sh (calls)`
- `plugins-atlas-tests.run-tests.sh -> plugins-atlas-tests.setup.sh (reads)`

## Type notes

- A `test_*` function passes iff it returns 0; assertions return 1 — callers chain `|| return 1`.
- Per-file `_*_fixture` builders echo a ready repo path; the underscore prefix escapes discovery.
- `_ledger_fixture` sets references_modules for ripple runs (plugins/atlas/tests/test-ledger.sh:7).
- `_doc_hash` pins byte-identity via git hash-object (plugins/atlas/tests/test-update-flow.sh:37).
- Edge-case sweep skips angles already pinned elsewhere (plugins/atlas/tests/test-edge-cases.sh:2).

## External deps

- jq — all JSON assertions; runner prerequisite (plugins/atlas/tests/run-tests.sh:79)
- git — fixture repos, rename/orphan/shallow-clone cases (plugins/atlas/tests/run-tests.sh:84)
- python3 — runs atlas-cli and inline heredocs (plugins/atlas/tests/helpers/setup.sh:33)

## Gotchas

- `run_atlas` drops stderr — rerun by hand to debug (plugins/atlas/tests/helpers/setup.sh:62).
- Fixtures use /tmp, not $TMPDIR — Spotlight stalls runs (plugins/atlas/tests/helpers/setup.sh:10).
- Racing subshells must `set +e` to be allowed to lose (plugins/atlas/tests/test-lock.sh:99).
- Only `test_*` funcs unset between files; helpers leak (plugins/atlas/tests/run-tests.sh:66).
- `seed_file` ends without a newline; appends need \n (plugins/atlas/tests/test-diffpack.sh:22).
