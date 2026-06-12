---
module: plugins/deployit/bin
summary: "Deployit's executable core — bash router, build/publish CLI, OTA install-page backend"
read_when: "Changing deployit subcommands, the deploy/publish flow, or backend endpoints"
sources:
  - path: plugins/deployit/bin/deployit-backend
    blob: eddad198093da22cd99a51e30f9ed3de94ec9a8e
  - path: plugins/deployit/bin/deployit-cli
    blob: 9f14c2bf9e45bec688d28c13e44d5d3a6a5138c1
  - path: plugins/deployit/bin/deployit-router.sh
    blob: 344168329e019299a535c6e7c327e726f0cb5d03
references_modules: [plugins-deployit-assets, plugins-deployit-tests-chunk-2, plugins-semver-misc]
generator: cartographer/1
baseline: b1e1f9d1dbced518c625c38bb87814de5af1a1b7
verified: true
---

# Module: plugins/deployit/bin

## Purpose

Executable core of deployit: a bash router, a JSON build/publish CLI, and an HTTP install backend.
The CLI archives/exports Xcode builds, stages OTA artifacts, and publishes to a shared git index.
The backend serves install pages from that index; stable symlinks keep the daemon upgrade-safe.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `Handler` | class | `plugins/deployit/bin/deployit-backend:236` | Routes all `/deployit/*` HTTP: pages, artifacts, health, refresh |
| `cmd_bootstrap` | def | `plugins/deployit/bin/deployit-cli:700` | One-time setup: dirs, symlinks, config, index clone, serve, launchd |
| `cmd_bump` | def | `plugins/deployit/bin/deployit-cli:872` | Non-interactive semver bump via semver-cli; includes dirty tree |
| `cmd_deploy` | def | `plugins/deployit/bin/deployit-cli:723` | Archive → export → stage → publish; prints install/listing URLs |
| `cmd_gc` | def | `plugins/deployit/bin/deployit-cli:976` | Archives old local-origin builds; deletes their serve dirs |
| `cmd_list` | def | `plugins/deployit/bin/deployit-cli:955` | Lists indexed builds; platform/project filters |
| `cmd_preflight` | def | `plugins/deployit/bin/deployit-cli:810` | Read-only: is a semver bump required; emits bump candidates |
| `cmd_redeploy` | def | `plugins/deployit/bin/deployit-cli:1062` | Re-points symlinks (`--source` = dev dir), restarts, verifies live |
| `cmd_status` | def | `plugins/deployit/bin/deployit-cli:921` | Backend health + recent local deploys |
| `cmd_url` | def | `plugins/deployit/bin/deployit-cli:914` | Prints this machine's listing URL |
| `deployit-router.sh` | script | `plugins/deployit/bin/deployit-router.sh:17` | Skill entry: execs the CLI with `--plugin-root` |
| `main` | def | `plugins/deployit/bin/deployit-backend:362` | Backend entrypoint: `ThreadingHTTPServer` on `127.0.0.1` |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `_derive_metadata` | def | `plugins/deployit/bin/deployit-cli:271` | Detects both Xcode layouts (workspace+Apps/ vs single project); feeds deploy + preflight |
| `_append_to_index` | def | `plugins/deployit/bin/deployit-cli:648` | Publish: pull --rebase, prepend, prune, commit, push; 3-attempt conflict retry |
| `_sync_plugin_root` | def | `plugins/deployit/bin/deployit-cli:116` | Atomic stable symlinks; upgrades move links, never the launchd plist |
| `_install_launchd` | def | `plugins/deployit/bin/deployit-cli:188` | Writes/loads the agent plist; called by both bootstrap and redeploy |
| `_semver_active_version` | def | `plugins/deployit/bin/deployit-cli:342` | Semver gate: `tracking: true` config + readable `VERSION` in target project |
| `_find_semver_cli` | def | `plugins/deployit/bin/deployit-cli:383` | Env override → sibling marketplace plugin → `~/.claude` glob |
| `_stage_ios_or_visionos` | def | `plugins/deployit/bin/deployit-cli:521` | Stages IPA; renders itms-services `manifest.plist` + `_meta.json` |
| `_prune_old_builds` | def | `plugins/deployit/bin/deployit-cli:621` | Keeps `PRUNE_KEEP_PER_PRODUCT` (10) per product per origin |

## Relationships

- `plugins-deployit-bin.deployit-router.sh -> plugins-deployit-bin.deployit-cli (calls)`
- `plugins-deployit-bin._launchd_plist -> plugins-deployit-bin.deployit-backend (calls)`
- `plugins-deployit-bin.cmd_bump -> plugins-semver-misc.semver-cli (calls)`
- `plugins-deployit-bin.cmd_redeploy -> plugins-deployit-tests-chunk-2.verify-live.sh (calls)`
- `plugins-deployit-bin.deployit-cli -> plugins-deployit-assets.ExportOptions.ios.plist (reads)`
- `plugins-deployit-bin.deployit-cli -> plugins-deployit-assets.manifest.template.plist (reads)`
- `plugins-deployit-bin._render_listing -> plugins-deployit-assets.listing.template.html (reads)`
- `plugins-deployit-bin.deployit-backend -> plugins-deployit-assets.index.template.html (reads)`

## Type notes

- Both Python programs are stdlib-only by design (`plugins/deployit/bin/deployit-backend:11`).
- CLI emits one JSON object per run, even argparse errors (`plugins/deployit/bin/deployit-cli:48`).
- `builds.json` is newest-first; lookups rely on it (`plugins/deployit/bin/deployit-cli:434`).
- Index = clone of `mikeydotio/deployit-index` (`plugins/deployit/bin/deployit-cli:143`).
- Semver reads are artifact-based, never imports (`plugins/deployit/bin/deployit-cli:342`).
- Tests stub side effects via `DEPLOYIT_SKIP_*` env vars (`plugins/deployit/bin/deployit-cli:190`).
- Backend binds `127.0.0.1` only (`plugins/deployit/bin/deployit-backend:385`).
- Serving gates: `_BUILD_ID_RE`, no subpaths/dotfiles (`plugins/deployit/bin/deployit-backend:328`).

## External deps

- xcodebuild — archive/export; `PlistBuddy` reads `CFBundleVersion` from the archive
- tailscale CLI — `status --json` (derive base URL), `serve --bg` (HTTPS front)
- launchctl — bootstrap/bootout/kickstart of `com.mikeydotio.deployit.backend`
- git — index clone/pull/commit/push; push rewrites SSH→HTTPS via `insteadOf`
- hdiutil, `xcrun notarytool`/`stapler` — dmg packaging, optional notarization

## Gotchas

- Deploy archives build `-configuration Debug` (`plugins/deployit/bin/deployit-cli:483`).
- Redeploy rewrites legacy hash-pinned plists (`plugins/deployit/bin/deployit-cli:1019`).
- Backend won't recreate `_plugin_root` onto itself (`plugins/deployit/bin/deployit-backend:380`).
- Listing GETs `git pull` synchronously (`plugins/deployit/bin/deployit-backend:284`).
