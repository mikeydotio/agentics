---
module: "plugins/deployit/tests (chunk 1)"
summary: "Bash integration tests that boot the real deployit-backend server against fixture trees, plus gh/tailscale PATH fakes."
read_when: "Touching deployit-backend HTTP routes/rendering or the bash test harness/fakes"
sources:
  - path: plugins/deployit/tests/fakes/gh
    blob: fa6e252e325c5fedba6b0e3ec0a9edf528d68208
  - path: plugins/deployit/tests/fakes/tailscale
    blob: e791bddad3f3d31a1e584d72f71075a4a5270547
  - path: plugins/deployit/tests/run-tests.sh
    blob: 5d017ec337d7a22a0616704396c2d233e1b32278
  - path: plugins/deployit/tests/test-backend-500-on-corrupt.sh
    blob: c1683f5c6233f47754ef702b8204def77f0f3815
  - path: plugins/deployit/tests/test-backend-appcast.sh
    blob: 496556d761d1dc7f7b0cae01714a7764f3fae26a
  - path: plugins/deployit/tests/test-backend-delete.sh
    blob: b2b76f44ba68e724055af8182a889e2dd17d89a3
  - path: plugins/deployit/tests/test-backend-healthz.sh
    blob: 4e9022321aa470e7ff69c9a316a4addd2840309d
  - path: plugins/deployit/tests/test-backend-listing-groups-by-product.sh
    blob: cdc14c5b8df733eb6a427ddeb3eb758edff91785
  - path: plugins/deployit/tests/test-backend-listing.sh
    blob: 6372fd40883aa2fa0de259549b8b0997a3fac551
  - path: plugins/deployit/tests/test-backend-macos-download.sh
    blob: cf9433d2f1fafb03d62aae6640a34ccf3f03e865
  - path: plugins/deployit/tests/test-backend-nav-no-ptr.sh
    blob: 9c115b7e7e5c5a054c89b95dc08435b10b181aaf
  - path: plugins/deployit/tests/test-backend-per-build.sh
    blob: 5fac8882eac31221f77613bf24eb4a257539c7dd
  - path: plugins/deployit/tests/test-backend-product-page.sh
    blob: 2ba3cd7336b3a3070b79e6b48a6d609228c7a9be
  - path: plugins/deployit/tests/test-backend-refresh.sh
    blob: 8af6d863fac5ab4787f05f8773511f0dedea268a
  - path: plugins/deployit/tests/test-backend-static-assets.sh
    blob: 2a6a390c6fe8a1e708e1f90d404eee00918cef86
generator: cartographer/4
baseline: 50c998d53e2ed58951ac5f794afd32bfa729f658
---

# Module: plugins/deployit/tests (chunk 1)

## Purpose

This is deployit's black-box test suite: each test-backend-*.sh script boots the real bin/deployit-backend python server against a hand-built ROOT (index/builds.json plus a serve/ tree), then curls its HTTP endpoints and asserts on status codes and rendered HTML/JSON — proving the actual production server rather than a mock. run-tests.sh is the discovery/aggregation harness that globs and runs every test-*.sh, and fakes/gh plus fakes/tailscale are PATH-installable stand-ins for the real CLIs so deployit's bootstrap/deploy-adjacent tests need no network or auth. If this module vanished, deployit's HTTP surface (listing, product pages, appcast, per-build downloads, delete, refresh, static assets) would have no regression coverage at all.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

Each test-backend-*.sh is fully self-contained: it builds its own ROOT via mktemp -d, symlinks PLUGIN_ROOT into ROOT/_plugin_root so the backend can resolve its own static assets (plugins/deployit/tests/test-backend-healthz.sh:9), spawns the real python backend as a background process, and traps EXIT to kill the PID and (usually) rm -rf the ROOT tempdir (plugins/deployit/tests/test-backend-healthz.sh:15). Startup is synchronized by polling the live `_healthz` endpoint in a bounded retry loop (50 x 0.1s) rather than a fixed sleep, so tests never race the server's boot (plugins/deployit/tests/test-backend-healthz.sh:17-22). run-tests.sh owns test discovery and lifecycle: it globs test-*.sh, runs each as a subprocess with output captured to /tmp/deployit-test.log, and aggregates PASS/FAIL counts, printing captured output indented only on failure (plugins/deployit/tests/run-tests.sh:14-29). test-backend-delete.sh sets DEPLOYIT_SKIP_GC_PUSH=1 so the backend's shelled-out CLI mutates index/builds.json in place without a git remote, keeping the delete test network- and git-free (plugins/deployit/tests/test-backend-delete.sh:11). fakes/gh and fakes/tailscale are PATH-substitutable stand-ins for the real CLIs, driven entirely by env-var knobs documented in their own header comments (plugins/deployit/tests/fakes/gh:2-9) or fixed canned output (plugins/deployit/tests/fakes/tailscale:2-10).

## External deps

- json — imported

## Gotchas

test-backend-static-assets.sh's cleanup trap only kills the backend PID and never removes its ROOT tempdir, unlike every other test in the module (plugins/deployit/tests/test-backend-static-assets.sh:20; contrast the kill+rm -rf pattern at plugins/deployit/tests/test-backend-healthz.sh:15). test-backend-500-on-corrupt.sh and test-backend-static-assets.sh both hardcode PORT=18733 (plugins/deployit/tests/test-backend-500-on-corrupt.sh:14, plugins/deployit/tests/test-backend-static-assets.sh:16); this collision is harmless only because run-tests.sh executes test-*.sh serially in a single for-loop (plugins/deployit/tests/run-tests.sh:14).
