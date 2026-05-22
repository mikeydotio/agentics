---
name: deployit
description: Use when the user wants to deploy an iOS / macOS / visionOS app to their tailnet for OTA install on their own devices. Commands are `/deployit bootstrap` (one-time per Mac), `/deployit deploy [--platform ios|macos|visionos] [--scheme NAME]`, `/deployit list`, `/deployit url`, `/deployit status`, and `/deployit gc`. Replaces hand-rolled `Tools/Deploy/deploy-ios.sh`-style scripts.
argument-hint: <bootstrap | deploy [--platform P] [--scheme S] | list | url | status | gc>
---

# deployit Orchestrator

`/deployit` archives the current Xcode workspace, exports a
Development- or Developer-ID-signed binary, stages it under
`~/Library/Application Support/deployit/serve/`, appends an entry
to the shared `mikeydotio/deployit-index` repo, and points the
user at a Tailscale-served URL.

**Router:** `bash ${CLAUDE_PLUGIN_ROOT}/bin/deployit-router.sh <ARGUMENTS>`

## Hard rules

1. Route every command through the router. Never call `deployit-cli` directly.
2. If the CLI returns `ok: false`, show the `display` (or `message`) and stop.
3. Never push to the index repo from this orchestrator; that is the CLI's job.
4. Build-number bumping is the host repo's responsibility. Lillist's
   `Tools/Deploy/bump-build-number.sh` Archive pre-action stays; the plugin
   reads the resolved `CFBundleVersion` from the built `Info.plist`.

## Generic flow

1. **Route**: `bash ${CLAUDE_PLUGIN_ROOT}/bin/deployit-router.sh <ARGUMENTS>`
2. **Check `ok`**: if false, show `display` and stop.
3. **Display**: show the CLI's `display` field on success.

## Per-command notes

- **bootstrap** is idempotent. Run it once on each Mac, and re-run any time
  the plugin version changes (it rewrites the launchd plist with the
  current plugin path).
- **deploy** auto-detects project + bundle ID + marketing version from
  `*.xcworkspace` + `Apps/*/project.yml`. If the CLI fails with a "no
  workspace" or "no project.yml" error, the user is likely in the wrong
  directory — confirm with them before suggesting a scheme override.
- **list / status / url** are read-only; no confirmations needed.
- **gc** requires `--keep N` or `--older-than D` — never run unqualified.

## Question loop

When the CLI returns a `questions` array (e.g., multiple schemes match the
requested platform), process each in order:

```
For each question in questions:
  1. Call AskUserQuestion with the question's header, question, and options
  2. Map the user's selection through flag_mapping or command_mapping
  3. Collect resulting flags
```

After processing all questions, re-run the router with the collected flags
appended to the original command.

## References

- `references/bootstrap.md` — per-machine one-time setup walkthrough
- `references/ios.md` — iOS specifics: signing, UDID registration, Trust flow
- `references/macos.md` — macOS Developer-ID signing + notarytool
- `references/visionos.md` — visionOS specifics (mostly ≡ iOS)
- `references/tailscale-serve.md` — proxy config + Mac App Store variant quirks
- `references/troubleshooting.md` — common archive/export failures + recipes
