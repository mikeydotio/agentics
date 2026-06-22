# macOS GitHub Release Reference

Every macOS `/deployit deploy` publishes a GitHub release of the
Developer-ID-signed app — archived as a `.zip` with `ditto` — to the **app's own
repository**, alongside the tailnet download page. The deployit agent authors the
release notes; the CLI resolves the version, packages the asset, and publishes.

Toggle and options live in `[github]` of `config.toml` (see
`assets/config.example.toml`). On by default; skip a single deploy with
`/deployit deploy --no-release`, or disable entirely with `release = false`.

## Prerequisites

- **GitHub CLI authenticated**: `gh auth login` (or a `GH_TOKEN` in the
  environment). The publish runs `gh release create` against the repo parsed from
  the app checkout's `origin` remote.
- **Developer ID signing**: the export must be Developer-ID signed
  (`ExportOptions.macos.plist` already sets `method = developer-id`). The release
  step verifies the signature and refuses to publish an ad-hoc/Development-signed
  app unless explicitly overridden.
- **Notarization (recommended)**: see below — without it the downloaded `.app`
  is Gatekeeper-quarantined.

## Version → tag resolution

The release tag is resolved in this strict order (the script fails loudly if it
reaches the end):

1. **semver `VERSION`** — when the project is semver-tracked (`.semver/config.yaml`
   with `tracking: true` and a `VERSION` file). The tag is the `VERSION` string
   verbatim (it already carries the `version_prefix`, e.g. `v2.17.0`), so the
   release attaches to the tag `semver`'s `git_tagging` already created at the
   release commit.
2. **`CFBundleShortVersionString`** — the marketing "version number" read from the
   built app's `Info.plist`. Normalised with the semver `version_prefix` (so
   `2.17.0` → `v2.17.0` when the prefix is `v`).
3. **Neither** → fail loudly. We never publish an unversioned release.

The release is pinned to the exact build commit via `--target <full-sha>`, so it
points at the right commit even when the tag is created during publish.

## Notarization

Today's `.dmg` path notarizes the disk image. A GitHub-release `.zip` extracts the
`.app` **directly**, so Gatekeeper checks the bundle's own ticket — which means the
`.app` itself must be notarized and stapled. When `[macos] notarize = true` (with
`notary_profile` set), a macOS deploy notarizes + staples the `.app` **before**
zipping it, so the download opens with no right-click dance. This reuses the same
credentials as `.dmg` notarization (`xcrun notarytool store-credentials`, see
`references/macos.md`); with both the release `.app` and the `.dmg` enabled,
notarytool runs once per artifact.

Without notarization the release still publishes (Developer-ID signed), but the
first launch on another Mac needs right-click → Open (the standard Gatekeeper
caveat from `references/macos.md`).

## Ordering, failure & recovery

The release is the **final** deploy step — it runs only after the tailnet build is
fully published (index push + backend refresh). Consequences:

- A release failure never rolls back a deployed, indexed build. The deploy
  `display` ends with `release: FAILED — <reason>`; the build is live on the
  tailnet, and re-running the deploy retries the release.
- A failed index push happens **before** any publish, so a broken deploy never
  leaves an orphaned public release.

Infrastructure gaps (no `gh`, not authenticated, no `origin` remote) degrade to a
loud `release:` warning rather than failing the whole deploy. A genuinely
unresolvable version fails loudly.

## Existing tag / re-deploy

If a release for the resolved tag already exists, the publish **fails loudly** by
default (e.g. re-deploying the same version). To replace the existing release's
asset and notes, pass `/deployit deploy --clobber-release` or set
`[github] clobber = true`.

## Running the publisher by hand

`bin/deployit-release` is standalone. To publish (or re-publish) from a signed
`.app` or a staged `.zip`:

```bash
bin/deployit-release \
  --app /path/to/MyApp.app \          # or --zip /path/to/MyApp.zip
  --project-dir /path/to/app-checkout \  # semver VERSION + origin remote
  --notes-file /tmp/notes.md \
  --target "$(git -C /path/to/app-checkout rev-parse HEAD)" \
  --dry-run                            # print the gh command(s); publish for real without it
```

Useful flags: `--repo OWNER/REPO` (override the parsed remote), `--clobber`,
`--prerelease`, `--attach <file>` (extra asset, e.g. the `.dmg`),
`--no-require-developer-id` (publish a non-Developer-ID build anyway).

Env overrides mirror the CLI: `DEPLOYIT_GH_BIN` (path to `gh`),
`DEPLOYIT_SKIP_CODESIGN_VERIFY` (treat the app as validly signed — tests only).
