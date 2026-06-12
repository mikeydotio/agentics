---
module: plugins/semver/tests
summary: "Mock-free bash harness driving semver's real hook runner, CLI, and router in throwaway /tmp git repos"
read_when: "Adding or debugging semver tests, or reusing the source-and-discover bash harness"
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
references_modules: [plugins-semver-hooks, plugins-semver-misc]
generator: cartographer/1
baseline: 65c6f5e8e65713af63741fbe8d498384f530200e
verified: true
---

# Module: plugins/semver/tests

## Purpose

Mock-free suite for the semver plugin: every test builds a throwaway git repo under /tmp and
drives the real hook runner, Python CLI, and router, asserting on JSON output and on-disk
effects. The harness is framework-free bash — test files are sourced, `test_*` functions are
discovered and run in isolated subshells — and `simulate_bump` re-enacts the skill's bump flow
against the real runner.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `add_feature_commit` | function | `plugins/semver/tests/helpers/setup.sh:66` | Commits one file to a fixture repo; message arg optional |
| `assert_eq` | function | `plugins/semver/tests/helpers/setup.sh:173` | Equality assertion |
| `assert_exit_code` | function | `plugins/semver/tests/helpers/setup.sh:251` | Exit-code equality assertion |
| `assert_file_contains` | function | `plugins/semver/tests/helpers/setup.sh:201` | Asserts the pattern greps in the file |
| `assert_file_exists` | function | `plugins/semver/tests/helpers/setup.sh:227` | Asserts the path is a regular file |
| `assert_file_not_contains` | function | `plugins/semver/tests/helpers/setup.sh:214` | Inverse of `assert_file_contains` |
| `assert_file_not_exists` | function | `plugins/semver/tests/helpers/setup.sh:239` | Inverse of `assert_file_exists` |
| `assert_json_field` | function | `plugins/semver/tests/helpers/setup.sh:264` | Asserts `jq -r <field>` of a JSON string equals expected |
| `assert_ne` | function | `plugins/semver/tests/helpers/setup.sh:188` | Inequality assertion |
| `cleanup_test_repo` | function | `plugins/semver/tests/helpers/setup.sh:101` | `rm -rf` of a fixture repo; refuses paths outside `/tmp/semver-test-*` |
| `create_hook_script` | function | `plugins/semver/tests/helpers/setup.sh:74` | Writes an executable user hook into the fixture's `.semver/hooks/<phase>/` |
| `create_prompt_hook` | function | `plugins/semver/tests/helpers/setup.sh:91` | Writes the fixture's `.semver/hooks/<phase>/PROMPT_HOOK.md` verbatim |
| `create_test_repo` | function | `plugins/semver/tests/helpers/setup.sh:27` | Hook-suite fixture: seeded repo (config, VERSION, CHANGELOG, tag); echoes its path |
| `run-tests.sh` | script | `plugins/semver/tests/run-tests.sh:1` | Entry point; optional arg substring-filters test files; exit code is the failure count |
| `sed_inplace` | function | `plugins/semver/tests/helpers/setup.sh:19` | BSD/GNU-portable in-place sed via a temp file |
| `simulate_bump` | function | `plugins/semver/tests/helpers/setup.sh:114` | Re-enacts the skill's bump flow; reports via `SIM_EXIT_CODE` and `SIM_RESULT_*` globals |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `run_test_file` | function | `plugins/semver/tests/run-tests.sh:26` | Harness core: sources a file, finds `test_*` via `declare -F`, runs each in a `set -e` subshell, unsets after |
| `create_semver_repo` | function | `plugins/semver/tests/test-cli.sh:9` | CLI-grade fixture (main branch, `git_tagging: true`); duplicated in the display-questions and router test files |
| `_make_tracked_repo` | function | `plugins/semver/tests/test-bump-run.sh:12` | Self-contained copy of the CLI fixture so the file is independent of source order |
| `RUNNER` | variable | `plugins/semver/tests/helpers/setup.sh:6` | Path to the hook runner under test; hook tests invoke `bash "$RUNNER" <phase> <type> <old> <new> <repo>` |

## Relationships

- `plugins-semver-tests.RUNNER -> plugins-semver-hooks.run-user-hooks.sh (calls)`
- `plugins-semver-tests.CLI -> plugins-semver-misc.semver-cli (calls)`
- `plugins-semver-tests.ROUTER -> plugins-semver-misc.semver-router.sh (calls)`
- `plugins-semver-tests.run-tests.sh -> plugins-semver-tests.setup.sh (calls)`

## Type notes

- Pass = exit 0 from a `set -e` subshell (plugins/semver/tests/run-tests.sh:47)
- Fixtures live in `/tmp/semver-test-*` mktemp dirs (plugins/semver/tests/helpers/setup.sh:29)
- Each test frees its repo via a RETURN trap (plugins/semver/tests/test-cli.sh:63)
- Assertions print FAIL detail and return 1 (plugins/semver/tests/helpers/setup.sh:181)
- `simulate_bump` returns 0; check `SIM_EXIT_CODE` (plugins/semver/tests/helpers/setup.sh:144)
- `simulate_bump` clears `SEMVER_BUMP_IN_PROGRESS` (plugins/semver/tests/helpers/setup.sh:138)

## External deps

- jq — parses all JSON assertions; required (plugins/semver/tests/run-tests.sh:79)
- git — fixture repos, commits, tags; required (plugins/semver/tests/run-tests.sh:84)

## Gotchas

- Test files are sourced — top-level code runs at load (plugins/semver/tests/run-tests.sh:37)
- Only functions are unset between files; variables persist (plugins/semver/tests/run-tests.sh:66)
- Duplicated `create_semver_repo` defs: last sourced wins (plugins/semver/tests/test-router.sh:10)
- `PASS_COUNT`/`FAIL_NAMES` are never read (plugins/semver/tests/helpers/setup.sh:10)
- Fixture creators `cd` and rely on subshell isolation (plugins/semver/tests/helpers/setup.sh:31)
