# Troubleshooting Reference

| Symptom | Cause | Fix |
|---|---|---|
| `tailscale is not up` | Tailscale daemon stopped | Open the Tailscale menubar app, or run `sudo tailscale up`. |
| Archive fails: "No profiles for \<bundle ID\> were found" | Apple ID 2FA session expired | Xcode → Settings → Accounts → select Apple ID → re-enter 2FA on iPhone. |
| Archive fails: `errSecInteractionNotAllowed` | Login keychain locked | `security unlock-keychain ~/Library/Keychains/login.keychain-db` |
| Install dialog shows blank version string | `bundle-version` in manifest doesn't match `CFBundleShortVersionString` | Verify `MARKETING_VERSION` is set in the consuming repo's `project.yml` (or equivalent xcconfig). |
| Device shows "Cannot Install" | UDID not in Development profile, or conflicting bundle ID already on device | Connect device to Xcode and run any target once to register UDID. Delete any conflicting install. |
| Install URL returns 404 | Tailscale Serve not configured, or backend not running | `tailscale serve status` to confirm proxy. `launchctl list \| grep deployit` to check agent. Logs at `~/Library/Logs/deployit/backend.err.log`. |
| `tailscale serve` reports "Path serving not supported" | Mac App Store Tailscale variant; filesystem path serving is sandboxed out | Use the proxy form (`tailscale serve --bg 8729`). Bootstrap handles this automatically. |
| `/deployit deploy` fails: "no workspace found" | Not in the correct directory | `cd` to the consuming repo's root (where the `.xcworkspace` lives) and re-run. |
| `/deployit deploy` fails: "multiple schemes match" | More than one scheme targets the requested platform | The CLI returns a `questions` array; the orchestrator presents the choice via `AskUserQuestion`. Or pass `--scheme <NAME>` explicitly. |
| `git push` to deployit-index conflicts repeatedly | Two machines deployed near-simultaneously | The CLI retries 3×. If it keeps failing, run `/deployit deploy` again — the push is the only step that failed; the local IPA is already staged. |
| Backend is up but listing page is stale | Index pull failed (network issue) | The listing shows a "stale since \<timestamp\>" banner. Force a refresh: `curl -X POST https://<host>.<tailnet>.ts.net/deployit/_internal/refresh` |
| launchd keeps restarting the backend rapidly | Backend crashes on startup | Check `~/Library/Logs/deployit/backend.err.log`. Common cause: port 8729 already in use by another process. `lsof -i :8729` to identify it. |
| macOS app blocked by Gatekeeper | Not notarized (Developer ID signed but no stapled ticket) | Right-click → Open in Finder for a one-time approval. Or enable notarization in `config.toml` and redeploy. See `references/macos.md`. |
| notarytool submission fails | Invalid or expired App Store Connect API key | Re-download the `.p8` key from App Store Connect and re-run `xcrun notarytool store-credentials deployit-notary ...`. |
| visionOS deploy fails: scheme not found | Consuming repo has no visionOS target | Add a visionOS target to the Xcode project, or do not pass `--platform visionos`. |
| Build-number regresses (e.g. build 10 after build 15) | Archive pre-action called twice (once by pre-action, once by deploy script) | Remove any explicit bump-script call from the deploy wrapper. The Archive pre-action already fires for `xcodebuild archive`. |

## Log locations

| Log | Purpose |
|---|---|
| `~/Library/Logs/deployit/backend.log` | stdout from the HTTP backend |
| `~/Library/Logs/deployit/backend.err.log` | stderr from the HTTP backend (start here) |

## Quick diagnostics

```bash
# Is the backend running?
launchctl list | grep deployit

# Is the proxy configured?
tailscale serve status

# Is the backend reachable?
curl -s https://<host>.<tailnet>.ts.net/deployit/_healthz

# Which process owns port 8729?
lsof -i :8729
```
