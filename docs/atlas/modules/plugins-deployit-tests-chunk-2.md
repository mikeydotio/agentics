---
module: "plugins/deployit/tests (chunk 2)"
summary: "Bash+python3 tests exercising deployit-cli/-backend via real git repos, fake gh, and DEPLOYIT_SKIP_* env sandboxing."
read_when: "Touching deployit-cli push/PR-fallback, rm, redeploy, or config/release parsing"
sources:
  - path: plugins/deployit/tests/test-backend-version-label.sh
    blob: fa42caacb9b717115e36d41d62fcd82e7c5920b7
  - path: plugins/deployit/tests/test-bootstrap-dirs.sh
    blob: fcb3b27daa351b0cba8db9cd480d2b35677662d1
  - path: plugins/deployit/tests/test-cli-archive-build-number.sh
    blob: 300b23be4b25228e0c39a522166c692fabe8b911
  - path: plugins/deployit/tests/test-cli-bump.sh
    blob: 04836f17b13c459010bcf9394f9fb1290831ceec
  - path: plugins/deployit/tests/test-cli-classify-push-failure.sh
    blob: 63117ce4a300476dae2632a87229430634aa47f2
  - path: plugins/deployit/tests/test-cli-config-sparkle.sh
    blob: 6f8ac4ff1172a8da5127f4dc3f8d64484d12fe88
  - path: plugins/deployit/tests/test-cli-deploy-autoprune.sh
    blob: 8f43eb9f58e1c4ad048e566c70e0313ae401e004
  - path: plugins/deployit/tests/test-cli-deploy-pr-automerge.sh
    blob: 6f488ecd1974e97d525ab2594947dc9adc7c8b61
  - path: plugins/deployit/tests/test-cli-deploy-pr-leave-open.sh
    blob: 048aca413738047ded55eda85cee972681886efe
  - path: plugins/deployit/tests/test-cli-deploy-release-wiring.sh
    blob: 0e013d6517715c30f668601827a896c1972be904
  - path: plugins/deployit/tests/test-cli-preflight.sh
    blob: 894d8c16d5cd39f2d0f18f40f0aab8527c185e9b
  - path: plugins/deployit/tests/test-cli-publish-preserve-on-failure.sh
    blob: 0928c7b78ef0847181fa040170b1a8b3347bc1e5
  - path: plugins/deployit/tests/test-cli-redeploy.sh
    blob: 5cc4141d1c5dc1700865ec366d1304c672bd9817
  - path: plugins/deployit/tests/test-cli-rm-pr-fallback.sh
    blob: 52a497fd13bde12d066e87aba4647d8d6852f285
  - path: plugins/deployit/tests/test-cli-rm.sh
    blob: dfac34f95d15aa78c898783643ccdc0c990f1bbf
generator: cartographer/4
baseline: a4486d2b70ad4124762f9d777af6a7dc007bdc6c
---

# Module: plugins/deployit/tests (chunk 2)

## Purpose

This chunk covers deployit's higher-risk CLI paths: git push-failure classification and PR fallback (ruleset/protected/auth/non-fast-forward), auto-prune on deploy, bootstrap/redeploy plist and symlink management, and rm's index-then-disk ordering. Tests load bin/deployit-cli as a module via importlib.machinery.SourceFileLoader to call internals like _append_to_index, _classify_push_failure, and _read_archive_build_number directly, and drive real local bare git repos (with pre-receive hooks simulating GitHub rulesets) instead of mocking git. Losing this chunk would strip regression coverage for the exact failure modes deployit's publish path exists to survive: a rejected push must never silently drop a commit.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `make_app` | def | `plugins/deployit/tests/test-cli-deploy-release-wiring.sh:32` | Creates a minimal macOS .app bundle (executable + Info.plist CFBundleShortVersionString) for staging/publish fixtures. |
| `mk` | def | `plugins/deployit/tests/test-cli-deploy-autoprune.sh:37` | Builds a serve/<id>/ fixture dir and returns a matching builds.json entry dict for seeding prune-scope cases. |
| `mk` | def | `plugins/deployit/tests/test-cli-rm.sh:45` | Builds an index entry (and a serve/<id>/ fixture if local=True) to seed local/foreign/cross-platform rm-scoping cases. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

Tests bypass deployit-cli's argv parser and unit-test its internals directly by loading the script as a module via importlib.machinery.SourceFileLoader (plugins/deployit/tests/test-cli-classify-push-failure.sh:13, plugins/deployit/tests/test-cli-deploy-pr-automerge.sh:51, plugins/deployit/tests/test-cli-archive-build-number.sh:39), calling functions like _classify_push_failure, _append_to_index, _read_archive_build_number, _read_config, and _publish_github_release straight off the loaded module.
- PR/ruleset scenarios stand up REAL local bare git repos with a `pre-receive` hook that rejects `main` with GH013-style stderr while allowing `deploy/*` branches, so the push-failure classifier and PR-fallback path run against real git plumbing rather than a git mock (plugins/deployit/tests/test-cli-deploy-pr-automerge.sh:30-42, plugins/deployit/tests/test-cli-rm-pr-fallback.sh:31-41).
- tests/fakes/gh (plugins/deployit/tests/fakes/gh:3-15) is a stateful bash stub logging each invocation to $FAKE_GH_LOG and toggled by env knobs (FAKE_GH_PR_CREATE_FAIL, FAKE_GH_PR_EXISTS, FAKE_GH_PR_MERGE_FAIL, etc.); DEPLOYIT_LAUNCHCTL_BIN is pointed at tests/fakes/true (a real compiled no-op `true` binary) to stub launchctl (plugins/deployit/tests/test-bootstrap-dirs.sh:10).
- DEPLOYIT_STATE_DIR plus DEPLOYIT_SKIP_* env vars (LAUNCHD, TAILSCALE_SERVE, INDEX_CLONE, KICKSTART, VERIFY, CODESIGN_VERIFY, RELEASE_PUBLISH) sandbox bootstrap/redeploy/deploy side effects away from the real machine (plugins/deployit/tests/test-bootstrap-dirs.sh:8-13, plugins/deployit/tests/test-cli-redeploy.sh:15-22, plugins/deployit/tests/test-cli-deploy-release-wiring.sh:18,70).
- test-backend-version-label.sh runs bin/deployit-backend as a real subprocess and polls /deployit/_healthz before asserting on rendered HTML (plugins/deployit/tests/test-backend-version-label.sh:58-67).

## External deps

- contextlib — imported
- importlib.machinery — imported
- importlib.util — imported
- json — imported

## Gotchas

- _read_archive_build_number's macOS layout check was a real latent bug: every macOS deploy failed at the build-number read because only the iOS Info.plist path was checked, caught by the first real macOS deploy (plugins/deployit/tests/test-cli-archive-build-number.sh:4-6).
- _read_config's TOML parsing has two live code paths — tomllib on Python 3.11+, a regex fallback below it — and this test runs whichever the ambient python3 provides, so the dev/CI python version silently picks the path under test (plugins/deployit/tests/test-cli-config-sparkle.sh:2-4).
- Auto-prune's keep-cap is scoped by (bundle_id, platform, origin_base_url) together, so a same-app build on a different platform or a different origin survives pruning past the cap (plugins/deployit/tests/test-cli-deploy-autoprune.sh:2-5,120-123).
- test-cli-deploy-release-wiring.sh asserts call ORDER by grepping deployit-cli's own source text (not runtime behavior) to guarantee _publish_github_release always runs after _append_to_index and _refresh_local_backend, so a failed deploy can never orphan a public GitHub release (plugins/deployit/tests/test-cli-deploy-release-wiring.sh:85-88).
- An auth-classified push failure preserves the commit on a LOCAL branch named deploy/<id>-local and skips the PR fallback entirely — a different recovery path than ruleset/protected failures, which push the branch and open a PR (plugins/deployit/tests/test-cli-publish-preserve-on-failure.sh:125-128).
- test-cli-rm.sh polls the bare origin's log for up to ~1s instead of reading once, because receive-pack's post-receive settle (quarantine migration + a detached maintenance run) can make a fresh reader briefly miss a just-pushed tip (plugins/deployit/tests/test-cli-rm.sh:84-93).
