---
module: "plugins/deployit/tests (chunk 3)"
summary: "Bash tests for deployit macOS staging, release publish, metadata, gc, plus a live-deploy smoke verifier."
read_when: "Touching deployit release, staging, metadata, gc tests, or live-deploy verification"
sources:
  - path: plugins/deployit/tests/test-cli-stage-macos-no-sparkle-tools.sh
    blob: 6b3bfa75c163b4144936d08ceb7c2f26fb025081
  - path: plugins/deployit/tests/test-cli-stage-macos-sparkle.sh
    blob: 483caf8c6d787b64d08bea97ad2796815d6f3f55
  - path: plugins/deployit/tests/test-cli-version.sh
    blob: d7a1daaa409feb77dbb59b51a4c1f76b58050f79
  - path: plugins/deployit/tests/test-gc.sh
    blob: be01b59bafa19e9c5bda91c29d3ccd6101f9ad88
  - path: plugins/deployit/tests/test-metadata-single-app.sh
    blob: 1f36ebce4b6cf9363f3e6045fb7afced5dcd2ef0
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
baseline: a4486d2b70ad4124762f9d777af6a7dc007bdc6c
---

# Module: plugins/deployit/tests (chunk 3)

## Purpose

This chunk is the correctness backstop for deployit's most host-dependent, hardest-to-eyeball code paths — macOS DMG/Sparkle staging, Developer-ID/codesign gating, GitHub release publishing, and Xcode project metadata extraction — each test forcing one specific failure or edge case (a missing sign_update tool, an existing GH tag, an unsigned app, a monorepo vs. single-app project layout) deterministically via env-var seams or a faked `gh` binary rather than depending on real signing keys or network state. verify-live.sh is the odd one out: not a fixture-driven unit test but a smoke check that curls a running deployit instance to confirm a deploy actually shipped the expected markup/asset changes, since a clean exit elsewhere never proves the live server itself was updated. Collectively they guard the exact fragile edges — graceful signing degradation, GH's tag/target_commitish rejection, and version-resolution precedence — that would otherwise only surface once shipped to production.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `make_app` | def | `plugins/deployit/tests/test-cli-stage-macos-sparkle.sh:32` | Creates a fresh minimal Lillist.app bundle so each Sparkle staging case runs against an unmodified fixture. |
| `meta_for` | def | `plugins/deployit/tests/test-cli-stage-macos-sparkle.sh:39` | Returns a canonical _meta.json-shaped dict for build_id, reused across the enabled/disabled Sparkle staging cases. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

Every test is a standalone bash script (no bats/test framework): each resolves TESTS_DIR/PLUGIN_ROOT from BASH_SOURCE and asserts by exiting non-zero + printing FAIL, only printing PASS on success (plugins/deployit/tests/test-cli-version.sh:3-4).
macOS-only tests self-skip (exit 0, "SKIP: ... unavailable") when native tools like hdiutil/ditto/codesign/PlistBuddy are missing, e.g. plugins/deployit/tests/test-cli-stage-macos-no-sparkle-tools.sh:11-12.
Internal (non-CLI) functions are unit-tested by dynamically loading the bin/ script as a Python module via importlib.machinery.SourceFileLoader, bypassing deployit-cli's/-release's own argument parser — `_stage_macos` in plugins/deployit/tests/test-cli-stage-macos-sparkle.sh:24-27 and `_resolve_version_and_tag` in plugins/deployit/tests/test-release-version-resolution.sh:17-19.
Determinism seams are env vars: DEPLOYIT_SPARKLE_SIGN_UPDATE (plugins/deployit/tests/test-cli-stage-macos-no-sparkle-tools.sh:28), DEPLOYIT_SKIP_SPARKLE_SIGN (plugins/deployit/tests/test-cli-stage-macos-sparkle.sh:49), DEPLOYIT_STATE_DIR + DEPLOYIT_SKIP_GC_PUSH (plugins/deployit/tests/test-gc.sh:8-9), and DEPLOYIT_SKIP_CODESIGN_VERIFY (plugins/deployit/tests/test-release-existing-tag.sh:21).
The `gh` CLI is faked by pointing DEPLOYIT_GH_BIN at tests/fakes/gh and driving it with FAKE_GH_* knobs (FAKE_GH_PREV_TAG, FAKE_GH_ISSUES_JSON, FAKE_GH_RELEASE_EXISTS, FAKE_GH_TAG_EXISTS, FAKE_GH_LOG) that set canned responses and capture the invocation for assertion — plugins/deployit/tests/test-release-context.sh:19-21, plugins/deployit/tests/test-release-existing-tag.sh:20-23, plugins/deployit/tests/test-release-tag-exists-omits-target.sh:24-25,41.
Each test isolates state in `mktemp -d` and cleans it via `trap 'rm -rf "$ROOT"' EXIT` (plugins/deployit/tests/test-gc.sh:6-7).
verify-live.sh is not fixture-based: it curls a real running server (port from --port, $DEPLOYIT_STATE_DIR, or the default config path) and accumulates PASS/FAIL counters via pass()/fail() helpers, exiting 1 on any failure (plugins/deployit/tests/verify-live.sh:41-45,138-139).

## External deps

- importlib.machinery — imported
- json — imported
- sys — imported
- tomli — imported
- tomllib — imported

## Gotchas

gh's `release create --target` is rejected with HTTP 422 "Release.target_commitish is invalid" once the tag already exists on the remote, so deployit-release must omit --target on that path — documented and asserted in plugins/deployit/tests/test-release-tag-exists-omits-target.sh:3-6,44-46.
A bare `gc` (no --keep) is asserted to still print valid JSON with "ok": false on stdout despite a nonzero exit; the test captures stdout+stderr together with `2>&1 || true` specifically because `pipefail` would otherwise fire on gc's own failing exit code — plugins/deployit/tests/test-gc.sh:69-76.
The EdDSA signature the Sparkle-enabled test asserts is a literal sentinel, "TEST-ED-SIGNATURE-DO-NOT-SHIP==", produced by the DEPLOYIT_SKIP_SPARKLE_SIGN stub path rather than a real signature — a deliberately unshippable placeholder value — plugins/deployit/tests/test-cli-stage-macos-sparkle.sh:49,60.
Metadata is introspected through a private, dunder-prefixed `--__dump-metadata` flag on the `deploy` subcommand that dumps resolved project metadata without performing a real deploy — plugins/deployit/tests/test-metadata-single-app.sh:32 and plugins/deployit/tests/test-metadata.sh:29.
macOS-only tests SKIP (exit 0) rather than FAIL when hdiutil/ditto/codesign/PlistBuddy are unavailable, so this suite can pass vacuously with zero coverage on a non-macOS host — plugins/deployit/tests/test-release-adhoc-signing.sh:9-11.
