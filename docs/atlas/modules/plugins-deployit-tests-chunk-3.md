---
module: "plugins/deployit/tests (chunk 3)"
summary: "Bash smoke tests for deployit-release's signing/tag/version logic and release-context, plus a live post-deploy check."
read_when: "Debugging deployit-release/gh publishing or verifying a live deployment"
sources:
  - path: plugins/deployit/tests/test-metadata.sh
    blob: 5c49e2f4a48015c86de20068bd861f6edde9103c
  - path: plugins/deployit/tests/test-release-adhoc-signing.sh
    blob: 1c2eec4f879b10ad29ff5ac5990c35b77c5e2c21
  - path: plugins/deployit/tests/test-release-context.sh
    blob: f7fee93b3950536b1d8343e7cd10de58289a0ea1
  - path: plugins/deployit/tests/test-release-existing-tag.sh
    blob: 00332c702ff756d1eb4c1a09f3515cb8a49f9826
  - path: plugins/deployit/tests/test-release-gh-invocation.sh
    blob: bd3aa872ed4f20bc7f80acaf971571acc33ccc6f
  - path: plugins/deployit/tests/test-release-tag-exists-omits-target.sh
    blob: 5a1d69c14cfc83138a84c810d00925393691f7fd
  - path: plugins/deployit/tests/test-release-version-resolution.sh
    blob: d635899e972a0301e03037445d8dc7ab49c90e9a
  - path: plugins/deployit/tests/verify-live.sh
    blob: bd37453899de071cc6fc016d65e27dd31550e720
generator: cartographer/4
baseline: 50c998d53e2ed58951ac5f794afd32bfa729f658
---

# Module: plugins/deployit/tests (chunk 3)

## Purpose

This chunk pins deployit's release-publishing pipeline and gives a human a live-deploy sanity check. Five scripts drive bin/deployit-release end to end against a faked gh binary — the Developer-ID signing gate, existing-tag/--clobber handling, --target omission once a tag exists, dry-run-vs-real gh invocation, and the semver-vs-Info.plist version/tag resolution order — one drives deployit-cli release-context's commit/issue aggregation for release notes, one drives deployit-cli's --__dump-metadata xcodegen project.yml parsing, and verify-live.sh stands apart as a standalone post-deploy smoke test that curls a running instance instead of exercising the CLI in a fixture. If this chunk vanished, a bad gh invocation, wrong tag/version resolution, or a signing-gate regression could ship undetected until a real release failed in production.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

Every test in this chunk except verify-live.sh is a self-contained bash script that builds its own mktemp sandbox (a throwaway git repo or fake .app bundle) and tears it down via `trap ... EXIT`, so no fixture state is shared across files — e.g. plugins/deployit/tests/test-metadata.sh:6-7, plugins/deployit/tests/test-release-context.sh:9.
Release tests never touch real GitHub: they redirect gh to a fake binary via DEPLOYIT_GH_BIN (plugins/deployit/tests/test-release-context.sh:19, plugins/deployit/tests/test-release-existing-tag.sh:20, plugins/deployit/tests/test-release-gh-invocation.sh:21, plugins/deployit/tests/test-release-tag-exists-omits-target.sh:24), and most also stub codesign via DEPLOYIT_SKIP_CODESIGN_VERIFY=1 (plugins/deployit/tests/test-release-existing-tag.sh:21).
verify-live.sh is the outlier: it owns no fixture at all and instead assumes an already-running deployit server, resolving its port from $DEPLOYIT_STATE_DIR/config.toml before hitting it over HTTP — plugins/deployit/tests/verify-live.sh:8-14,40.

## External deps

- importlib.machinery — imported
- json — imported
- sys — imported
- tomli — imported
- tomllib — imported

## Gotchas

gh rejects a divergent --target on an existing tag (HTTP 422 "Release.target_commitish is invalid"), so deployit-release must omit --target once the tag exists on the remote — plugins/deployit/tests/test-release-tag-exists-omits-target.sh:2-7,44-46.
verify-live.sh inverts pass/fail for two markers: finding id="ptr" or touchstart in the served UI is a FAIL, because pull-to-refresh was deliberately replaced by a nav-bar refresh button and pointerdown swipe-to-delete — plugins/deployit/tests/verify-live.sh:79-81,93-95.
test-release-version-resolution.sh loads bin/deployit-release itself as a python module via importlib.machinery.SourceFileLoader to unit-test _resolve_version_and_tag directly, rather than shelling out — plugins/deployit/tests/test-release-version-resolution.sh:17-19.
test-release-adhoc-signing.sh is the one release test that never sets DEPLOYIT_SKIP_CODESIGN_VERIFY (every other release test in this chunk does), so a real unsigned .app produces a genuine codesign failure to verify the Developer-ID gate — plugins/deployit/tests/test-release-adhoc-signing.sh:2-4,22 vs plugins/deployit/tests/test-release-existing-tag.sh:21.
