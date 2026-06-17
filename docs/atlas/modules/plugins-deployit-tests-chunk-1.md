---
module: "plugins/deployit/tests (chunk 1)"
summary: "Sandboxed bash tests pinning deployit's backend HTTP surface, CLI bootstrap, and the test runner"
read_when: "Touching deployit backend routes/UI, CLI bootstrap/bump/preflight, or its tests"
sources:
  - path: plugins/deployit/tests/fakes/tailscale
    blob: e791bddad3f3d31a1e584d72f71075a4a5270547
  - path: plugins/deployit/tests/run-tests.sh
    blob: 5d017ec337d7a22a0616704396c2d233e1b32278
  - path: plugins/deployit/tests/test-backend-500-on-corrupt.sh
    blob: c1683f5c6233f47754ef702b8204def77f0f3815
  - path: plugins/deployit/tests/test-backend-appcast.sh
    blob: baaf806aa614d45a5b5693a52e8fa1176a88aa72
  - path: plugins/deployit/tests/test-backend-healthz.sh
    blob: 4e9022321aa470e7ff69c9a316a4addd2840309d
  - path: plugins/deployit/tests/test-backend-listing-groups-by-product.sh
    blob: 766abd7a54fbd937d227694560afcda42a98ebbd
  - path: plugins/deployit/tests/test-backend-listing.sh
    blob: 898e867d71e6737664a9ec49507fd0c4be730855
  - path: plugins/deployit/tests/test-backend-macos-download.sh
    blob: 73868f35fb2b3a69881091d18f7219687f5b5c53
  - path: plugins/deployit/tests/test-backend-nav-no-ptr.sh
    blob: 9123894849996cffeb4fa8de123df79bc9237c6b
  - path: plugins/deployit/tests/test-backend-per-build.sh
    blob: 40ee874e0c8b38e250605874eb95d14e1e6fa411
  - path: plugins/deployit/tests/test-backend-product-page.sh
    blob: 3e47ca29d7051c3bd270dafe705a11b6d7abfb15
  - path: plugins/deployit/tests/test-backend-refresh.sh
    blob: 8af6d863fac5ab4787f05f8773511f0dedea268a
  - path: plugins/deployit/tests/test-backend-static-assets.sh
    blob: 2a6a390c6fe8a1e708e1f90d404eee00918cef86
  - path: plugins/deployit/tests/test-backend-version-label.sh
    blob: 8ddf7d8821bcc8c4b87dc8bcb782ecb410d07311
  - path: plugins/deployit/tests/test-bootstrap-dirs.sh
    blob: fcb3b27daa351b0cba8db9cd480d2b35677662d1
references_modules: [plugins-deployit-bin, plugins-deployit-tests-chunk-2]
generator: cartographer/2
baseline: b4cedefaba8df96ee167877bf2ee9c3143ef0b08
---

# Module: plugins/deployit/tests (chunk 1)

## Purpose

First alphabetical half of deployit's test suite: the serial test runner, a tailscale fake, all
backend-route tests, and the CLI bootstrap test. Each test is self-contained — boot the real
production binary against a throwaway state root, assert on observable HTTP or filesystem behavior;
externals are faked binaries or `DEPLOYIT_*` env knobs, never in-process mocks. This chunk is the
primary regression net for every deployit backend HTTP route and the CLI bootstrap flow.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `run-tests.sh` | script | `plugins/deployit/tests/run-tests.sh:1` | Serially runs every `test-*.sh` beside it; `$1` filters by substring; exits 1 on failure, dumping `/tmp/deployit-test.log` |
| `tailscale` | fake executable | `plugins/deployit/tests/fakes/tailscale:1` | Injected via `DEPLOYIT_TAILSCALE_BIN`; answers `status --json` with DNSName `studio.tail-abc.ts.net.` for deterministic hostname assertions |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `check` | bash function | `plugins/deployit/tests/test-backend-static-assets.sh:27` | Asserts Content-Type + Cache-Control per PWA asset route via GET `-D -` (backend has no `do_HEAD`) |

## Relationships

- `plugins-deployit-tests-chunk-1.run-tests.sh -> plugins-deployit-tests-chunk-2.test-*.sh (calls)`
- `plugins-deployit-tests-chunk-1.test-backend-*.sh -> plugins-deployit-bin.deployit-backend (calls)`
- `plugins-deployit-tests-chunk-1.test-bootstrap-dirs.sh -> plugins-deployit-bin.deployit-cli (calls)`

## Type notes

- Every `test-backend-*.sh` boots the real backend with `--root <mktemp> --no-git-pull`.
- All backend tests seed `index/builds.json` and create a `_plugin_root` symlink before starting.
- Fixtures mirror production schema: `index/builds.json` entries plus `serve/<id>/_meta.json`.
- Pinned GET routes tested: `/deployit/`, `/deployit/p/<bundle>/<platform>/`, `/deployit/<build-id>/`, `_healthz`.
- Pinned GET routes tested: `/deployit/app.js`, `/deployit/app.css`, `/deployit/*.webmanifest`, static icons.
- Sparkle appcast route tested: `/deployit/p/<bundle>/macos/appcast.xml` — `plugins/deployit/tests/test-backend-appcast.sh:93`.
- Appcast filtering: unsigned builds, archived builds, and iOS builds excluded — `plugins/deployit/tests/test-backend-appcast.sh:120-126`.
- Appcast must be well-formed XML; test uses `python3 -c xml.dom.minidom` — `plugins/deployit/tests/test-backend-appcast.sh:129`.
- Pinned POST route: `/deployit/_internal/refresh` — `plugins/deployit/tests/test-backend-refresh.sh:18`.
- Nav-bar Refresh button (`id="refresh"`) present; `id="ptr"` absent — `plugins/deployit/tests/test-backend-nav-no-ptr.sh:57-64`.
- Version label rule: `semver_version` wins when set, else `build_number` — `plugins/deployit/tests/test-backend-version-label.sh:71-76`.
- macOS landing shows Gatekeeper note; must not show iOS Device Management note — `plugins/deployit/tests/test-backend-macos-download.sh:73-75`.
- 500 on corrupt `_meta.json` yields `{"ok":false}` + `"internal_error"` — `plugins/deployit/tests/test-backend-500-on-corrupt.sh:22-24`.
- Path traversal in build paths must 404 — `plugins/deployit/tests/test-backend-per-build.sh:58`.
- `DEPLOYIT_STATE_DIR` redirects all CLI state — `plugins/deployit/tests/test-bootstrap-dirs.sh:8`.
- `DEPLOYIT_SKIP_*` env vars disable launchd/serve/clone side-effects — `plugins/deployit/tests/test-bootstrap-dirs.sh:11-13`.
- Bootstrap idempotency: second run must also return `ok:true` — `plugins/deployit/tests/test-bootstrap-dirs.sh:36-37`.

## External deps

- curl — every backend assertion is an HTTP request against 127.0.0.1
- python3 stdlib (xml.dom.minidom) — appcast XML well-formedness check

## Gotchas

- PORT 18733 double-booked: `plugins/deployit/tests/test-backend-500-on-corrupt.sh:14` and `plugins/deployit/tests/test-backend-static-assets.sh:16`; safe only when run serially.
- `curl -I` returns 501 (no `do_HEAD`); backend tests must use GET with `-D -` — `plugins/deployit/tests/test-backend-static-assets.sh:30`.
- Cleanup gap: `plugins/deployit/tests/test-backend-static-assets.sh:20` traps kill but never `rm -rf $ROOT`.
- `run-tests.sh` discovery glob is `test-*.sh` — `plugins/deployit/tests/run-tests.sh:14`; `verify-live.sh` and fakes are not included.
