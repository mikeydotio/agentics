---
name: deployit
description: Use when the user wants to deploy an iOS / macOS / visionOS app to their tailnet for OTA install on their own devices. Commands: `/deployit bootstrap` (one-time setup), `deploy [--platform P] [--scheme S]`, `list`, `url`, `status`, `gc`, `redeploy [--source PATH]`. Reports/bumps the semver version in the web UI when present. Every macOS deploy also publishes a Developer-ID-signed GitHub release (pass `--no-release` to skip).
argument-hint: <bootstrap | deploy [--platform P] [--scheme S] [--no-release] | list | url | status | gc | rm [--build ID | --product BUNDLE_ID --platform P] | redeploy [--source PATH]>
model: sonnet
effort: medium
---

# deployit Orchestrator

`/deployit` archives the current Xcode workspace or project, exports a
Development- or Developer-ID-signed binary, stages it under
`~/Library/Application Support/deployit/serve/`, appends an entry
to the shared `mikeydotio/deployit-index` repo, and points the
user at a Tailscale-served URL. For macOS, it additionally publishes a
GitHub release of the Developer-ID-signed app (zipped) to the app's own
repo, with release notes you author from the commit/issue history.

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
6. For the GitHub release (macOS), your only job is to **author the notes** and
   route them through `deploy --release-notes-file`. Never call `gh` or
   `bin/deployit-release` yourself, and never create tags or releases directly —
   the CLI owns publishing (see **macOS GitHub release**).

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

  If the project's own `.deployit/config.toml` has a `[toolchain]` table,
  archive/export use that pinned Xcode instead of the machine's
  `xcode-select` default — see **Per-project toolchain pin**. If the CLI
  fails with a `[toolchain] ... does not exist` or `... but no
  /Applications/Xcode*.app install has a version >= ...` error, that pin is
  stale or the required Xcode isn't installed on this Mac; do not silently
  remove the pin without checking with the user first (it usually exists
  because the project genuinely needs that toolchain).
- **list / status / url** are read-only; no confirmations needed.
- **gc** requires `--keep N` or `--older-than D` — never run unqualified.
- **rm** deletes a local build or product — its index entry plus the on-disk
  `serve/<id>/` files — and is the writer behind the web UI's swipe-to-delete.
  Destructive: require an explicit `--build ID` or `--product BUNDLE_ID
  --platform P`, never unqualified. It only removes builds this machine owns
  (`origin_base_url == base_url`); foreign builds are managed on their origin Mac.
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
4. **macOS — author the release notes** (skip for iOS/visionOS, when the user
   passed `--no-release`, or when `[github] release = false`). Every macOS
   deploy publishes a GitHub release and you write its notes:
   a. Gather facts:
      `bash ${CLAUDE_PLUGIN_ROOT}/bin/deployit-router.sh release-context`.
      Returns `owner_repo`, `prev_tag`, `commits` (each with a `url`), and
      `closed_issues` (each with `number`, `title`, `url`).
   b. Compose Markdown: an optional 1–3 sentence preamble, then a bulleted list
      of the changes (from `commits`) and the closed issues, each a hyperlink
      built from its `url`. Surface the issues the commits actually
      reference/close; never invent entries; omit a section that has nothing.
      Keep it tight and user-facing.
   c. Write it to a temp file, e.g. `/tmp/deployit-release-notes.md`.
5. **Deploy**: `bash ${CLAUDE_PLUGIN_ROOT}/bin/deployit-router.sh deploy --platform <P> [--scheme <S>] [--release-notes-file <tmp>]`.
   Pass `--release-notes-file <tmp>` from step 4 for macOS (omit for other
   platforms). Handle the scheme question loop as usual, then show the deploy
   `display`.

`preflight`, `bump`, and `release-context` are internal sub-steps of `deploy` —
users never invoke them directly. The build is archived from the (possibly
just-created) release commit, so the recorded commit and build-id reflect that
release.

## macOS GitHub release

Every macOS `deploy` also publishes a GitHub release on the **app's own repo**
(its `origin`), containing the Developer-ID-signed `.app` as a `.zip`:

- **You author the notes** (step 4 above); the CLI publishes them verbatim.
- The release **tag/version** is resolved by the CLI: the semver `VERSION` when
  the project is semver-tracked, else the app's `CFBundleShortVersionString`. If
  neither exists, the release step fails loudly.
- It runs **last**, after the tailnet build is fully published, and is
  **recoverable**: the deploy `display` ends with a `release:` line — either the
  release URL, or `release: FAILED — …`. On failure the tailnet build still
  deployed; surface the error and re-deploy to retry (add `--clobber-release` if
  the tag already exists).
- Prerequisite: the GitHub CLI must be authenticated (`gh auth login`). For a
  download that opens without the Gatekeeper prompt, configure notarization
  (`[macos] notarize`). Full details in `references/github-release.md`.

## Build configuration

`deploy` passes **no** `-configuration` to `xcodebuild` — the scheme's Archive
action decides, exactly as Archiving from Xcode would. (Before v3.0.0 deployit
forced `Debug`, which overrides the scheme, so every OTA build shipped
unoptimized with `#if DEBUG` code compiled in.)

Before archiving, `deploy` asks xcodebuild what the archive resolves to and
**refuses an unoptimized archive that has not been acknowledged**, on every
platform. The check is substance-based (`SWIFT_OPTIMIZATION_LEVEL`, falling back
to `GCC_OPTIMIZATION_LEVEL`), never the configuration name, so a `Release`-named
build compiled `-Onone` is still caught. If xcodebuild cannot answer, `deploy`
refuses too.

A project that deploys unoptimized builds on purpose acknowledges it in its own
`.deployit/config.toml`:

```toml
[build]
allow_debug = true
```

That is an acknowledgement, not a setting — it never chooses or changes the
configuration. It does **not** authorise publishing: an unoptimized archive is
still refused when the deploy would publish a Developer-ID-signed GitHub release
(escape via `--no-release` or `[github] release = false`), and it does not
silence an unresolved-settings refusal. There is deliberately no
`[build] configuration` value key — the scheme already declares that, and a
second authority could diverge from it silently. Every build records its
`configuration` and `optimization_level` in `_meta.json` and the index entry.
Full details in `references/build-configuration.md`.

## Per-project toolchain pin

A project can pin the Xcode toolchain `deploy` archives/exports with, via its
own `<project>/.deployit/config.toml` `[toolchain]` table — either
`min_sdk = "27"` (picks the newest matching `/Applications/Xcode*.app`) or an
explicit `developer_dir` path. This is separate from the per-machine
`~/Library/Application Support/deployit/config.toml` bootstrap writes; the
project one is committed to the app's repo so the pin travels with the
project. No `[toolchain]` table (or no `.deployit/config.toml` at all) means
unchanged behavior — archive/export inherit the ambient toolchain. Full
details, including the failure modes, in `references/toolchain.md`.

## Post-deploy tests

If the project has a `.deployit/post-deploy-test.sh`, every `deploy` runs it
**out-of-band** after the build is fully published: deployit spawns it detached
(so a 15–20 min suite runs free of the ~60s hook/tool timeout), streams it to a
per-build log, and the deploy `display` ends with a `post_test:` line — either
`running out-of-band → <log>` or `no .deployit/post-deploy-test.sh — skipped`.
The pass/fail badge appears on the build page when the suite finishes; the script
owns any failure reporting (e.g. filing an issue per failing test). Surface the
`post_test:` line to the user but do **not** wait on the suite. Long suites belong
here; keep a fast (<60s) blocking gate as a PreToolUse hook. Full details in
`references/post-deploy-tests.md`.

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
- `references/github-release.md` — macOS GitHub release: version/tag rules, notes, notarization, recovery
- `references/post-deploy-tests.md` — out-of-band post-deploy test suites via `.deployit/post-deploy-test.sh`
- `references/build-configuration.md` — which configuration is archived, the unoptimized-archive refusal, and `[build] allow_debug`
- `references/toolchain.md` — per-project Xcode toolchain pin via `.deployit/config.toml [toolchain]`
- `references/sparkle.md` — macOS Sparkle auto-update: appcast + EdDSA signing + app wiring
- `references/visionos.md` — visionOS specifics (mostly ≡ iOS)
- `references/tailscale-serve.md` — proxy config + Mac App Store variant quirks
- `references/troubleshooting.md` — common archive/export failures + recipes
- `references/semver.md` — semver integration: version display + deploy-time bump guard
- `references/index-publishing.md` — appcast/listing PR publish flow (`publish = "auto"`, `auto_merge`), referenced from troubleshooting.md's ruleset-block recipe
