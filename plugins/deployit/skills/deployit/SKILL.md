---
name: deployit
description: Use when the user wants to deploy an iOS / macOS / visionOS app to their tailnet for OTA install on their own devices. Commands are `/deployit bootstrap` (one-time per Mac), `/deployit deploy [--platform ios|macos|visionos] [--scheme NAME]`, `/deployit list`, `/deployit url`, `/deployit status`, `/deployit gc`, and `/deployit redeploy [--source PATH]` (refresh daemon + verify after PWA changes). When the project uses the semver plugin, deploy reports the semver version in the web UI and bumps it when it has not changed since the last build. Replaces hand-rolled `Tools/Deploy/deploy-ios.sh`-style scripts.
argument-hint: <bootstrap | deploy [--platform P] [--scheme S] | list | url | status | gc | redeploy [--source PATH]>
---

# deployit Orchestrator

`/deployit` archives the current Xcode workspace or project, exports a
Development- or Developer-ID-signed binary, stages it under
`~/Library/Application Support/deployit/serve/`, appends an entry
to the shared `mikeydotio/deployit-index` repo, and points the
user at a Tailscale-served URL.

**Router:** `bash ${CLAUDE_PLUGIN_ROOT}/bin/deployit-router.sh <ARGUMENTS>`

## Hard rules

1. Route every command through the router. Never call `deployit-cli` directly.
2. If the CLI returns `ok: false`, show the `display` (or `message`) and stop.
3. Never push to the index repo from this orchestrator; that is the CLI's job.
4. Build-number bumping is the host repo's responsibility. Lillist's
   `Tools/Deploy/bump-build-number.sh` Archive pre-action stays; the plugin
   reads the resolved `CFBundleVersion` from the built `Info.plist`.
5. Semver awareness is automatic and independent of `CFBundleVersion`. When the
   project tracks its version with the semver plugin (`.semver/config.yaml` with
   `tracking: true` + a `VERSION` file), `deploy` reports the semver version in
   the web UI and ensures it changed since the last build (see **Semver-aware
   deploy**). It never touches the app's `MARKETING_VERSION` or Info.plist —
   display only.

## Generic flow

1. **Route**: `bash ${CLAUDE_PLUGIN_ROOT}/bin/deployit-router.sh <ARGUMENTS>`
2. **Check `ok`**: if false, show `display` and stop.
3. **Display**: show the CLI's `display` field on success.

## Per-command notes

- **bootstrap** is idempotent. Run it once on each Mac, and re-run any time
  the plugin version changes (it rewrites the launchd plist with the
  current plugin path).
- **deploy** runs a semver preflight first (see **Semver-aware deploy**), then
  auto-detects project + bundle ID + marketing version from one
  of two repo layouts (Apps-layout wins when both signals are present):

  1. **Apps-layout (monorepo):** `./<Name>.xcworkspace` + `./Apps/<Name>-<Platform>/project.yml`.
     Default scheme is `<Name>-<Platform>` (e.g. `Lillist-iOS`).
  2. **Single-app layout:** `./<Name>.xcodeproj` + `./project.yml`. Default
     scheme is `<Name>` (e.g. `moshtail`).

  `MARKETING_VERSION` and `PRODUCT_BUNDLE_IDENTIFIER` may be quoted or
  unquoted in `project.yml`. If the CLI fails with "no recognised Xcode
  project layout in cwd," the user is likely in the wrong directory —
  confirm with them before suggesting a scheme override.
- **list / status / url** are read-only; no confirmations needed.
- **gc** requires `--keep N` or `--older-than D` — never run unqualified.
- **redeploy** updates the daemon's stable `_plugin_root` and
  `bin/deployit-backend` symlinks, rewrites a legacy hash-pinned plist if
  detected, kickstarts launchd, and runs `tests/verify-live.sh` against the
  live HTTP endpoint. Pass `--source PATH` to point at a dev checkout instead
  of the cached release. **Run this after every change to `plugins/deployit/`**
  — `_healthz` alone is not enough to confirm the new code is live.

## Semver-aware deploy

`deploy` runs a preflight first so builds stay version-correct when the project
uses the semver plugin. Run these steps in order (the user still just calls
`/deployit deploy [--platform P] [--scheme S]`):

1. **Preflight**: `bash ${CLAUDE_PLUGIN_ROOT}/bin/deployit-router.sh preflight --platform <P>`
   (same `--platform` the user gave). If `ok` is false, show `display` and stop.
2. If `semver_active` is false **or** `bump_needed` is false → skip to step 4.
3. If `bump_needed` is true (the current semver `VERSION` already labels the
   latest published build, so this build needs a fresh version):
   a. Ask **one** `AskUserQuestion` — header "Version bump", question "Which
      version component to bump for this deploy?". Build the options from the
      `candidates` map: `Patch → <candidates.patch>`, `Minor → <candidates.minor>`,
      `Major → <candidates.major>` (drop the `→ target` if `candidates` is null).
   b. Run `bash ${CLAUDE_PLUGIN_ROOT}/bin/deployit-router.sh bump --component <major|minor|patch>`
      for the chosen component. This bumps via the semver plugin, folding any
      uncommitted changes into the `chore(release)` commit (no further prompts)
      and tagging per the project's semver config. If `ok` is false, show
      `display` and **stop** — never deploy a stale version.
4. **Deploy**: `bash ${CLAUDE_PLUGIN_ROOT}/bin/deployit-router.sh deploy --platform <P> [--scheme <S>]`.
   Handle the scheme question loop as usual, then show the deploy `display`.

`preflight` and `bump` are internal sub-steps of `deploy` — users never invoke
them directly. The build is archived from the (possibly just-created) release
commit, so the recorded commit and build-id reflect that release.

## Question loop

When the CLI returns a `questions` array (e.g., multiple schemes match the
requested platform), process each in order:

```
For each question in questions:
  1. Call AskUserQuestion with the question's header, question, and options
  2. Map the user's selection through flag_mapping or command_mapping
  3. Collect resulting flags
```

After processing all questions, re-run the router with the collected flags
appended to the original command.

## References

- `references/bootstrap.md` — per-machine one-time setup walkthrough
- `references/ios.md` — iOS specifics: signing, UDID registration, Trust flow
- `references/macos.md` — macOS Developer-ID signing + notarytool
- `references/sparkle.md` — macOS Sparkle auto-update: appcast + EdDSA signing + app wiring
- `references/visionos.md` — visionOS specifics (mostly ≡ iOS)
- `references/tailscale-serve.md` — proxy config + Mac App Store variant quirks
- `references/troubleshooting.md` — common archive/export failures + recipes
- `references/semver.md` — semver integration: version display + deploy-time bump guard
