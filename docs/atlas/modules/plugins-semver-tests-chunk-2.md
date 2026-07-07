---
module: "plugins/semver/tests (chunk 2)"
summary: "Bash tests for semver-router.sh's command routing/aliases and semver-cli's `set` (explicit-version) subcommand."
read_when: "Changing router argument routing or semver-cli's `set` subcommand"
sources:
  - path: plugins/semver/tests/test-router.sh
    blob: b46148087b516791ba60aa331a954b1e396ac8c5
  - path: plugins/semver/tests/test-set.sh
    blob: 4e495ad362ab56e6d5d491abecd6da123c6bdc2a
generator: cartographer/4
baseline: cb09ceb006e3fb4759a91d64d9e6655e67d04bf7
---

# Module: plugins/semver/tests (chunk 2)

## Purpose

This chunk covers two of the semver plugin's most argument-heavy surfaces: test-router.sh exercises bin/semver-router.sh's command dispatch end-to-end — every subcommand, aliases (`check`→validate, `fix`→repair), `--plugin-root`/option passthrough, and the JSON usage/error fallback for unknown commands. test-set.sh exhaustively covers `semver-cli set`'s explicit-version-assignment logic: forward/non-sequential/backward sets, same-version re-cuts (no-op vs. tag-recreate), tag conflicts, invalid versions, the tracking-inactive and dirty-tree guards, reentrancy blocking, first-version-via-set, and post-bump hook firing. Losing this chunk would remove the only coverage proving the router's alias/passthrough contract stays correct and that `set` — the plugin's most invariant-heavy version-assignment path — doesn't silently corrupt VERSION, CHANGELOG.md, or git tags on edge-case input.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

Both files build a fresh throwaway git repo per test rather than sharing one process-wide fixture: test-router.sh's create_semver_repo() (plugins/semver/tests/test-router.sh:10-52) and test-set.sh's _set_repo() (plugins/semver/tests/test-set.sh:9-48) each independently construct an equivalent tracking-active repo (git init, .semver/config.yaml, VERSION=v1.0.0, CHANGELOG.md, tag v1.0.0). Cleanup ownership differs between the two: test-router.sh ends each test_route_* function with a bare `rm -rf "$dir"` (e.g. plugins/semver/tests/test-router.sh:68, :81, :103) with no trap guard, so it only runs if the function's prior statements fall through to that final line, while test-set.sh registers `trap "cleanup_test_repo '$repo'" RETURN` immediately after fixture creation (e.g. plugins/semver/tests/test-set.sh:54, :70, :78), which fires on any function return. test-set.sh never defines `$CLI`, `$PLUGIN_ROOT`, or `cleanup_test_repo` itself — they're first referenced at plugins/semver/tests/test-set.sh:57, :234, and :54 respectively — so the file only behaves correctly when sourced into an environment that already provides them (the shared test harness), unlike test-router.sh, which computes its own `PLUGIN_ROOT`/`ROUTER` at file scope (plugins/semver/tests/test-router.sh:5-6) and is more self-contained. Most `set` invocations in test-set.sh pass the dummy `--plugin-root /x` (e.g. plugins/semver/tests/test-set.sh:57, :71, :79), which is inert for those assertions; only test_set_post_bump_hook_fires passes the real `"$PLUGIN_ROOT"` (plugins/semver/tests/test-set.sh:234), because that is the one test in this file that needs `set` to actually discover and run a `.semver/hooks/post-bump/` script under the real plugin tree.

## External deps


## Gotchas

`semver-cli set run <version>` to the currently-checked-out version is not an error — it's a supported "recut": test_set_recut_same_version_is_noop (plugins/semver/tests/test-set.sh:101-111) asserts `.recut` is true and `.tag_action` is "noop" with no new commit and no duplicate CHANGELOG.md heading, while test_set_recut_recreates_missing_tag (plugins/semver/tests/test-set.sh:113-120) asserts the same re-cut instead reports `.tag_action` "created" when the version's git tag had been deleted beforehand — the CLI treats a missing tag on the already-current version as reason enough to recreate it even though nothing else about the repo changed.
