---
module: plugins/semver/tests
summary: "Bats-free bash test harness exercising semver-cli, semver-router.sh, and run-user-hooks.sh against throwaway git repos."
read_when: "Adding or debugging semver tests, or reusing the bash test harness"
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
  - path: plugins/semver/tests/test-integration.sh
    blob: ec210c208c64353e050015700f2e70e51960f357
  - path: plugins/semver/tests/test-prompt-hooks.sh
    blob: ce9972d43cf214b0de434a2bc86094b05c1ecbef
  - path: plugins/semver/tests/test-router.sh
    blob: 9981ff4600c847f5fdafc76be727dd5375d49606
generator: cartographer/4
baseline: 50c998d53e2ed58951ac5f794afd32bfa729f658
---

# Module: plugins/semver/tests

## Purpose

This is the semver plugin's own automated test suite: a self-rolled, bats-free bash harness (helpers/setup.sh + run-tests.sh) that discovers and runs `test_*` functions from each test-*.sh file against throwaway git repos built in /tmp. It exercises every executable surface of the semver plugin end-to-end — bin/semver-cli's JSON commands (current, validate, bump gather/execute/run/first-version, tracking start/stop-gather/stop-execute/restore-tags, auto-bump start/stop, repair diagnose/execute, recommend), bin/semver-router.sh's argument routing, and hooks/run-user-hooks.sh's pre-bump/post-bump discovery, ordering, failure handling, PROMPT_HOOK.md passthrough, and reentrancy guard. Losing this module would remove the only verification that the semver JSON contract (ok/executed/questions/display fields) and the hook lifecycle actually behave as documented, leaving regressions to surface only against a real user's repo.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

Fixture repos are ephemeral: create_test_repo/create_semver_repo mktemp a fresh /tmp/semver-test-XXXXXX git repo per test (plugins/semver/tests/helpers/setup.sh:27-29, duplicated per test file), and each test_* function installs `trap "cleanup_test_repo '$repo'" RETURN` so the repo is deleted when the function returns regardless of pass or fail. Global counters PASS_COUNT/FAIL_COUNT/FAIL_NAMES are declared in helpers/setup.sh:10-12 but never incremented anywhere in this module — the real pass/fail bookkeeping lives in run-tests.sh's own TOTAL_PASS/TOTAL_FAIL/ALL_FAILURES (plugins/semver/tests/run-tests.sh:17-20), so those setup.sh globals are vestigial. Each test_* function is executed in its own subshell for isolation (`output=$( set -e; "$func" 2>&1 )`, plugins/semver/tests/run-tests.sh:44-49), but the test file itself is sourced straight into the runner's process, so any non-test_ helper it defines is shared, mutable, process-lifetime state across the whole run (see gotchas). SEMVER_BUMP_IN_PROGRESS is the reentrancy invariant this module verifies throughout: hooks/run-user-hooks.sh must exit 2 with status "blocked" when it is already set (plugins/semver/tests/test-hook-reentrancy.sh:4-19, plugins/semver/tests/test-integration.sh:136-162), and helpers/setup.sh's simulate_bump clears it before each real invocation (plugins/semver/tests/helpers/setup.sh:138,163) so the harness's own environment can't false-positive that guard.

## External deps


## Gotchas

sed_inplace() (plugins/semver/tests/helpers/setup.sh:19-23) edits through a temp file instead of `sed -i` specifically to dodge the BSD-vs-GNU `-i` flag incompatibility (comment at plugins/semver/tests/helpers/setup.sh:16-18). cleanup_test_repo() (plugins/semver/tests/helpers/setup.sh:101-106) refuses to `rm -rf` unless the path matches `/tmp/semver-test-*`, a deliberate guard against deleting an unrelated directory if a caller passes a bad `$repo`. simulate_bump() explicitly clears `SEMVER_BUMP_IN_PROGRESS=""` before invoking the real runner (plugins/semver/tests/helpers/setup.sh:138 and :163) so the harness's own shell env can never leak a stale reentrancy guard into the simulated flow. run-tests.sh sources every test-*.sh file directly into its own process (plugins/semver/tests/run-tests.sh:37) and afterward unsets only the discovered `test_*` functions (plugins/semver/tests/run-tests.sh:64-67) — any other helper a test file defines persists into later files, and the assumption that every file's copy is kept identical has already slipped: `create_semver_repo` is independently redefined in test-cli.sh:9, test-display-questions.sh:9, and test-router.sh:10, and test-router.sh's copy diverges — it omits the `# Initial commit` and `# Initialize semver config` comments the other two carry immediately before the same commands (test-cli.sh:18,23 and test-display-questions.sh:18,23; the corresponding commands sit at test-router.sh:19,23 with no preceding comment). The drift is currently inert only because `test-router.sh` sorts last among run-tests.sh's alphabetically-globbed test-*.sh files (plugins/semver/tests/run-tests.sh:90) and nothing sourced afterward calls `create_semver_repo`; a new test file that sorted after "router" and called it would silently inherit the drifted, comment-stripped body instead of the two files' matching one. test-router.sh also recomputes its own `PLUGIN_ROOT`/`ROUTER` at file scope (plugins/semver/tests/test-router.sh:5-6), silently overwriting the `PLUGIN_ROOT` global helpers/setup.sh already set (plugins/semver/tests/helpers/setup.sh:5) — harmless only because both resolve to the same plugin directory from their respective depths.
