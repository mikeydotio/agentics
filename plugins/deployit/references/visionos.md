# visionOS Deploy Reference

visionOS deploys follow the same path as iOS. This document covers the
differences.

## How it works

The plugin archives with `--destination 'generic/platform=visionOS'` and
exports using `ExportOptions.visionos.plist` (Development method, automatic
signing). The resulting `.ipa` is staged and served via the same
`itms-services://` manifest flow as iOS. Vision Pro installs it OTA from
the Tailscale-served URL.

## UDID registration

Vision Pro shows up in Xcode as a paired device. Registration works the
same way as iPhone: connect the device (USB or wireless pairing), run any
target on it from Xcode once, and the UDID is registered with the team's
Development provisioning profile. Then `/deployit deploy --platform visionos`
works.

## First-install trust flow

Identical to iOS:
1. Settings → General → VPN & Device Management → trust the developer team.
2. Launch the app.

Subsequent installs proceed silently.

## Archive size

Reality Composer Pro assets and spatial audio resources can significantly
balloon the archive size compared to equivalent iOS assets. This is a
project concern, not a plugin concern — the plugin stages whatever the
archive produces. Large archives increase the round-trip time.

## No visionOS target in the consuming repo

If the consuming repo has no visionOS scheme, `/deployit deploy --platform visionos`
will fail at the archive step:

```
xcodebuild: error: The specified scheme does not contain any buildable targets for visionOS.
```

The CLI surfaces this as `ok: false` with the scheme-not-found message.
Adding a visionOS target to the consuming project is outside the scope of
this plugin.

## Simulator deploys

visionOS Simulator builds are not staged for OTA install (there is no
install flow for a simulator). Use Xcode directly for simulator testing.
`/deployit deploy --platform visionos` always targets a physical device.
