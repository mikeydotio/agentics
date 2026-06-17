---
module: "plugins/deployit/tests (chunk 2)"
summary: "CLI-focused tests pinning deployit redeploy, gc, metadata extraction, macOS staging, and the live-deploy gate"
read_when: "Changing deployit redeploy, gc, metadata extraction, or verifying a live deployment"
sources:
  - path: plugins/deployit/tests/test-cli-archive-build-number.sh
    blob: 300b23be4b25228e0c39a522166c692fabe8b911
  - path: plugins/deployit/tests/test-cli-bump.sh
    blob: 04836f17b13c459010bcf9394f9fb1290831ceec
  - path: plugins/deployit/tests/test-cli-config-sparkle.sh
    blob: 6f8ac4ff1172a8da5127f4dc3f8d64484d12fe88
  - path: plugins/deployit/tests/test-cli-deploy-autoprune.sh
    blob: 8f43eb9f58e1c4ad048e566c70e0313ae401e004
  - path: plugins/deployit/tests/test-cli-preflight.sh
    blob: 894d8c16d5cd39f2d0f18f40f0aab8527c185e9b
  - path: plugins/deployit/tests/test-cli-redeploy.sh
    blob: 5cc4141d1c5dc1700865ec366d1304c672bd9817
  - path: plugins/deployit/tests/test-cli-stage-macos-no-sparkle-tools.sh
    blob: e5ac361f4179b34d9833f7daa4f7a641a8afd775
  - path: plugins/deployit/tests/test-cli-stage-macos-sparkle.sh
    blob: 991934e1ae5673233ed810f458a7aa7629e0c4ca
  - path: plugins/deployit/tests/test-cli-version.sh
    blob: d7a1daaa409feb77dbb59b51a4c1f76b58050f79
  - path: plugins/deployit/tests/test-gc.sh
    blob: be01b59bafa19e9c5bda91c29d3ccd6101f9ad88
  - path: plugins/deployit/tests/test-metadata-single-app.sh
    blob: 1f36ebce4b6cf9363f3e6045fb7afced5dcd2ef0
  - path: plugins/deployit/tests/test-metadata.sh
    blob: 5c49e2f4a48015c86de20068bd861f6edde9103c
  - path: plugins/deployit/tests/verify-live.sh
    blob: ac91a62908f8dc436f6a358bf5dbc11d2c31163b
references_modules: [plugins-deployit-bin]
generator: cartographer/2
baseline: b4cedefaba8df96ee167877bf2ee9c3143ef0b08
---

# Module: plugins/deployit/tests (chunk 2)

## Purpose

Second partition of deployit's test suite, covering CLI operations that require
deeper fixture setup: redeploy symlink rewiring and legacy plist repair, gc archiving
and prune scoping, metadata extraction for two xcodeproj layouts, macOS Sparkle staging
(both artifacts + signature propagation), semver bump folding, and the live-backend
smoke check. Each test drives the real `deployit-cli` binary — externals replaced only
via `DEPLOYIT_*` env knobs and executable stubs. `verify-live.sh` is the sole test
meant for post-deploy assertion against a running daemon.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `test-cli-archive-build-number.sh` | script | `plugins/deployit/tests/test-cli-archive-build-number.sh:1` | Pins `_read_archive_build_number` for iOS (flat) and macOS (Contents/) xcarchive layouts; asserts SystemExit when no Info.plist |
| `test-cli-bump.sh` | script | `plugins/deployit/tests/test-cli-bump.sh:1` | Verifies `deployit bump` increments version, folds dirty files into release commit; graceful ok:false when semver-cli absent; SKIPs if not found |
| `test-cli-config-sparkle.sh` | script | `plugins/deployit/tests/test-cli-config-sparkle.sh:1` | Pins `_read_config` Sparkle section under tomllib (≥3.11) and regex fallback (<3.11); safe defaults when section absent |
| `test-cli-deploy-autoprune.sh` | script | `plugins/deployit/tests/test-cli-deploy-autoprune.sh:1` | Calls `_append_to_index` directly; verifies prune caps at 10 per (bundle_id, platform, origin_base_url), removes oldest from index + disk |
| `test-cli-preflight.sh` | script | `plugins/deployit/tests/test-cli-preflight.sh:1` | Four bump-decision cases (semver inactive / no prior / same version / different version) via pre-seeded index, no xcodebuild |
| `test-cli-redeploy.sh` | script | `plugins/deployit/tests/test-cli-redeploy.sh:1` | Proves redeploy retargets stable symlinks, rewrites legacy hash-pinned plists, is idempotent, rejects source missing `bin/deployit-backend` |
| `test-cli-stage-macos-no-sparkle-tools.sh` | script | `plugins/deployit/tests/test-cli-stage-macos-no-sparkle-tools.sh:1` | Graceful degradation when Sparkle signing fails: dmg produced, zip discarded, no `sparkle` key, warning on stderr |
| `test-cli-stage-macos-sparkle.sh` | script | `plugins/deployit/tests/test-cli-stage-macos-sparkle.sh:1` | Enabled: .dmg + .zip + EdDSA metadata in _meta.json; disabled: .dmg only; real hdiutil/ditto, stubbed signer; SKIPs non-macOS |
| `test-cli-version.sh` | script | `plugins/deployit/tests/test-cli-version.sh:1` | Sanity: `deployit-cli --version` returns `{"ok": true, "version": "0.1.0"}` |
| `test-gc.sh` | script | `plugins/deployit/tests/test-gc.sh:1` | Proves `gc --keep N` archives oldest beyond budget, removes serve dirs, is idempotent, and bare `gc` returns ok:false JSON |
| `test-metadata-single-app.sh` | script | `plugins/deployit/tests/test-metadata-single-app.sh:1` | Pins `_derive_metadata` for root `.xcodeproj` + `./project.yml` with unquoted PRODUCT_BUNDLE_IDENTIFIER |
| `test-metadata.sh` | script | `plugins/deployit/tests/test-metadata.sh:1` | Pins `_derive_metadata` for xcworkspace + `Apps/<target>/project.yml` monorepo layout |
| `verify-live.sh` | script | `plugins/deployit/tests/verify-live.sh:1` | Post-deploy smoke check: healthz, static assets, listing markers, product row count vs index, product page back-link; exits 1 on any failure |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `mk` | bash function | `plugins/deployit/tests/test-cli-deploy-autoprune.sh:37` | Builds a complete index entry + `serve/<id>/` fixture; all 12 seed builds go through it, expressing the prune scope invariant compactly |
| `make_app` | python function | `plugins/deployit/tests/test-cli-stage-macos-sparkle.sh:32` | Creates a minimal macOS .app bundle for each Sparkle test case; real hdiutil runs against it |
| `meta_for` | python function | `plugins/deployit/tests/test-cli-stage-macos-sparkle.sh:39` | Canonical `_meta.json`-shaped dict reused across both staging cases; separate from `make_app` so bundles can be re-created independently |
| `check_static` | bash function | `plugins/deployit/tests/verify-live.sh:54` | Asserts a static asset returns 200 with the expected Content-Type prefix; covers app.css and app.js |
| `mk_build` | bash function | `plugins/deployit/tests/test-gc.sh:26` | Emits both the `serve/<id>` dir and the `builds.json` entry, keeping gc ordering tests consistent |

## Relationships

- `plugins-deployit-tests-chunk-2.test-cli-archive-build-number.sh -> plugins-deployit-bin._read_archive_build_number (calls)`
- `plugins-deployit-tests-chunk-2.test-cli-bump.sh -> plugins-deployit-bin.deployit-cli (calls)`
- `plugins-deployit-tests-chunk-2.test-cli-config-sparkle.sh -> plugins-deployit-bin._read_config (calls)`
- `plugins-deployit-tests-chunk-2.test-cli-deploy-autoprune.sh -> plugins-deployit-bin._append_to_index (calls)`
- `plugins-deployit-tests-chunk-2.test-cli-preflight.sh -> plugins-deployit-bin.deployit-cli (calls)`
- `plugins-deployit-tests-chunk-2.test-cli-redeploy.sh -> plugins-deployit-bin.deployit-cli (calls)`
- `plugins-deployit-tests-chunk-2.test-cli-stage-macos-no-sparkle-tools.sh -> plugins-deployit-bin._stage_macos (calls)`
- `plugins-deployit-tests-chunk-2.test-cli-stage-macos-sparkle.sh -> plugins-deployit-bin._stage_macos (calls)`
- `plugins-deployit-tests-chunk-2.test-cli-version.sh -> plugins-deployit-bin.deployit-cli (calls)`
- `plugins-deployit-tests-chunk-2.test-gc.sh -> plugins-deployit-bin.deployit-cli (calls)`
- `plugins-deployit-tests-chunk-2.test-metadata.sh -> plugins-deployit-bin.deployit-cli (calls)`
- `plugins-deployit-tests-chunk-2.test-metadata-single-app.sh -> plugins-deployit-bin.deployit-cli (calls)`
- `plugins-deployit-tests-chunk-2.verify-live.sh -> plugins-deployit-bin.deployit-backend (calls)`

## Type notes

- Five tests load `deployit-cli` as a Python module via `importlib.machinery.SourceFileLoader` to call private functions directly without subprocess overhead: `plugins/deployit/tests/test-cli-archive-build-number.sh:39`, `plugins/deployit/tests/test-cli-config-sparkle.sh:50`, `plugins/deployit/tests/test-cli-deploy-autoprune.sh:86`, `plugins/deployit/tests/test-cli-stage-macos-sparkle.sh:24`, `plugins/deployit/tests/test-cli-stage-macos-no-sparkle-tools.sh:36`.
- `DEPLOYIT_SKIP_SPARKLE_SIGN=1` stubs the EdDSA signer; pinned stub signature is `TEST-ED-SIGNATURE-DO-NOT-SHIP==`: `plugins/deployit/tests/test-cli-stage-macos-sparkle.sh:60`.
- `DEPLOYIT_SPARKLE_SIGN_UPDATE` overrides the sign_update binary; set to a failing stub to test graceful degradation: `plugins/deployit/tests/test-cli-stage-macos-no-sparkle-tools.sh:28`.
- Redeploy uses the chunk-1-owned `fakes/tailscale` and `fakes/true` via `DEPLOYIT_TAILSCALE_BIN` / `DEPLOYIT_LAUNCHCTL_BIN`: `plugins/deployit/tests/test-cli-redeploy.sh:16-17`.
- Legacy plist repair: a plist whose ProgramArguments contains a cache-hash path is rewritten to `<state>/bin/deployit-backend`; idempotence verified by checking `plist_rewritten: false` on re-run: `plugins/deployit/tests/test-cli-redeploy.sh:77-99`.
- Prune scope is `(bundle_id, platform, origin_base_url)` — cross-origin and cross-platform builds from the same bundle survive: `plugins/deployit/tests/test-cli-deploy-autoprune.sh:113-115`.
- macOS archive dual-path test was born from a latent bug in the first real Lillist macOS deploy where only the iOS path was checked: `plugins/deployit/tests/test-cli-archive-build-number.sh:4-6`.
- `verify-live.sh` omits `-e` so all checks run before reporting; exits 1 iff FAIL > 0: `plugins/deployit/tests/verify-live.sh:11`, `plugins/deployit/tests/verify-live.sh:136`.
- Port resolution: `--port` flag, else parsed from `$DEPLOYIT_STATE_DIR/config.toml` via tomllib/tomli: `plugins/deployit/tests/verify-live.sh:24-37`.

## External deps

- hdiutil, ditto — macOS staging tests; tests SKIP on non-macOS when absent
- PlistBuddy (`/usr/libexec/PlistBuddy`) — archive build-number test; SKIPs when absent
- curl — all `verify-live.sh` HTTP assertions
- git — repo fixtures for bump and preflight tests; metadata tests init throwaway repos
- python3 stdlib (importlib, json, pathlib) — inline fixture builders and function-level harnesses
- tomllib (≥3.11) / tomli (<3.11) — `verify-live.sh` port extraction from config.toml

## Gotchas

- hdiutil/ditto tests skip silently on non-macOS: `plugins/deployit/tests/test-cli-stage-macos-sparkle.sh:12`.
- `test-cli-bump.sh` SKIPs when semver-cli absent at `../semver/bin/semver-cli`: `plugins/deployit/tests/test-cli-bump.sh:10`.
- `verify-live.sh` checks for absence of `id="ptr"` (pull-to-refresh removed) as a new-code marker: `plugins/deployit/tests/verify-live.sh:82-85`.
- `verify-live.sh` is NOT in `run-tests.sh`'s `test-*.sh` glob; invoke it separately after deploy: `plugins/deployit/tests/verify-live.sh:1`.
- CLI version bumps must update the pinned literal in test-cli-version.sh: `plugins/deployit/tests/test-cli-version.sh:7`.
