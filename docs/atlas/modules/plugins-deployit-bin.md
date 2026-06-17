---
module: plugins/deployit/bin
summary: "Deployit's executable core — bash router, build/publish CLI, OTA install-page backend"
read_when: "Changing deployit subcommands, the deploy/publish flow, or backend endpoints"
sources:
  - path: plugins/deployit/bin/deployit-backend
    blob: 998a36c278063066f887da95ef6d9af0fc888025
  - path: plugins/deployit/bin/deployit-cli
    blob: e5fe7efc4cc4e283479305422cccc69309ffb058
  - path: plugins/deployit/bin/deployit-router.sh
    blob: 344168329e019299a535c6e7c327e726f0cb5d03
references_modules: [plugins-deployit-assets, plugins-deployit-tests-chunk-2, plugins-semver-misc]
generator: cartographer/2
baseline: b4cedefaba8df96ee167877bf2ee9c3143ef0b08
---

# Module: plugins/deployit/bin

## Purpose

Executable core of deployit: a bash router, a JSON build/publish CLI, and an HTTP install backend.
The CLI archives/exports Xcode builds, stages OTA artifacts, and publishes to a shared git index.
The backend serves install pages from that index; stable symlinks keep the daemon upgrade-safe.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `Handler` | class | `plugins/deployit/bin/deployit-backend:338` | Routes all `/deployit/*` HTTP: pages, artifacts, health, refresh |
| `cmd_bootstrap` | def | `plugins/deployit/bin/deployit-cli:836` | One-time setup: dirs, symlinks, config, index clone, serve, launchd |
| `cmd_bump` | def | `plugins/deployit/bin/deployit-cli:1024` | Non-interactive semver bump via semver-cli; includes dirty tree |
| `cmd_deploy` | def | `plugins/deployit/bin/deployit-cli:859` | Archive → export → stage → publish; prints install/listing URLs |
| `cmd_gc` | def | `plugins/deployit/bin/deployit-cli:1128` | Archives old local-origin builds; deletes their serve dirs |
| `cmd_list` | def | `plugins/deployit/bin/deployit-cli:1107` | Lists indexed builds; platform/project filters |
| `cmd_preflight` | def | `plugins/deployit/bin/deployit-cli:962` | Read-only: is a semver bump required; emits bump candidates |
| `cmd_redeploy` | def | `plugins/deployit/bin/deployit-cli:1214` | Re-points symlinks (`--source` = dev dir), restarts, verifies live |
| `cmd_status` | def | `plugins/deployit/bin/deployit-cli:1073` | Backend health + recent local deploys |
| `cmd_url` | def | `plugins/deployit/bin/deployit-cli:1066` | Prints this machine's listing URL |
| `deployit-router.sh` | script | `plugins/deployit/bin/deployit-router.sh:17` | Skill entry: execs the CLI with `--plugin-root` |
| `main` | def | `plugins/deployit/bin/deployit-backend:474` | Backend entrypoint: `ThreadingHTTPServer` on `127.0.0.1` |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `_append_to_index` | def | `plugins/deployit/bin/deployit-cli:784` | Publish: pull --rebase, prepend, prune, commit, push; 3-attempt conflict retry |
| `_derive_metadata` | def | `plugins/deployit/bin/deployit-cli:271` | Detects both Xcode layouts (workspace+Apps/ vs single project); feeds deploy + preflight |
| `_find_semver_cli` | def | `plugins/deployit/bin/deployit-cli:383` | Env override → sibling marketplace plugin → `~/.claude` glob |
| `_install_launchd` | def | `plugins/deployit/bin/deployit-cli:188` | Writes/loads the agent plist; called by both bootstrap and redeploy |
| `_prune_old_builds` | def | `plugins/deployit/bin/deployit-cli:757` | Keeps `PRUNE_KEEP_PER_PRODUCT` (10) per product per origin |
| `_semver_active_version` | def | `plugins/deployit/bin/deployit-cli:342` | Semver gate: `tracking: true` config + readable `VERSION` in target project |
| `_stage_ios_or_visionos` | def | `plugins/deployit/bin/deployit-cli:551` | Stages IPA; renders itms-services `manifest.plist` + `_meta.json` |
| `_stage_macos` | def | `plugins/deployit/bin/deployit-cli:686` | Wraps .app in .dmg; optional notarize/staple; optional Sparkle EdDSA zip |
| `_sync_plugin_root` | def | `plugins/deployit/bin/deployit-cli:116` | Atomic stable symlinks; upgrades move links, never the launchd plist |

## Relationships

- `plugins-deployit-bin.deployit-router.sh -> plugins-deployit-bin.deployit-cli (calls)`
- `plugins-deployit-bin.cmd_bump -> plugins-semver-misc.semver-cli (calls)`
- `plugins-deployit-bin.cmd_redeploy -> plugins-deployit-tests-chunk-2.verify-live.sh (calls)`
- `plugins-deployit-bin.deployit-cli -> plugins-deployit-assets.ExportOptions.ios.plist (reads)`
- `plugins-deployit-bin.deployit-cli -> plugins-deployit-assets.manifest.template.plist (reads)`
- `plugins-deployit-bin._render_listing -> plugins-deployit-assets.listing.template.html (reads)`
- `plugins-deployit-bin.deployit-backend -> plugins-deployit-assets.index.template.html (reads)`

## Type notes

- Both Python programs are stdlib-only by design (`plugins/deployit/bin/deployit-backend:11`).
- CLI emits one JSON object per run, even argparse errors (`plugins/deployit/bin/deployit-cli:48`).
- `builds.json` is newest-first; lookups rely on it (`plugins/deployit/bin/deployit-cli:436`).
- Index = clone of `mikeydotio/deployit-index` (`plugins/deployit/bin/deployit-cli:143`).
- Semver reads are artifact-based, never imports (`plugins/deployit/bin/deployit-cli:342`).
- Tests stub side effects via `DEPLOYIT_SKIP_*` env vars (`plugins/deployit/bin/deployit-cli:190`).
- Backend binds `127.0.0.1` only (`plugins/deployit/bin/deployit-backend:497`).
- Serving gates: `_BUILD_ID_RE`, no subpaths/dotfiles (`plugins/deployit/bin/deployit-backend:427`).
- `_launchd_plist` (`plugins/deployit/bin/deployit-cli:158`) generates a plist STRING embedding the backend path via stable symlinks; launchd later launches the backend process — there is no direct call between them.

## External deps

- xcodebuild — archive/export; `PlistBuddy` reads `CFBundleVersion` from the archive
- tailscale CLI — `status --json` (derive base URL), `serve --bg` (HTTPS front)
- launchctl — bootstrap/bootout/kickstart of `com.mikeydotio.deployit.backend`
- git — index clone/pull/commit/push; push rewrites SSH→HTTPS via `insteadOf`
- hdiutil, `xcrun notarytool`/`stapler` — dmg packaging, optional notarization
- ditto — Sparkle zip creation (preserves bundle symlinks and resource forks)

## Gotchas

- Deploy archives build `-configuration Debug` (`plugins/deployit/bin/deployit-cli:497`).
- Redeploy rewrites legacy hash-pinned plists (`plugins/deployit/bin/deployit-cli:1235`).
- Backend won't recreate `_plugin_root` onto itself (`plugins/deployit/bin/deployit-backend:491`).
- Listing GETs trigger `git pull` synchronously (`plugins/deployit/bin/deployit-backend:386`).
