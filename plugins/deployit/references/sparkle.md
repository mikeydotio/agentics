# Sparkle Auto-Update Reference (macOS)

deployit can publish an **EdDSA-signed Sparkle appcast** so your macOS apps
update themselves in place. The work splits in two:

- **deployit's half (automatic once enabled):** each `macos` deploy also zips
  the `.app`, signs the zip with your EdDSA key, and serves a per-product
  appcast at `<base_url>/p/<bundle_id>/macos/appcast.xml` (tailnet-only). When
  a GitHub release is also published for that deploy, the same signed zip and
  a second appcast are attached to the release too — see "Two appcast
  channels" below.
- **Your app's half (one-time wiring):** add the Sparkle framework, point its
  feed at whichever appcast URL matches your distribution channel, and embed
  the matching public key.

This is opt-in. Until you enable it (below), macOS deploys behave exactly as
before — a `.dmg` download, no appcast.

## Two appcast channels

A signed macOS build can be reachable in two different ways, each with its
own appcast:

| Channel | Feed URL | Reachable from |
|---|---|---|
| Tailnet | `<base_url>/p/<bundle_id>/macos/appcast.xml` | only devices on your tailnet — dev/test installs |
| GitHub release | `https://github.com/<owner>/<repo>/releases/latest/download/appcast.xml` | anywhere — real distributed users |

The GitHub-release feed is published **automatically** whenever a build is
both EdDSA-signed (`[macos.sparkle] enabled = true`) and a GitHub release is
published for it (`[github] release = true`, the default — see
`references/github-release.md`) — no separate toggle. It carries a single
`<item>` for the current release; the `<enclosure>` points at that release's
zip asset (`.../releases/download/<tag>/<Project>.zip`), which is the exact
same EdDSA-signed bytes as the tailnet zip (deployit reuses one signed archive
for both). deployit reports both URLs (when applicable) after a deploy.

**A distributed (Developer-ID) app should point `SUFeedURL` at the GitHub
feed, not the tailnet one** — the tailnet appcast's enclosure is only
reachable while your origin Mac is up and on the tailnet (see "Limitations &
notes" below), which silently breaks auto-update for anyone off it. If your
project builds separate local/distribution configurations (e.g. an xcconfig
per scheme), point the distribution build's `SU_FEED_URL` at the GitHub feed
and keep the tailnet feed only for local/dev builds.

**Caveat — pre-releases:** `.../releases/latest/download/...` only ever
resolves to the newest **non-prerelease** release. If `[github] prerelease =
true` (or `--prerelease`) is set for a deploy, deployit withholds the
GitHub-release appcast for that build and warns — publishing one would create
a feed URL that can never resolve to it.

**Config-vs-app detection.** Every macOS deploy inspects the built `.app` for
Sparkle wiring (an embedded `Sparkle.framework`, and `SUFeedURL`/
`SUPublicEDKey` in its Info.plist) independent of `[macos.sparkle] enabled`,
and warns loudly on any mismatch — most importantly, an app that *is*
Sparkle-wired while `enabled` is `false`, which otherwise fails silently (no
appcast, no error). `enabled` still decides whether an appcast is actually
produced, since signing needs the configured key.

## 1. Generate an EdDSA key pair (once, ever)

Sparkle ships a `generate_keys` tool (see "Where the tools live" below):

```bash
generate_keys
```

It stores the **private** key in your login Keychain and prints the **public**
key (`SUPublicEDKey`) — copy it. Treat the private key like an SSH key.

### Share ONE key across your Macs

A Sparkle app verifies updates against a **single** `SUPublicEDKey`, but the
`deployit-index` is shared across every Mac you deploy from. So **every origin
Mac must sign with the same private key**, or installs from machine B fail
verification on an app that embeds machine A's public key.

Export the private key to a file and sync it (e.g. via `~/Enderchest`, which
Syncthing replicates to your other Macs):

```bash
generate_keys -x ~/Enderchest/deployit/sparkle_ed_priv.key
```

On each Mac, point `config.toml` at that file (step 2). Keep it private — it is
the root of trust for your updates.

## 2. Enable Sparkle in config.toml

`~/Library/Application Support/deployit/config.toml`:

```toml
[macos.sparkle]
enabled = true
sign_update_path = ""    # empty = auto-discover; or an explicit path (step 3)
private_key_path = "/Users/<you>/Enderchest/deployit/sparkle_ed_priv.key"
public_ed_key = "<the SUPublicEDKey generate_keys printed>"
```

- `private_key_path` empty → `sign_update` uses its Keychain default (fine on a
  single Mac, but a Keychain can't be shared across Macs — prefer the file).
- `public_ed_key` is surfaced for convenience only (product page + deploy
  output); the app, not deployit, enforces it.

## 3. Where the Sparkle tools live

`sign_update` and `generate_keys` come with Sparkle. Leave `sign_update_path`
empty to auto-discover it; deployit tries, in order:

1. `DEPLOYIT_SPARKLE_SIGN_UPDATE` env var
2. `macos.sparkle.sign_update_path` in `config.toml`
3. `sign_update` on `PATH`
4. the **SwiftPM artifact bundle** — you'll add Sparkle via SPM anyway (step
   4), and after a build the tools sit under
   `~/Library/Developer/Xcode/DerivedData/<Project>-*/SourcePackages/artifacts/*/Sparkle/bin/`
5. the Homebrew cask, `/opt/homebrew/Caskroom/sparkle/<version>/bin/` (or
   `/usr/local/...` on Intel) — **deprecated**, see below

Rungs 1–2 are explicit operator intent: if you set either one, deployit uses
*exactly* that binary — a path that doesn't exist there is a **hard error**
naming the path you configured, never a silent fall-through to something
else. This is deliberate (see the incident below): an operator who pinned a
tool believes it's pinned, so guessing a substitute without saying so is
worse than failing loudly. Leave the key **empty** to opt into auto-discovery
(rungs 3–5) instead.

When multiple versions match the same glob (e.g. two Caskroom installs),
deployit picks the **newest by parsed version**, not the first one
alphabetically.

**Prefer the SwiftPM artifact over Homebrew.** Homebrew has deprecated the
`sparkle` cask — `brew info --cask sparkle` reports *"Deprecated because it
does not pass the macOS Gatekeeper check! It will be disabled on
2026-09-01."* Its downloads are also quarantined by Homebrew and adhoc-signed
by Sparkle with no Team ID, a combination Gatekeeper kills outright on first
run. The SwiftPM artifact is byte-identical, carries **no quarantine xattr**
(SwiftPM extraction doesn't set one), and is guaranteed to match the Sparkle
version your app actually links — deployit tries it first and only falls
back to the cask (with a warning) if no SwiftPM artifact is found.

**The trap that caused a real incident.** Lillist v0.19.0 shipped an
unsigned GitHub release on 2026-07-29 because `config.toml` pinned a
version-stamped Caskroom path (`.../sparkle/2.9.3/bin/sign_update`), and
`brew upgrade` later deleted 2.9.3 while installing 2.9.4. The pre-#117
resolver treated the missing pin as *absent* and silently substituted the
2.9.4 binary — which Gatekeeper killed with a non-zero exit and **empty
stderr**, logged as a bare `sign_update failed: ` with nothing after the
colon. Two lessons are now enforced: a version-stamped path is a trap
`brew upgrade` springs on you (prefer the SwiftPM artifact, which has no
version segment to go stale), and a configured-but-missing path is fatal, not
silently substituted.

- **Direct download:** the Sparkle release tarball's `bin/` also works — set
  `sign_update_path` explicitly.

## 4. Add Sparkle to your app (SPM)

In Xcode: **File → Add Package Dependencies →**
`https://github.com/sparkle-project/Sparkle`, "Up to Next Major" from `2.0.0`.
Link `Sparkle` to your app target.

## 5. Info.plist keys

Pick the feed URL for your distribution channel (see "Two appcast channels"
above) — tailnet for dev/test builds, GitHub release for anything you ship to
other people:

```xml
<key>SUFeedURL</key>
<!-- tailnet (dev/test only): -->
<string>https://<host>.<tailnet>.ts.net/deployit/p/<bundle_id>/macos/appcast.xml</string>
<!-- GitHub release (distributed users): -->
<string>https://github.com/<owner>/<repo>/releases/latest/download/appcast.xml</string>
<key>SUPublicEDKey</key>
<string><the public key from step 1></string>
<key>SUEnableAutomaticChecks</key>
<true/>
```

deployit prints both `appcast` URLs (tailnet always; GitHub release when one
was published for the build) and `SUPublicEDKey` after each signed deploy, and
shows the tailnet one on the product page
(`/deployit/p/<bundle_id>/macos/`). The tailnet feed is only reachable while
the origin Mac is up and on the tailnet (same caveat as install links — see
`references/tailscale-serve.md`); the GitHub-release feed is reachable from
anywhere.

## 6. Add a "Check for Updates…" affordance

AppKit:

```swift
import Sparkle

final class UpdaterController {
    let updater = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
}
// Bind a "Check for Updates…" menu item to:
//   updaterController.updater.checkForUpdates()
```

SwiftUI: hold an `SPUStandardUpdaterController` in your `App` and bind a command
to `updater.checkForUpdates()` (see Sparkle's current SwiftUI sample).

## 7. Test an update (N → N+1)

1. With Sparkle enabled, `/deployit deploy --platform macos`. Install build N
   (download the `.dmg`, drag to Applications, launch).
2. Bump the app's `CFBundleVersion`; deploy build N+1.
3. In build N, choose **Check for Updates…**. Sparkle fetches the appcast,
   verifies `sparkle:edSignature` against `SUPublicEDKey`, downloads the `.zip`,
   and installs.

Sparkle decides "newer" by `CFBundleVersion` (`sparkle:version`), so each build
must increase it — deployit reads it from the archived `Info.plist` (the host
repo's build-number pre-action handles bumping it).

## Limitations & notes

- **Notarization of the `.zip` tracks `[github] release`, not just
  `[macos] notarize`.** The Sparkle `.zip`, the GitHub-release `.zip`, and the
  GitHub-appcast enclosure are the same file — and `_stage_macos` only staples
  a notarization ticket onto the `.app` *before* zipping when **both**
  `release` (on for that deploy — the default) **and** `notarize = true` are
  set, since stapling is otherwise only worth doing for the GitHub-release
  `.app`. So with the common config (GitHub releases + notarization both on,
  as in this project's own deploys), every Sparkle-zip surface is notarized —
  no Gatekeeper prompt. Deploying with `--no-release`/`[github] release =
  false` (Sparkle-only, no GitHub release) skips the staple even with
  `notarize = true`, so that build's `.zip` carries the Developer-ID signature
  without a stapled ticket, and a freshly auto-updated app may show the
  Gatekeeper "unidentified developer" prompt once. The EdDSA signature
  guarantees update integrity either way.
- **Signing is required when a GitHub release is being published.** A
  Developer-ID release is what real users auto-update from, so shipping one
  unsigned is a failed release that reports success — issue #117. If
  `sign_update` fails, isn't found, or its output can't be parsed, and this
  deploy publishes a GitHub release (`[github] release = true`, the default),
  the **whole deploy fails** (non-zero exit, nothing published — tailnet
  index, backend, and release all untouched) rather than shipping an
  unsigned build. deployit also preflights the toolchain before the
  archive/export/notarize round-trip, so a bad pin fails in seconds, not
  minutes in. Every failure names the resolved binary and, when the exit was
  a silent kill (empty stdout/stderr — Gatekeeper's signature), calls that
  out with the `xattr -d com.apple.quarantine <path>` fix.
- **Best-effort only for tailnet-only deploys.** With `--no-release` or
  `[github] release = false`, a signing failure still degrades gracefully as
  before: the deploy ships the `.dmg` and skips the appcast for that build (a
  warning is logged to `~/Library/Logs/deployit/backend.err.log` / the deploy
  stderr, naming the resolved binary). The build won't appear in the feed
  until re-deployed with signing working.
- **Key rotation.** If you generate a new key pair, ship an app update that
  embeds the new `SUPublicEDKey` *before* retiring the old key, or existing
  installs can't verify the switch.

