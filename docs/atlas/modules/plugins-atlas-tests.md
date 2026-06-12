---
module: plugins/atlas/tests
summary: "Bash regression suite pinning atlas-cli JSON contracts and the session hook via throwaway /tmp git repos"
read_when: "Changing atlas-cli or hook behavior, or writing/debugging atlas plugin tests"
sources:
  - path: plugins/atlas/tests/helpers/setup.sh
    blob: 218e426a7e05f0286a2b5b422897b3466e17f3af
  - path: plugins/atlas/tests/run-tests.sh
    blob: febae8f36c0646a382a834d4bb81fac24f7ba8fb
  - path: plugins/atlas/tests/test-commit.sh
    blob: 7d66eeedfb471de9a12b2720e7bbcf998e9900c7
  - path: plugins/atlas/tests/test-ground.sh
    blob: a6bddad7cdecaf512472a53f199baaa07f2b3a31
  - path: plugins/atlas/tests/test-hook.sh
    blob: 5545302a4317791ae60c63e45833dc34b822636f
  - path: plugins/atlas/tests/test-index.sh
    blob: 2874a1bcef0889b9e18d91f93c60b3737404f665
  - path: plugins/atlas/tests/test-init.sh
    blob: 1f85b244ea31d8dae57fbb880aad83337d1938f1
  - path: plugins/atlas/tests/test-ledger.sh
    blob: 1b2fa083305e51fd580c12a0dab67425a55cb875
  - path: plugins/atlas/tests/test-lint.sh
    blob: 68f14c678b9cd861c77f034ab4d807275508cc0b
  - path: plugins/atlas/tests/test-lock.sh
    blob: 9b6c39e83aab4b0db326b19e51dd4111553d463b
  - path: plugins/atlas/tests/test-partition.sh
    blob: 4671fae665fdc132eabd409016d982e10c51501e
  - path: plugins/atlas/tests/test-scan.sh
    blob: 64fdfb8349fc9b8fc74817948c47ac664b123cae
  - path: plugins/atlas/tests/test-status.sh
    blob: fdde9f2ee86018efefcd6e1794a0a90d04cf1be0
references_modules: [plugins-atlas-misc]
generator: cartographer/1
baseline: b9203a6997fdbc2248086c1aa9ee6f62b1e025b6
verified: true
---

# Module: plugins/atlas/tests

## Purpose

Black-box regression suite for the atlas plugin: every test builds a throwaway git repo under
/tmp, runs `atlas-cli` or the SessionStart hook as a subprocess, and asserts on the JSON
envelope and exit code. `plugins/atlas/tests/helpers/setup.sh` is the de-facto testing API
every per-subcommand file consumes; `plugins/atlas/tests/run-tests.sh` discovers and isolates
tests. If the suite vanished, drift in envelopes, error codes, and tiers would ship silently.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `CLI` | variable | `plugins/atlas/tests/helpers/setup.sh:6` | Path to plugins/atlas/bin/atlas-cli; run via python3 |
| `PLUGIN_ROOT` | variable | `plugins/atlas/tests/helpers/setup.sh:5` | Plugin root; anchors the CLI and hook under test |
| `assert_eq` | function | `plugins/atlas/tests/helpers/setup.sh:206` | Returns 1 + FAIL diff on mismatch |
| `assert_exit_code` | function | `plugins/atlas/tests/helpers/setup.sh:218` | assert_eq for exit codes; pair with EXIT_CODE |
| `assert_file_exists` | function | `plugins/atlas/tests/helpers/setup.sh:270` | Fails unless the path is a regular file |
| `assert_json_contains` | function | `plugins/atlas/tests/helpers/setup.sh:245` | jq array filter must contain the value |
| `assert_json_field` | function | `plugins/atlas/tests/helpers/setup.sh:229` | jq -r filter output must equal expected |
| `assert_json_not_contains` | function | `plugins/atlas/tests/helpers/setup.sh:258` | Inverse of assert_json_contains |
| `backdate_lock` | function | `plugins/atlas/tests/helpers/setup.sh:190` | Rewinds .atlas/lock/lock.json heartbeat N seconds back |
| `cleanup_fixture_repo` | function | `plugins/atlas/tests/helpers/setup.sh:67` | rm -rf guarded to /tmp/atlas-tests-* paths only |
| `commit_all` | function | `plugins/atlas/tests/helpers/setup.sh:43` | git add -A plus quiet commit |
| `create_fixture_repo` | function | `plugins/atlas/tests/helpers/setup.sh:12` | Echoes a fresh git repo under /tmp/atlas-tests-XXXXXX, gpgsign off |
| `run-tests.sh` | script | `plugins/atlas/tests/run-tests.sh:1` | Entry point; arg substring-filters test files; exit status = failure count |
| `run_atlas` | function | `plugins/atlas/tests/helpers/setup.sh:58` | Runs the CLI inside the repo; sets OUTPUT/EXIT_CODE; drops stderr |
| `seed_file` | function | `plugins/atlas/tests/helpers/setup.sh:27` | Deterministic ~N-byte text file (default 100); never binary-sniffed |
| `write_config` | function | `plugins/atlas/tests/helpers/setup.sh:50` | stdin to docs/atlas/config.yaml inside the fixture |
| `write_full_module_doc` | function | `plugins/atlas/tests/helpers/setup.sh:143` | Full canonical-skeleton doc passing lint L1; claims the symbol at line 1 of its source |
| `write_module_doc` | function | `plugins/atlas/tests/helpers/setup.sh:78` | Minimal blobless doc (ledger finalize stamps hashes); ATLAS_TEST_SUMMARY overrides summary |
| `write_overview_doc` | function | `plugins/atlas/tests/helpers/setup.sh:109` | Overview doc: doc-path sources, tree scope, index-facts block |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `run_test_file` | function | `plugins/atlas/tests/run-tests.sh:26` | Sources a test file, finds test_* via declare -F, runs each in a set -e subshell |
| `OUTPUT` | variable | `plugins/atlas/tests/helpers/setup.sh:62` | Stdout global from run_atlas/run_hook; twin EXIT_CODE alongside; globals force sequential runs |
| `run_hook` | function | `plugins/atlas/tests/test-hook.sh:27` | Pipes a SessionStart cwd event into the hook with CLAUDE_PROJECT_DIR scrubbed |
| `_status_fixture` | function | `plugins/atlas/tests/test-status.sh:6` | Five-module map puts stale-doc ratios exactly on tier boundaries (20/40/60%) |

## Relationships

- `plugins-atlas-tests.run_atlas -> plugins-atlas-misc.atlas-cli (calls)`
- `plugins-atlas-tests.run_hook -> plugins-atlas-misc.session-start.sh (calls)`
- `plugins-atlas-tests.run-tests.sh -> plugins-atlas-tests.setup.sh (reads)`

## Type notes

- A `test_*` function passes iff it returns 0; assertions return 1 — callers chain `|| return 1`.
- Per-file `_*_fixture` builders echo a ready repo path; the underscore prefix escapes discovery.
- `_ledger_fixture` sets references_modules for ripple runs (plugins/atlas/tests/test-ledger.sh:7).

## External deps

- jq — all JSON assertions; runner prerequisite (plugins/atlas/tests/run-tests.sh:79)
- git — fixture repos, rename/orphan/shallow-clone cases (plugins/atlas/tests/run-tests.sh:84)
- python3 — runs atlas-cli and inline heredocs (plugins/atlas/tests/helpers/setup.sh:33)

## Gotchas

- `run_atlas` drops stderr — rerun by hand to debug (plugins/atlas/tests/helpers/setup.sh:62).
- Fixtures use /tmp, not $TMPDIR — Spotlight stalls runs (plugins/atlas/tests/helpers/setup.sh:10).
- Racing subshells must `set +e` to be allowed to lose (plugins/atlas/tests/test-lock.sh:99).
- Only `test_*` funcs unset between files; helpers leak (plugins/atlas/tests/run-tests.sh:66).
