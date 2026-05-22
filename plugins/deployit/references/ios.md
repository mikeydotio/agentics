# iOS Deploy Reference

## Why Development-method OTA install works

iOS accepts the `itms-services://` payload if the device's UDID is embedded
in the provisioning profile used to sign the IPA. Development-method profiles
include every device registered with the team — no Ad-Hoc profile, no
TestFlight, no App Store Connect involvement.

Tailscale Serve provides a Let's Encrypt-backed HTTPS URL
(`https://<host>.<tailnet>.ts.net/deployit/`). iOS requires HTTPS for the
manifest URL; the tailnet hostname satisfies that constraint without any
additional certificate setup.

## Build-number bumping

Build-number bumping is the consuming repo's responsibility, not the plugin's.

If the repo uses an Archive pre-action script (e.g., Lillist's
`Tools/Deploy/bump-build-number.sh`), that script fires automatically during
`xcodebuild archive` — both from Xcode and from the CLI. The plugin reads the
resolved `CFBundleVersion` from the exported `Info.plist` after the archive
completes; it does not write to `BuildNumber.xcconfig` or any other file.

Do not call the bump script inside `deploy-ios.sh` or an equivalent wrapper.
The Archive pre-action already fires; a second call double-bumps.

## First-install trust flow

On the first install from a fresh developer profile, iOS shows an
"Untrusted Developer" alert and refuses to launch the app:

1. Settings → General → VPN & Device Management
2. Tap the developer team name
3. Tap **Trust "<team name>"** → confirm
4. Return to the Home Screen and launch the app

Every subsequent install from the same team profile proceeds silently.

## UDID registration

If the device's UDID is not in the Development provisioning profile, the
archive succeeds but the install dialog shows "Cannot Install" or the IPA
installs and refuses to launch.

Fix: connect the device to the Mac, open Xcode, and run any target on the
device once. Xcode registers the UDID with the team profile automatically.
Then re-run `/deployit deploy`.

## Common failure recipes

### Apple ID 2FA session expired

**Symptom:** Archive fails with "No profiles for <bundle ID> were found."

**Fix:**
1. Open Xcode → Settings (⌘,) → Accounts tab.
2. Select your Apple ID, click the refresh icon or re-enter your password to
   trigger a 2FA prompt.
3. Complete 2FA on your iPhone.
4. Re-run `/deployit deploy`.

### Login keychain locked

**Symptom:** Archive fails with `errSecInteractionNotAllowed`.

**Fix:**
```bash
security unlock-keychain ~/Library/Keychains/login.keychain-db
```

Enter your macOS login password when prompted, then re-run `/deployit deploy`.

### Install dialog shows blank version string

**Symptom:** The OTA manifest's `bundle-version` key doesn't match
`CFBundleShortVersionString` in the installed app.

**Fix:** Verify `MARKETING_VERSION` is set correctly in the consuming repo's
`project.yml` (or equivalent). The plugin derives `marketing_version` from the
built `Info.plist`; if the project doesn't set it, the manifest entry is empty.

### "Cannot Install" on device

Two common causes:

1. **UDID not in profile** — see UDID registration above.
2. **Conflicting bundle ID already installed** — a previous install from a
   different signing identity (e.g., an App Store build) can block a
   Development-signed install. Delete the existing app on the device and
   retry.
