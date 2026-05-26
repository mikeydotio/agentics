# Tailscale Serve Reference

## Why the proxy architecture

The Mac App Store variant of Tailscale runs in a sandbox and cannot serve
filesystem paths directly (see https://tailscale.com/kb/1065/macos-variants).
Both the App Store variant and the system extension variant support proxying
to a local HTTP backend.

deployit uses `tailscale serve --bg 8729` to proxy
`https://<host>.<tailnet>.ts.net/deployit/` → `http://127.0.0.1:8729`.
The backend on port 8729 is a Python HTTP service managed by launchd
(`com.mikeydotio.deployit.backend`). From the iPhone's perspective, it is
a single TLS connection to the tailnet hostname backed by a Let's Encrypt
certificate — no self-signed cert warnings.

## Verifying the proxy

```bash
tailscale serve status
```

Expected output includes a line like:
```
https://<host>.<tailnet>.ts.net/
|-- / proxy http://127.0.0.1:8729
```

If the proxy is missing, re-run `/deployit bootstrap`.

## Verifying MIME types (run once after first deploy)

```bash
# Replace with your actual URL
curl -sI "$DEPLOYIT_URL/<build_id>/manifest.plist" | grep -i content-type
curl -sI "$DEPLOYIT_URL/<build_id>/app.ipa"         | grep -i content-type
```

`manifest.plist` should be `application/x-plist` or `text/xml` — iOS accepts
both. The `.ipa` should be `application/octet-stream`. If Tailscale Serve is
returning `text/html` or something unexpected, the backend may be serving the
wrong directory root.

## Reboot behavior

- **Tailscale Serve config** — persists across reboots. The daemon restores
  the proxy configuration on startup. No action needed after a reboot.
- **deployit backend** — managed by launchd with `KeepAlive = true`. It
  starts automatically at login and is restarted if it crashes. Check its
  status with:
  ```bash
  launchctl list | grep deployit
  ```
  Logs are at `~/Library/Logs/deployit/backend.log` and
  `~/Library/Logs/deployit/backend.err.log`.

## Path prefix

All deployit URLs use the `/deployit/` prefix:

```
https://<host>.<tailnet>.ts.net/deployit/                       # listing
https://<host>.<tailnet>.ts.net/deployit/<id>/                  # per-build landing page
https://<host>.<tailnet>.ts.net/deployit/<id>/manifest.plist
https://<host>.<tailnet>.ts.net/deployit/<id>/<App>.ipa
https://<host>.<tailnet>.ts.net/deployit/_healthz               # liveness probe
https://<host>.<tailnet>.ts.net/deployit/manifest.webmanifest   # PWA manifest
https://<host>.<tailnet>.ts.net/deployit/icon.svg               # SVG favicon
https://<host>.<tailnet>.ts.net/deployit/apple-touch-icon.png   # iOS Home Screen icon
https://<host>.<tailnet>.ts.net/deployit/icons/icon-{192,512,maskable-512}.png
```

The backend routes all `/deployit/` paths; anything outside that prefix
returns 404 (intentional — the root is not a general-purpose file server).
Static PWA assets (manifest, icons) come from a closed allowlist in the
backend — adding new ones requires editing `_STATIC_ASSETS` in `deployit-backend`.

## Installing the listing as a PWA on iOS

The listing page is an installable Progressive Web App. To put it on the
iPhone Home Screen as a standalone app icon:

1. Run `/deployit url` and open the URL in **iOS Safari** (not Chrome/Firefox
   on iOS — only Safari supports Add-to-Home-Screen for PWAs).
2. Tap the Share button → **Add to Home Screen**.
3. The icon and name preload from the web manifest — accept the defaults.

Launching from the Home Screen icon opens deployit chromeless (no Safari
toolbar) with a translucent status bar, respects the notch and Home
indicator via `safe-area-inset`, and stays inside the `/deployit/` scope so
tapping a build still uses the standalone window for the install page.

## Tearing down Tailscale Serve

```bash
# Remove the HTTPS proxy
tailscale serve --https=443 off

# Stop the backend launchd agent
launchctl bootout gui/$(id -u)/com.mikeydotio.deployit.backend
```

This leaves the launchd plist on disk. To also remove it:
```bash
rm ~/Library/LaunchAgents/com.mikeydotio.deployit.backend.plist
```

Re-running `/deployit bootstrap` after this restores everything.

## Multiple machines

Each machine runs its own Tailscale Serve proxy and its own backend. The
listing at `GET /deployit/` on any given machine shows all builds across
the tailnet (pulled from the shared index repo), but install links point at
the origin machine's URL. If that machine is asleep or offline, that
specific build is not installable — the listing entry remains visible but
the install link will fail.
