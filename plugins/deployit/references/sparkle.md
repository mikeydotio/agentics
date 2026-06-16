# Sparkle Auto-Update Reference (macOS)

deployit can publish an **EdDSA-signed Sparkle appcast** so your macOS apps
update themselves in place. The work splits in two:

- **deployit's half (automatic once enabled):** each `macos` deploy also zips
  the `.app`, signs the zip with your EdDSA key, and serves a per-product
  appcast at `<base_url>/p/<bundle_id>/macos/appcast.xml`. The `.dmg` stays the
  manual "Download" on the web UI.
- **Your app's half (one-time wiring):** add the Sparkle framework, point its
  feed at the deployit appcast URL, and embed the matching public key.

This is opt-in. Until you enable it (below), macOS deploys behave exactly as
before — a `.dmg` download, no appcast.

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

`sign_update` and `generate_keys` come with Sparkle. deployit auto-discovers
`sign_update` on `PATH`, then common locations; set `sign_update_path` (or the
`DEPLOYIT_SPARKLE_SIGN_UPDATE` env var) if yours is elsewhere. Typical sources:

- **Swift Package Manager** (you'll add Sparkle via SPM anyway): after a build,
  the tools sit under
  `~/Library/Developer/Xcode/DerivedData/<proj>/SourcePackages/artifacts/sparkle/Sparkle/bin/`.
- **Homebrew:** `brew install --cask sparkle` →
  `/opt/homebrew/Caskroom/sparkle/<version>/bin/`.
- **Direct download:** the Sparkle release tarball's `bin/`.

## 4. Add Sparkle to your app (SPM)

In Xcode: **File → Add Package Dependencies →**
`https://github.com/sparkle-project/Sparkle`, "Up to Next Major" from `2.0.0`.
Link `Sparkle` to your app target.

## 5. Info.plist keys

```xml
<key>SUFeedURL</key>
<string>https://<host>.<tailnet>.ts.net/deployit/p/<bundle_id>/macos/appcast.xml</string>
<key>SUPublicEDKey</key>
<string><the public key from step 1></string>
<key>SUEnableAutomaticChecks</key>
<true/>
```

deployit prints the exact `appcast` URL and `SUPublicEDKey` after each signed
deploy, and shows them on the product page (`/deployit/p/<bundle_id>/macos/`).
The feed is only reachable while the origin Mac is up and on the tailnet (same
caveat as install links — see `references/tailscale-serve.md`).

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

- **The `.zip` is not notarized.** deployit notarizes/staples the `.dmg` (when
  enabled), but the Sparkle `.zip` enclosure carries the same Developer-ID-signed
  `.app` without a stapled ticket. A freshly auto-updated app may show the
  Gatekeeper "unidentified developer" prompt once. The EdDSA signature still
  guarantees update integrity. To avoid the prompt, notarize the `.app` before
  it ships (outside the current flow).
- **Best-effort signing.** If `sign_update` or the key is missing, the deploy
  still succeeds — it ships the `.dmg` and skips the appcast for that build (a
  warning is logged to `~/Library/Logs/deployit/backend.err.log` / the deploy
  stderr). The build won't appear in the feed until re-deployed with signing
  working.
- **Key rotation.** If you generate a new key pair, ship an app update that
  embeds the new `SUPublicEDKey` *before* retiring the old key, or existing
  installs can't verify the switch.
```

