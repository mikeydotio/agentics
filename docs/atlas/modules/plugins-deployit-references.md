---
module: plugins/deployit/references
summary: "Per-concern procedure docs behind /deployit — setup, platform deploys, proxy, semver bump guard, recovery"
read_when: "Changing deployit deploy/bootstrap/proxy/semver behavior or debugging install failures"
sources:
  - path: plugins/deployit/references/bootstrap.md
    blob: 24850fe5b053d9925a7af47513cfc2ac04033f93
  - path: plugins/deployit/references/ios.md
    blob: 59175850b662bbf27b81972fc0ee97cfbe31acb9
  - path: plugins/deployit/references/macos.md
    blob: b2d5da0c1051ce2fddae6b2f1b630fc5dce9a3c3
  - path: plugins/deployit/references/semver.md
    blob: 6bfc5d8f26e34851b97f77d4236e88fe8be273d6
  - path: plugins/deployit/references/tailscale-serve.md
    blob: 92267a1597530c980bfee1916f83a818dba94abd
  - path: plugins/deployit/references/troubleshooting.md
    blob: f34f378b62868e7e11176fa0b0d4b6e6e2f6c87c
  - path: plugins/deployit/references/visionos.md
    blob: 3773ae52396c5b6df79ce4d8926f2412fe4eca3d
references_modules: [plugins-deployit-assets, plugins-deployit-bin, plugins-deployit-misc, plugins-semver-misc]
generator: cartographer/1
baseline: b1e1f9d1dbced518c625c38bb87814de5af1a1b7
verified: true
---

# Module: plugins/deployit/references

## Purpose

Depth layer of the `/deployit` skill's thin-router design: one procedure doc per deploy concern.
Each doc draws an ownership boundary between the plugin, the host repo, and external tooling.
They mirror behavior implemented in `plugins/deployit/bin`, so CLI/backend changes rot them first.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `Bootstrap Reference` | reference doc | `plugins/deployit/references/bootstrap.md:1` | Owns one-time per-Mac setup: idempotent setup steps, prerequisites, re-run, teardown |
| `iOS Deploy Reference` | reference doc | `plugins/deployit/references/ios.md:1` | Owns iOS OTA mechanics: Development-profile `itms-services://` install, trust + UDID flows |
| `macOS Deploy Reference` | reference doc | `plugins/deployit/references/macos.md:1` | Owns macOS deploys: Developer ID signing, Gatekeeper, notarytool setup, staple pipeline |
| `Semver awareness` | reference doc | `plugins/deployit/references/semver.md:1` | Owns the semver-plugin contract: activity detection, web-UI version labels, deploy-time bump guard |
| `Tailscale Serve Reference` | reference doc | `plugins/deployit/references/tailscale-serve.md:1` | Owns the HTTPS layer: proxy rationale, `/deployit/` URL map, PWA install, reboot + teardown |
| `Troubleshooting Reference` | reference doc | `plugins/deployit/references/troubleshooting.md:1` | Owns the symptom→cause→fix table, log locations, quick diagnostics |
| `visionOS Deploy Reference` | reference doc | `plugins/deployit/references/visionos.md:1` | Owns visionOS deltas from iOS: archive destination, `ExportOptions.visionos.plist` export, device-only |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `8729` | TCP port | `plugins/deployit/references/tailscale-serve.md:10` | Backend port behind the proxy; a port conflict is the documented crash-loop cause |
| `com.mikeydotio.deployit.backend` | launchd label | `plugins/deployit/references/bootstrap.md:15` | Backend agent identity; lifecycle, teardown, and diagnostics key on it |
| `deployit-notary` | keychain profile | `plugins/deployit/references/macos.md:42` | Default notarytool profile the plugin looks for; override via `config.toml` `notary_profile` |

## Relationships

- `plugins-deployit-misc.SKILL.md -> plugins-deployit-references.bootstrap.md (reads)`
- `plugins-deployit-misc.SKILL.md -> plugins-deployit-references.ios.md (reads)`
- `plugins-deployit-misc.SKILL.md -> plugins-deployit-references.macos.md (reads)`
- `plugins-deployit-misc.SKILL.md -> plugins-deployit-references.semver.md (reads)`
- `plugins-deployit-misc.SKILL.md -> plugins-deployit-references.tailscale-serve.md (reads)`
- `plugins-deployit-misc.SKILL.md -> plugins-deployit-references.troubleshooting.md (reads)`
- `plugins-deployit-misc.SKILL.md -> plugins-deployit-references.visionos.md (reads)`
- `plugins-deployit-references.bootstrap.md -> plugins-deployit-references.macos.md (reads)`
- `plugins-deployit-references.macos.md -> plugins-deployit-assets.ExportOptions.macos.plist (reads)`
- `plugins-deployit-references.semver.md -> plugins-deployit-bin._semver_active_version (reads)`
- `plugins-deployit-references.semver.md -> plugins-deployit-bin._version_label (reads)`
- `plugins-deployit-references.semver.md -> plugins-deployit-misc.SKILL.md (reads)`
- `plugins-deployit-references.semver.md -> plugins-semver-misc.semver-cli (calls)`
- `plugins-deployit-references.tailscale-serve.md -> plugins-deployit-bin._STATIC_ASSETS (reads)`
- `plugins-deployit-references.troubleshooting.md -> plugins-deployit-bin.deployit-cli (reads)`
- `plugins-deployit-references.visionos.md -> plugins-deployit-references.ios.md (extends)`

## Type notes

- Build bumps belong to the host repo's Archive pre-action (plugins/deployit/references/ios.md:17)
- Semver state is read from disk; only the bump shells out (plugins/deployit/references/semver.md:5)
- `semver_version` freezes into metadata at deploy time (plugins/deployit/references/semver.md:22)
- Proxy and backend survive reboots unattended (plugins/deployit/references/tailscale-serve.md:44)
- visionOS Simulator builds are never staged for OTA (plugins/deployit/references/visionos.md:52)

## External deps

- tailscale CLI — `serve --bg` proxy and daemon checks; HTTPS ingress for every URL
- Xcode toolchain — `xcodebuild`, `xcrun notarytool`, `xcrun stapler`, `security`
- launchd (`launchctl`) — backend lifecycle and KeepAlive restarts
- gh CLI — HTTPS pushes to the shared deployit-index repo
- hdiutil — wraps the `.app` into the served `.dmg`
- qrencode (optional) — terminal QR code for the install URL

## Gotchas

- Archive pre-action plus wrapper bump double-bumps (plugins/deployit/references/ios.md:26)
- Sandboxed Tailscale can't path-serve; use proxy (plugins/deployit/references/tailscale-serve.md:5)
- PWA assets come from `_STATIC_ASSETS` only (plugins/deployit/references/tailscale-serve.md:76)
- Install links fail when origin Mac sleeps (plugins/deployit/references/tailscale-serve.md:115)
- A failed semver bump halts the deploy entirely (plugins/deployit/references/semver.md:75)
