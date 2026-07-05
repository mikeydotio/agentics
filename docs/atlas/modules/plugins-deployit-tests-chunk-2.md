---
module: "plugins/deployit/tests (chunk 2)"
summary: "Deployit CLI tests (bootstrap, redeploy, gc, rm, preflight, bump, macOS staging) plus the backend version-label test."
read_when: "Changing deployit CLI subcommands, macOS staging/release, or version-label rendering"
sources:
  - path: plugins/deployit/tests/test-backend-version-label.sh
    blob: fa42caacb9b717115e36d41d62fcd82e7c5920b7
  - path: plugins/deployit/tests/test-bootstrap-dirs.sh
    blob: fcb3b27daa351b0cba8db9cd480d2b35677662d1
  - path: plugins/deployit/tests/test-cli-archive-build-number.sh
    blob: 300b23be4b25228e0c39a522166c692fabe8b911
  - path: plugins/deployit/tests/test-cli-bump.sh
    blob: 04836f17b13c459010bcf9394f9fb1290831ceec
  - path: plugins/deployit/tests/test-cli-config-sparkle.sh
    blob: 6f8ac4ff1172a8da5127f4dc3f8d64484d12fe88
  - path: plugins/deployit/tests/test-cli-deploy-autoprune.sh
    blob: 8f43eb9f58e1c4ad048e566c70e0313ae401e004
  - path: plugins/deployit/tests/test-cli-deploy-release-wiring.sh
    blob: a06013b6b9fdfb84de6568994835065c20f0490b
  - path: plugins/deployit/tests/test-cli-preflight.sh
    blob: 894d8c16d5cd39f2d0f18f40f0aab8527c185e9b
  - path: plugins/deployit/tests/test-cli-redeploy.sh
    blob: 5cc4141d1c5dc1700865ec366d1304c672bd9817
  - path: plugins/deployit/tests/test-cli-rm.sh
    blob: dfac34f95d15aa78c898783643ccdc0c990f1bbf
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
references_modules: [plugins-atlas-bin-chunk-1, plugins-deployit-bin, plugins-semver-misc]
generator: cartographer/4
baseline: 50c998d53e2ed58951ac5f794afd32bfa729f658
---

# Module: plugins/deployit/tests (chunk 2)

## Purpose

This chunk pins deployit-cli's state-mutating subcommands — bootstrap, bump, preflight, redeploy, rm, gc, and deploy's macOS staging/release path — plus the private functions those subcommands lean on (_stage_macos, _publish_github_release, _read_archive_build_number, _read_config, _append_to_index, _derive_metadata), most exercised in-process via importlib.machinery.SourceFileLoader rather than only through the CLI's JSON stdout. It also carries the backend's version-label rendering test and a single-app Xcode metadata-extraction fixture. Losing this chunk removes the only regression coverage for prune scoping, Sparkle signing degradation, redeploy's legacy-plist repair, and the semver-driven bump/preflight decision — the riskiest, most state-mutating parts of deployit.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `make_app` | def | `plugins/deployit/tests/test-cli-deploy-release-wiring.sh:32` | Creates a minimal macOS .app bundle (executable + Info.plist CFBundleShortVersionString) for staging/publish fixtures. |
| `make_app` | def | `plugins/deployit/tests/test-cli-stage-macos-sparkle.sh:32` | Creates a fresh minimal Lillist.app bundle so each Sparkle staging case runs against an unmodified fixture. |
| `meta_for` | def | `plugins/deployit/tests/test-cli-stage-macos-sparkle.sh:39` | Returns a canonical _meta.json-shaped dict for build_id, reused across the enabled/disabled Sparkle staging cases. |
| `mk` | def | `plugins/deployit/tests/test-cli-deploy-autoprune.sh:37` | Builds a serve/<id>/ fixture dir and returns a matching builds.json entry dict for seeding prune-scope cases. |
| `mk` | def | `plugins/deployit/tests/test-cli-rm.sh:45` | Builds an index entry (and a serve/<id>/ fixture if local=True) to seed local/foreign/cross-platform rm-scoping cases. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

- `plugins-deployit-tests-chunk-2.make_app -> plugins-atlas-bin-chunk-1.read_text (calls)`
- `plugins-deployit-tests-chunk-2.make_app -> plugins-deployit-bin._append_to_index (calls)`
- `plugins-deployit-tests-chunk-2.make_app -> plugins-deployit-bin._publish_github_release (calls)`
- `plugins-deployit-tests-chunk-2.make_app -> plugins-deployit-bin._refresh_local_backend (calls)`
- `plugins-deployit-tests-chunk-2.make_app -> plugins-deployit-bin._stage_macos (calls)`
- `plugins-deployit-tests-chunk-2.make_app -> plugins-semver-misc.get (calls)`
- `plugins-deployit-tests-chunk-2.meta_for -> plugins-atlas-bin-chunk-1.read_text (calls)`
- `plugins-deployit-tests-chunk-2.meta_for -> plugins-deployit-bin._append_to_index (calls)`
- `plugins-deployit-tests-chunk-2.meta_for -> plugins-deployit-bin._stage_macos (calls)`
- `plugins-deployit-tests-chunk-2.meta_for -> plugins-semver-misc.get (calls)`
- `plugins-deployit-tests-chunk-2.mk -> plugins-deployit-bin._append_to_index (calls)`

## Type notes

- Prune invariant: `_append_to_index` prunes to a per-product cap within `(bundle_id, platform, origin_base_url)`; other platforms/origins of the same bundle survive — plugins/deployit/tests/test-cli-deploy-autoprune.sh:2-5.
- `rm` scoping: only builds whose `origin_base_url` matches the local config's `base_url` may be removed, even by exact `--build` id — plugins/deployit/tests/test-cli-rm.sh:5-6.
- Release-publish ordering: `_publish_github_release` must run after `_append_to_index` and `_refresh_local_backend` so a failed deploy never orphans a public release — plugins/deployit/tests/test-cli-deploy-release-wiring.sh:5-7.
- Sparkle metadata propagation: `sparkle.*` fields written by `_stage_macos` into `_meta.json` must survive the pop/add transform applied before `_append_to_index` — plugins/deployit/tests/test-cli-stage-macos-sparkle.sh:69-77.
- Archive layout duality: `_read_archive_build_number` must resolve `CFBundleVersion` from a flat `.app/Info.plist` (iOS/visionOS) or a nested `.app/Contents/Info.plist` (macOS) — plugins/deployit/tests/test-cli-archive-build-number.sh:2-6.
- `_read_config`'s `[macos.sparkle]` sub-table degrades to `enabled: False` when the section is absent, on both the tomllib and regex-fallback parse paths — plugins/deployit/tests/test-cli-config-sparkle.sh:2-6.
- `redeploy` plist repair: a legacy launchd plist pinning a cache-hash script path is rewritten to the stable `<state>/bin/deployit-backend` path, and is idempotent on re-run — plugins/deployit/tests/test-cli-redeploy.sh:54-59.

## External deps

- importlib.machinery — imported
- importlib.util — imported
- json — imported

## Gotchas

- test-cli-bump.sh SKIPs when semver-cli isn't found at ../semver/bin/semver-cli — plugins/deployit/tests/test-cli-bump.sh:10-11.
- test-cli-archive-build-number.sh SKIPs on non-macOS when /usr/libexec/PlistBuddy is absent — plugins/deployit/tests/test-cli-archive-build-number.sh:11-12.
- test-cli-deploy-release-wiring.sh and the stage-macos-*.sh tests SKIP unless hdiutil/ditto (and PlistBuddy) are present — plugins/deployit/tests/test-cli-deploy-release-wiring.sh:12-14, plugins/deployit/tests/test-cli-stage-macos-sparkle.sh:12-13.
- test-cli-rm.sh polls the bare remote's log rather than reading it once, because a local push's post-receive settle can briefly lag a fresh reader even though the push already landed — plugins/deployit/tests/test-cli-rm.sh:84-93.
- test-cli-deploy-release-wiring.sh pins publish-after-append/refresh ordering by grepping the CLI's own source text, not by asserting at runtime — plugins/deployit/tests/test-cli-deploy-release-wiring.sh:85-88.
- test-cli-version.sh hardcodes the literal "0.1.0"; it must be updated whenever the CLI's --version output changes — plugins/deployit/tests/test-cli-version.sh:7.
