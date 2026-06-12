---
module: "plugins/deployit/tests (chunk 1)"
summary: "Sandboxed bash tests pinning deployit's backend HTTP surface and CLI bootstrap/bump/preflight flows"
read_when: "Touching deployit backend routes/UI, CLI bootstrap/bump/preflight, or its tests"
sources:
  - path: plugins/deployit/tests/fakes/tailscale
    blob: e791bddad3f3d31a1e584d72f71075a4a5270547
  - path: plugins/deployit/tests/run-tests.sh
    blob: 5d017ec337d7a22a0616704396c2d233e1b32278
  - path: plugins/deployit/tests/test-backend-500-on-corrupt.sh
    blob: c1683f5c6233f47754ef702b8204def77f0f3815
  - path: plugins/deployit/tests/test-backend-healthz.sh
    blob: 4e9022321aa470e7ff69c9a316a4addd2840309d
  - path: plugins/deployit/tests/test-backend-listing-groups-by-product.sh
    blob: 7d1099c8b0a3fb980ec5084575d75afd0ea84150
  - path: plugins/deployit/tests/test-backend-listing.sh
    blob: 3e3f20dd4f53ed6b638919c290a2849015ca4f8e
  - path: plugins/deployit/tests/test-backend-per-build.sh
    blob: 40ee874e0c8b38e250605874eb95d14e1e6fa411
  - path: plugins/deployit/tests/test-backend-product-page.sh
    blob: d530f271877a73cff7c33f494d115c73c703c8e8
  - path: plugins/deployit/tests/test-backend-refresh.sh
    blob: 8af6d863fac5ab4787f05f8773511f0dedea268a
  - path: plugins/deployit/tests/test-backend-static-assets.sh
    blob: 2a6a390c6fe8a1e708e1f90d404eee00918cef86
  - path: plugins/deployit/tests/test-backend-version-label.sh
    blob: ad8cf9e2d6ff32f905a5261799607bca81c9ac7b
  - path: plugins/deployit/tests/test-bootstrap-dirs.sh
    blob: fcb3b27daa351b0cba8db9cd480d2b35677662d1
  - path: plugins/deployit/tests/test-cli-bump.sh
    blob: 04836f17b13c459010bcf9394f9fb1290831ceec
  - path: plugins/deployit/tests/test-cli-deploy-autoprune.sh
    blob: 8f43eb9f58e1c4ad048e566c70e0313ae401e004
  - path: plugins/deployit/tests/test-cli-preflight.sh
    blob: 894d8c16d5cd39f2d0f18f40f0aab8527c185e9b
references_modules: [plugins-deployit-bin, plugins-deployit-tests-chunk-2, plugins-semver-misc]
generator: cartographer/1
baseline: b9203a6997fdbc2248086c1aa9ee6f62b1e025b6
verified: true
---

# Module: plugins/deployit/tests (chunk 1)

## Purpose

First alphabetical half of deployit's test suite: black-box HTTP tests against the backend daemon,
sandboxed CLI tests for bootstrap/bump/preflight/auto-prune, the serial runner, and the tailscale
fake. Each test is a self-contained executable: build a throwaway state root, boot the real
production binary, assert on observable HTTP/git/filesystem behavior; externals are faked binaries
or `DEPLOYIT_*` env knobs, never in-process mocks. It is the only regression net for the deployit
web UI's routes and the CLI's semver integration.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `run-tests.sh` | script | `plugins/deployit/tests/run-tests.sh:1` | Serially runs every `test-*.sh` beside it; `$1` filters by substring; exits 1 on failure, dumping `/tmp/deployit-test.log` |
| `tailscale` | fake executable | `plugins/deployit/tests/fakes/tailscale:1` | Injected via `DEPLOYIT_TAILSCALE_BIN`; answers `status --json` with DNSName `studio.tail-abc.ts.net.` for deterministic hostname assertions |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `check` | bash function | `plugins/deployit/tests/test-backend-static-assets.sh:27` | Asserts Content-Type + Cache-Control per PWA asset route via GET `-D -` (backend has no `do_HEAD`) |
| `run_preflight` | bash function | `plugins/deployit/tests/test-cli-preflight.sh:30` | One sandboxed `deployit-cli preflight` invocation shared by every bump-decision case |
| `seed_index` | bash function | `plugins/deployit/tests/test-cli-preflight.sh:36` | Re-seeds `index/builds.json` between cases so scenarios stay isolated |

## Relationships

- `plugins-deployit-tests-chunk-1.run-tests.sh -> plugins-deployit-tests-chunk-2.test-*.sh (calls)`
- `plugins-deployit-tests-chunk-1.test-backend-*.sh -> plugins-deployit-bin.deployit-backend (calls)`
- `plugins-deployit-tests-chunk-1.test-bootstrap-dirs.sh -> plugins-deployit-bin.deployit-cli (calls)`
- `plugins-deployit-tests-chunk-1.test-cli-bump.sh -> plugins-deployit-bin.deployit-cli (calls)`
- `plugins-deployit-tests-chunk-1.test-cli-bump.sh -> plugins-semver-misc.semver-cli (calls)`
- `plugins-deployit-tests-chunk-1.test-cli-deploy-autoprune.sh -> plugins-deployit-bin._append_to_index (calls)`
- `plugins-deployit-tests-chunk-1.test-cli-preflight.sh -> plugins-deployit-bin.deployit-cli (calls)`

## Type notes

- Every test-backend-*.sh boots the real backend with `--root <mktemp> --no-git-pull`.
- plugins/deployit/tests/test-backend-healthz.sh:7-9 seeds serve/, index/, logs/, `_plugin_root`.
- Fixtures mirror production schema: index/builds.json entries plus serve/<id>/_meta.json.
- Pinned GET routes: /deployit/, /deployit/p/<bundle>/<platform>/, /deployit/<build-id>/, _healthz.
- Pinned POST route: /deployit/_internal/refresh: plugins/deployit/tests/test-backend-refresh.sh:18
- Version label rule (semver wins): plugins/deployit/tests/test-backend-version-label.sh:2
- DEPLOYIT_STATE_DIR redirects all CLI state: plugins/deployit/tests/test-bootstrap-dirs.sh:8
- DEPLOYIT_SKIP_* disables launchd/serve/clone: plugins/deployit/tests/test-bootstrap-dirs.sh:11-13
- DEPLOYIT_SEMVER_CLI overrides semver-cli discovery: plugins/deployit/tests/test-cli-bump.sh:35
- test-cli-bump.sh SKIPs when semver-cli is absent: plugins/deployit/tests/test-cli-bump.sh:10
- Autoprune loads deployit-cli with importlib: plugins/deployit/tests/test-cli-deploy-autoprune.sh:86
- Prune scope pinned: only same (bundle_id, platform, origin_base_url) entries are pruned.
- preflight fixture matches _derive_metadata shape: plugins/deployit/tests/test-cli-preflight.sh:17

## External deps

- curl — every backend assertion is an HTTP request against 127.0.0.1
- python3 stdlib (json, pathlib, importlib) — heredoc fixture builders and the autoprune harness
- git — bare-remote and work-tree fixtures backing index pushes and release commits

## Gotchas

- PORT=18733 double-booked: plugins/deployit/tests/test-backend-500-on-corrupt.sh:14
- PORT=18733 also bound: plugins/deployit/tests/test-backend-static-assets.sh:16; serial-safe only.
- curl -I 501s (no do_HEAD); use GET -D: plugins/deployit/tests/test-backend-static-assets.sh:30
- Cleanup gap: plugins/deployit/tests/test-backend-static-assets.sh:20 traps kill but never rm -rf.
- Path traversal in build paths must 404: plugins/deployit/tests/test-backend-per-build.sh:58
- Discovery glob is test-*.sh: plugins/deployit/tests/run-tests.sh:14; verify-live.sh not included.
- DEPLOYIT_LAUNCHCTL_BIN points at a no-op fake: plugins/deployit/tests/test-bootstrap-dirs.sh:10
