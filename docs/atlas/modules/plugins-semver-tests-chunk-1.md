---
module: "plugins/semver/tests (chunk 1)"
summary: "Bash test suite covering semver-cli commands and the hook runner's execution, failures, and reentrancy."
read_when: "Adding or debugging tests for semver-cli or the hook runner"
sources:
  - path: plugins/semver/tests/helpers/setup.sh
    blob: 087a4482effea86118a5f541d909d1cd5bef1045
  - path: plugins/semver/tests/run-tests.sh
    blob: c3721e8619b1e0790cb584ac03bb6c235fcec187
  - path: plugins/semver/tests/test-bump-run.sh
    blob: a707de3204d97de4a55df9c40e562bb3d86c8ae2
  - path: plugins/semver/tests/test-cli.sh
    blob: f525e2512a65e5b890dc4c7d574b97d579b16d80
  - path: plugins/semver/tests/test-display-questions.sh
    blob: a47a76f5e0313f6e7947537cd3abe2a02c7abbe7
  - path: plugins/semver/tests/test-hook-discovery.sh
    blob: ff34bcac9a11b0716788e351c79dde766c13e0d7
  - path: plugins/semver/tests/test-hook-execution.sh
    blob: 726915a09246d27cfc474197525a169cefdc2f7f
  - path: plugins/semver/tests/test-hook-failures.sh
    blob: 6be046822fa395c49dd051c32c04ccac06344a93
  - path: plugins/semver/tests/test-hook-reentrancy.sh
    blob: f42c68a95e4cb6652e4e9ca7c46a550b8cf41eea
  - path: plugins/semver/tests/test-init.sh
    blob: 5b187c49b2c33a194ee57651e3c8d1e129f45fff
  - path: plugins/semver/tests/test-integration.sh
    blob: ec210c208c64353e050015700f2e70e51960f357
  - path: plugins/semver/tests/test-prompt-hooks.sh
    blob: ce9972d43cf214b0de434a2bc86094b05c1ecbef
generator: cartographer/4
baseline: cb09ceb006e3fb4759a91d64d9e6655e67d04bf7
---

# Module: plugins/semver/tests (chunk 1)

## Purpose

This is the hand-rolled bash test suite for the semver plugin's CLI and hook runner — a lightweight function-based test framework (no bats) built around shared fixture/assertion helpers in helpers/setup.sh and a discovery-based runner in run-tests.sh rather than a third-party framework. Each test-*.sh file creates a throwaway git+.semver repo fixture, drives it through semver-cli or hooks/run-user-hooks.sh, and asserts on the resulting JSON/files/git-state, giving end-to-end coverage of CLI commands (current, validate, bump, tracking, auto-bump, repair, init), hook discovery/ordering/failure-handling/reentrancy, prompt hooks, and full bump-flow integration. If this module vanished, semver-cli's JSON contracts (ok/error codes, display/questions payloads) and the hook runner's failure/reentrancy semantics would have no regression protection.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

- Each test_* function runs inside its own subshell via `set -e; "$func"` captured in a command substitution (plugins/semver/tests/run-tests.sh:44-49), so an assertion failure or unbound var in one test cannot abort the whole file or leak env changes forward.
- Fixture repos are owned per-test-function: created with `mktemp -d "/tmp/semver-test-XXXXXX"` and torn down by cleanup_test_repo, registered via `trap "cleanup_test_repo '$repo'" RETURN` in nearly every test (e.g. plugins/semver/tests/test-cli.sh:63); cleanup_test_repo refuses to rm -rf anything outside the /tmp/semver-test-* prefix (plugins/semver/tests/helpers/setup.sh:101-106).
- Full-CLI-tracked repo fixtures are file-local, not shared: create_semver_repo is redefined near-identically in both plugins/semver/tests/test-cli.sh:9 and plugins/semver/tests/test-display-questions.sh:9, and plugins/semver/tests/test-bump-run.sh:12 defines its own _make_tracked_repo rather than reusing either — each file owns its fixture builder instead of pulling one from helpers/setup.sh.

## External deps


## Gotchas

- sed_inplace() exists solely to paper over BSD sed (macOS, needs `-i ''`) vs GNU sed (`-i`) incompatibility by editing through a temp file (plugins/semver/tests/helpers/setup.sh:16-23).
- cleanup_test_repo only rm -rf's paths matching /tmp/semver-test-* as a safety guard against deleting an unintended directory (plugins/semver/tests/helpers/setup.sh:101-106).
- Reentrancy exit codes differ by call path: hooks/run-user-hooks.sh exits 2 when SEMVER_BUMP_IN_PROGRESS is set (asserted in plugins/semver/tests/test-hook-reentrancy.sh:17), but semver-cli's own bump-gather reentrancy path exits 0 with ok=false instead — a distinction the test spells out in an inline comment (plugins/semver/tests/test-cli.sh:816-817).
- helpers/setup.sh declares PASS_COUNT/FAIL_COUNT/FAIL_NAMES as "Counters (managed by run-tests.sh)" (plugins/semver/tests/helpers/setup.sh:9-12), but run-tests.sh never references them — it tracks its own separate TOTAL_PASS/TOTAL_FAIL/ALL_FAILURES instead (plugins/semver/tests/run-tests.sh:17-20), leaving the setup.sh globals dead.
