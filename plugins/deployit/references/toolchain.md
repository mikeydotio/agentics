# Per-project toolchain pin

deployit normally archives/exports with whatever Xcode `xcode-select` already
has active on the machine. Some projects need a *different* toolchain than the
default — e.g. a beta SDK a specific dependency requires — without touching
the developer's global `xcode-select`. `.deployit/config.toml`'s `[toolchain]`
table (the same `.deployit/` project-local convention as
`ExportOptions.<platform>.plist` and `post-deploy-test.sh`) lets a project pin
that toolchain in its own repo, so different projects on the same Mac can pin
different Xcodes with no manual switching between deploys.

This is a **separate file from the per-machine `~/Library/Application
Support/deployit/config.toml`** that `bootstrap` writes (server port,
notarization, Sparkle, GitHub release settings). The per-project file lives in
the *app's own repo* and is committed, so the pin travels with the project and
applies on every Mac that deploys it.

## Opt in: `<project>/.deployit/config.toml`

```toml
[toolchain]
# Pin by minimum SDK/Xcode major version — resolves to the newest
# /Applications/Xcode*.app whose own version is >= this value. Preferred over
# a hardcoded path: Xcode install locations and names churn (a beta moving
# from ~/Downloads to /Applications, or being renamed once it ships stable).
min_sdk = "27"

# OR pin an explicit path (wins over min_sdk if both are set) — an escape
# hatch for a nonstandard install location:
# developer_dir = "/Applications/Xcode-beta.app/Contents/Developer"
```

Neither key is required — a project with no `[toolchain]` table (or no
`.deployit/config.toml` at all) behaves exactly as before this feature
existed: archive/export inherit whatever toolchain the ambient environment
(the calling shell's `DEVELOPER_DIR`, or `xcode-select`) already provides.

## Resolution + failure mode

- `developer_dir` set → used verbatim. Fails loudly (`ok: false`, before any
  `xcodebuild` invocation) if that path doesn't exist — a stale pin should
  never silently fall through to the wrong toolchain.
- `min_sdk` set (and no `developer_dir`) → scans `/Applications/Xcode*.app`,
  reads each candidate's `CFBundleShortVersionString`, and picks the newest
  one whose major version is `>= min_sdk`. Fails loudly if nothing on disk
  qualifies, rather than silently building with whatever the ambient
  toolchain happens to be. This matters when the pin exists precisely
  *because* a wrong-toolchain build would still **succeed** but silently omit
  something the required SDK enables — see
  [mikeydotio/lillist#70](https://github.com/mikeydotio/lillist/issues/70):
  an app whose optional feature only compiles against a newer SDK still
  builds fine on the default one, just without that feature, so a resolver
  that quietly fell back would ship a build silently missing it.
- Neither key set → no override; behavior is unchanged from before this
  feature existed.

The resolved `DEVELOPER_DIR` applies to **both** the `xcodebuild archive` and
`xcodebuild -exportArchive` steps of the same deploy, so they never disagree
about which toolchain produced the artifact being exported.

## Debugging

`/deployit deploy --dump-metadata --platform <P>` prints the resolved
`developer_dir` (`null` when no `[toolchain]` table applies) alongside the
rest of the detected project metadata, without running a build.
