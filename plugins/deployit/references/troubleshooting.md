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
| `/deployit deploy` fails: "no recognised Xcode project layout in cwd" | Not in the consuming repo's root, or the repo doesn't match either supported layout | `cd` to the root of either a monorepo (containing `<Name>.xcworkspace` + `Apps/<Name>-<Platform>/project.yml`) or a single-app project (containing `<Name>.xcodeproj` + `./project.yml`). |
| `/deployit deploy` fails: "multiple schemes match" | More than one scheme targets the requested platform | The CLI returns a `questions` array; the orchestrator presents the choice via `AskUserQuestion`. Or pass `--scheme <NAME>` explicitly. |
| `git push` to deployit-index conflicts repeatedly | Two machines deployed near-simultaneously | Each attempt re-pulls a fresh `origin/main` and retries (up to 3×); the generated commit is never discarded. If it still can't publish, the commit is preserved on a `deploy/<id>` branch and its PR URL printed — merge that to publish. |
| Deploy publish fails: `GH013 … Changes must be made through a pull request` (or `push declined due to repository rule violations`) | A branch-protection ruleset (e.g. org-wide `protect-main`) blocks direct pushes to `deployit-index`'s `main` | Expected under a ruleset — deployit now auto-publishes via a PR (`publish = "auto"`, the default) and, with `auto_merge = true` (default), merges it for you. The build renders on the listing once the PR lands. See `references/index-publishing.md`. |
| Deploy publish fails: `GH006 … protected branch hook declined` | A classic protected-branch rule (required reviews/status checks) on `deployit-index/main` | Same PR-publish fallback as GH013. If a required **review** blocks the auto-merge, the PR is left open with its URL printed — merge it (or configure a dedicated deploy identity that can). |
| Deploy shows `index: pending PR merge — <url>` and the build isn't on the listing | `auto_merge = false`, or the auto-merge hit a conflict with a concurrent deploy | The build is already installable at its direct URL (shown as `install:`); the **listing** updates when you merge the printed PR. To make publish fully hands-off, set `[index] auto_merge = true`. |
| Deploy still dead-ends at publish with `GH013`/`GH006` **even though the PR-fallback fix was merged** | The plugin cache is keyed by **version string**: the fix landed under an already-cached version without a version bump, so Claude Code never re-extracts it and keeps running the pre-fix `deployit-cli` — the plugin *reports* the fixed version while *executing* unfixed code. | The durable fix is a marketplace **version bump** (never mutate a released version's content in place — see the repo's `CLAUDE.md` › Plugin Version Sync). To rescue an install already stuck on the stale version, force a re-extract: `rm -rf ~/.claude/plugins/cache/agentics/deployit/<ver>/`, then update the marketplace (or restart Claude Code) so the bumped version extracts. Afterwards run `/deployit redeploy` so the daemon's `_plugin_root` symlink advances to the new code. |
| Web UI swipe-to-delete (or `/deployit gc`) fails from the daemon: "could not open PR" / gh not found | The launchd daemon's minimal PATH can't resolve `gh` (Homebrew lives outside it) | deployit resolves `gh` to an absolute path (Homebrew/Intel locations) and pins the git credential helper to it. If `gh` is installed elsewhere, set `DEPLOYIT_GH_BIN` to its absolute path in the daemon's environment. The delete leaves local files intact until the index change lands. |
| Backend is up but listing page is stale | Index pull failed (network issue) | The listing shows a "stale since \<timestamp\>" banner. Force a refresh: `curl -X POST https://<host>.<tailnet>.ts.net/deployit/_internal/refresh` |
| launchd keeps restarting the backend rapidly | Backend crashes on startup | Check `~/Library/Logs/deployit/backend.err.log`. Common cause: port 8729 already in use by another process. `lsof -i :8729` to identify it. |
| macOS app blocked by Gatekeeper | Not notarized (Developer ID signed but no stapled ticket) | Right-click → Open in Finder for a one-time approval. Or enable notarization in `config.toml` and redeploy. See `references/macos.md`. |
| notarytool submission fails | Invalid or expired App Store Connect API key | Re-download the `.p8` key from App Store Connect and re-run `xcrun notarytool store-credentials deployit-notary ...`. |
| Sparkle update fails the signature check | Origin Macs signed with different EdDSA keys, but the app embeds one `SUPublicEDKey` | Share ONE private key across all your Macs via `private_key_path` (see `references/sparkle.md`). Re-deploy from the offending Mac. |
| macOS deploy produced no appcast / `.zip` | `[macos.sparkle] enabled = false`, or `sign_update` / the key wasn't found (deploy logs a "skipping Sparkle" warning) | Set `enabled = true` and a valid `sign_update_path` + `private_key_path` in `config.toml`; check the deploy stderr / `backend.err.log` for the skip reason, then re-deploy. |
| Sparkle says "you're up to date" despite a newer build | `CFBundleVersion` did not increase between builds (Sparkle compares `sparkle:version`) | Ensure the host repo bumps the build number per build; deployit reads `CFBundleVersion` from the archived `Info.plist`. |
| visionOS deploy fails: scheme not found | Consuming repo has no visionOS target | Add a visionOS target to the Xcode project, or do not pass `--platform visionos`. |
| Build-number regresses (e.g. build 10 after build 15) | Archive pre-action called twice (once by pre-action, once by deploy script) | Remove any explicit bump-script call from the deploy wrapper. The Archive pre-action already fires for `xcodebuild archive`. |
| Deploy shows `post_test: no .deployit/post-deploy-test.sh — skipped` but you expected a suite to run | The opt-in script is missing or mis-named (deployit looks for exactly `<project>/.deployit/post-deploy-test.sh`) | Create it at that path (see `references/post-deploy-tests.md`). It runs out-of-band after every deploy; a `not_configured` badge on the build page means the same thing. |
| Build page shows `Tests running…` long after the suite should have finished | The detached run was killed (e.g. machine slept/rebooted mid-suite) or the script hangs | The status JSON at `<state>/posttest/<build_id>.json` carries `pid` + `started_at` — `kill -0 <pid>` to check liveness. Check `<state>/logs/posttest-<build_id>.log` for where it stalled; re-deploy to re-run. |
| Post-deploy test reports `error` (not `failed`) | deployit couldn't launch the script (unreadable, or `bash` unavailable) | Confirm `.deployit/post-deploy-test.sh` is a readable shell script; run `bash .deployit/post-deploy-test.sh` by hand to reproduce. |

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
