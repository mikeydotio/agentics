# macOS Deploy Reference

## Signing method

The plugin uses **Developer ID** signing for macOS builds by default
(`ExportOptions.macos.plist` sets `method = developer-id`). This allows the
resulting `.dmg` to be distributed outside the Mac App Store to any Mac in
the tailnet.

Development-method signing also works if you don't have a Developer ID
certificate, but Gatekeeper will quarantine the app on Macs that haven't
opened it before (see below).

## Gatekeeper behavior without notarization

On a Mac that has never run the app, Gatekeeper will block it at first launch
with "Cannot be opened because it is from an unidentified developer." The
workaround is to right-click → Open in Finder. After that first approval the
app opens normally.

To avoid the right-click dance entirely, notarize the build (see below).
Notarization embeds an Apple-issued ticket in the app; Gatekeeper accepts it
on any Mac without quarantine.

## Setting up notarization

Notarization requires a one-time credential setup per Mac. It does not require
any changes to the consuming repo.

### 1. Create an App Store Connect API key

Go to: https://appstoreconnect.apple.com/access/integrations/api

- Click **Generate API Key**.
- Role: **Account Holder** (or at minimum Developer + App Manager).
- Download the `.p8` file. Note the **Issuer ID** and **Key ID** shown on
  the page. The `.p8` file can only be downloaded once.

### 2. Store credentials with notarytool

```bash
xcrun notarytool store-credentials deployit-notary \
  --key /path/to/AuthKey_<KEY_ID>.p8 \
  --key-id <KEY_ID> \
  --issuer <ISSUER_ID>
```

The profile name `deployit-notary` is what the plugin looks for by default.
If you use a different name, set it in `config.toml` (see step 3).

### 3. Enable notarization in config.toml

```toml
[macos]
notarize = true
notary_profile = "deployit-notary"
```

`config.toml` lives at `~/Library/Application Support/deployit/config.toml`.
Edit it directly or re-run `/deployit bootstrap` (bootstrap preserves
existing keys, so add these lines manually before re-running, or add them
after).

## What happens at deploy with notarization enabled

1. `xcodebuild archive` → `xcodebuild -exportArchive` → `.app`
2. `hdiutil create` wraps the `.app` in a `.dmg`
3. `xcrun notarytool submit <dmg> --keychain-profile deployit-notary --wait`
   — blocks until Apple's notarization queue processes the submission
   (typically 1–5 minutes)
4. `xcrun stapler staple <dmg>` — embeds the notarization ticket in the `.dmg`
5. The stapled `.dmg` is staged to `serve/<build_id>/<App>.dmg`

After stapling, the `.dmg` is self-contained: Gatekeeper accepts it offline,
without contacting Apple's servers.

## Install flow on the target Mac

The per-build landing page at `https://<host>.<tailnet>.ts.net/deployit/<build_id>/`
shows a **Download** button. Clicking it downloads the `.dmg` directly.
Mount, drag to Applications, launch — same as any other Developer ID app.

## Notarization failures

If `notarytool submit` fails, the CLI surfaces the full Apple error log.
Common causes:

- **Hardened Runtime entitlement issues** — the `.app` references an
  entitlement that requires justification. Check the notarization log for
  the specific entitlement.
- **Invalid or expired API key** — re-download the `.p8` and re-run
  `notarytool store-credentials`.
- **Network timeout** — Apple's queue was slow; re-run `/deployit deploy`.
  The upload is idempotent (Apple deduplicates by content hash).
