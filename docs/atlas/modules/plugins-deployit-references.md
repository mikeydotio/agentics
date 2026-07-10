---
module: plugins/deployit/references
summary: "Per-concern procedure docs behind /deployit — setup, platform deploys, proxy, semver bump guard, recovery"
read_when: "Changing deployit deploy/bootstrap/proxy/semver behavior or debugging install failures"
sources:
  - path: plugins/deployit/references/bootstrap.md
    blob: 24850fe5b053d9925a7af47513cfc2ac04033f93
  - path: plugins/deployit/references/github-release.md
    blob: c76af9df46aa1976f57f66cff2d6e7afc5b073cc
  - path: plugins/deployit/references/index-publishing.md
    blob: c403b37310959de5a4bbef9d30684e75d81f17a3
  - path: plugins/deployit/references/ios.md
    blob: 59175850b662bbf27b81972fc0ee97cfbe31acb9
  - path: plugins/deployit/references/macos.md
    blob: f3a69568a6ae8ad41280e7be3b3e3e34a19a1272
  - path: plugins/deployit/references/semver.md
    blob: 6bfc5d8f26e34851b97f77d4236e88fe8be273d6
  - path: plugins/deployit/references/sparkle.md
    blob: 03c53342a7c898cc3f381e24959f28e0a893257f
  - path: plugins/deployit/references/tailscale-serve.md
    blob: 92267a1597530c980bfee1916f83a818dba94abd
  - path: plugins/deployit/references/troubleshooting.md
    blob: f088e1e68868f93c78f755868aeec1cfb81ba0ea
  - path: plugins/deployit/references/visionos.md
    blob: 3773ae52396c5b6df79ce4d8926f2412fe4eca3d
generator: cartographer/4
baseline: a4486d2b70ad4124762f9d777af6a7dc007bdc6c
---

# Module: plugins/deployit/references

## Purpose

This module is the deep-reference layer behind the `/deployit` skill: one procedure doc per deploy concern (bootstrap, iOS/macOS/visionOS platform mechanics, GitHub release publishing, Sparkle auto-update, semver integration, Tailscale Serve networking, troubleshooting), cross-linking each other and back to the skill's own "Semver-aware deploy" section (plugins/deployit/references/semver.md:41) instead of duplicating procedure into the skill itself. Each doc draws an explicit ownership boundary between what deployit automates, what the host app repo must supply (e.g. build-number bumping, per plugins/deployit/references/ios.md:17), and what external tooling owns (Xcode, Tailscale, Sparkle, GitHub, notarytool). If this module vanished, the CLI's bare error output would be the only trace of its non-obvious failure modes — the data-protection-vs-file-based keychain trap during headless notarization (plugins/deployit/references/macos.md:64), the cross-Mac Sparkle key-sharing requirement (plugins/deployit/references/sparkle.md:29), and the strict version-to-tag resolution order for GitHub releases (plugins/deployit/references/github-release.md:26) — with no documented recovery path.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

- Build-number bumping belongs to the host repo's Archive pre-action, not the plugin (plugins/deployit/references/ios.md:17)
- Semver state is read from disk; only the deploy-time bump shells out to semver-cli (plugins/deployit/references/semver.md:5)
- `semver_version` freezes into build metadata at deploy time, since the backend serves builds from many machines and can't re-read a project's VERSION later (plugins/deployit/references/semver.md:22)
- GitHub release version resolves in strict order — semver VERSION, then CFBundleShortVersionString, else fail loudly — and the release step never runs until the tailnet index push has fully succeeded (plugins/deployit/references/github-release.md:26)
- Tailscale Serve config and the deployit backend both persist across reboots unattended (plugins/deployit/references/tailscale-serve.md:44)
- visionOS Simulator builds are never staged for OTA install (plugins/deployit/references/visionos.md:52)
- All origin Macs must share one EdDSA private key for Sparkle — divergent keys break update verification on installs signed from a different Mac (plugins/deployit/references/sparkle.md:29)

## External deps


## Gotchas

- Calling a bump script inside a deploy wrapper double-bumps — the host repo's Archive pre-action already fires for `xcodebuild archive` (plugins/deployit/references/ios.md:26)
- The Mac App Store Tailscale variant is sandboxed and can't serve filesystem paths directly, which is why the proxy design exists (plugins/deployit/references/tailscale-serve.md:5)
- Static PWA assets are served from a closed `_STATIC_ASSETS` allowlist; adding new ones requires a backend code edit, not a docs change (plugins/deployit/references/tailscale-serve.md:76)
- Install links fail if the origin Mac is asleep or offline, even though the listing entry (pulled from the shared index) still shows the build (plugins/deployit/references/tailscale-serve.md:115)
- notarytool's default data-protection keychain re-locks the instant the screen locks, so a headless/SSH deploy fails notarization even though codesign already succeeded — fix is a file-based keychain plus `notary_keychain` (plugins/deployit/references/macos.md:64)
- A semver CLI that can't be discovered halts the deploy entirely rather than shipping a stale/unversioned build (plugins/deployit/references/semver.md:75)
- Sparkle signing failures are best-effort: a missing `sign_update` or key still ships the `.dmg` and silently skips the appcast for that build (plugins/deployit/references/sparkle.md:135)
- Re-publishing a GitHub release for an already-existing tag fails loudly by default; `--clobber-release` (or `[github] clobber = true`) is required to replace it (plugins/deployit/references/github-release.md:74)
