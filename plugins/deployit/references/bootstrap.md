# Bootstrap Reference

One-time per-machine setup for deployit. Run `/deployit bootstrap` — it is
idempotent and safe to re-run after plugin updates.

## What bootstrap does

In order:

1. Verifies `tailscale` is installed and the daemon is reachable (`tailscale status`).
2. Creates `~/Library/Application Support/deployit/{index,serve,logs}`.
3. Clones `mikeydotio/deployit-index` into `index/` if not already present.
4. Writes `config.toml` (derived from `tailscale status`; preserves existing keys on re-run).
5. Installs the launchd agent at
   `~/Library/LaunchAgents/com.mikeydotio.deployit.backend.plist` and
   loads it (`launchctl bootstrap gui/$(id -u) <plist>`). On re-run, the
   plist is rewritten with the current plugin path and the agent is
   reloaded.
6. Runs `tailscale serve --bg 8729` if the proxy is not already configured.
7. Polls `GET /deployit/_healthz` until the backend responds (up to 30 s).
8. Prints the bookmark URL: `https://<host>.<tailnet>.ts.net/deployit/`

## Prerequisites

### Required for all platforms

- **Tailscale installed and daemon up.** The Mac App Store variant works;
  the macOS system extension variant also works. Confirm with
  `tailscale status`.
- **`gh` CLI authenticated.** The plugin pushes to `mikeydotio/deployit-index`
  via HTTPS using the `gh` credential helper. Run `gh auth status` to verify.

### Required for iOS and visionOS deploys (not needed for bootstrap itself)

- An **Apple Developer team membership** with at least one registered device.
- The target device's **UDID registered** in the team's Development
  provisioning profile. This happens automatically when you run any target
  on the device from Xcode at least once.
- A **`Signing.local.xcconfig`** (or equivalent) in the consuming repo's
  `Apps/Config/` directory that supplies `LOCAL_DEVELOPMENT_TEAM = <10-char-team-id>`.
  See the consuming repo's `Signing.local.xcconfig.example`.

### Required for macOS notarized deploys (not needed for bootstrap itself)

- `xcrun notarytool store-credentials` must have been run once with a valid
  App Store Connect API key. See `references/macos.md`.

## Optional

```bash
brew install qrencode
```

With `qrencode` installed, `/deployit deploy` prints a terminal QR code for
the install URL. The deploy succeeds without it; the URL is printed either way.

## What to expect

Bootstrap prints the bookmark URL when it finishes:

```
Bootstrap complete.
Bookmark this URL on your iPhone (Safari):
  https://<host>.<tailnet>.ts.net/deployit/
```

Open that URL in Safari on your iPhone the first time to verify reachability.
The page will be empty until the first deploy succeeds.

## Re-running

Safe at any time. `config.toml` is preserved (existing keys are not
overwritten). The launchd plist is regenerated with the current plugin path
and the agent is reloaded. Tailscale Serve state is checked and left
unchanged if already correct.

## Tearing down (rare)

```bash
# Remove Tailscale Serve proxy
tailscale serve --https=443 off

# Stop and unload the launchd agent
launchctl bootout gui/$(id -u)/com.mikeydotio.deployit.backend

# Remove per-machine state (does NOT affect other machines or the index repo)
rm -rf ~/Library/LaunchAgents/com.mikeydotio.deployit.backend.plist
rm -rf ~/Library/Application\ Support/deployit
rm -rf ~/Library/Logs/deployit
```

See also `references/tailscale-serve.md` for Tailscale-specific teardown.
