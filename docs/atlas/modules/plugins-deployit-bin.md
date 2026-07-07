---
module: plugins/deployit/bin
summary: "deployit's runtime: CLI orchestrator, HTTP install/listing daemon, and GitHub-release publisher."
read_when: "Changing deployit subcommands, the deploy/publish flow, or backend endpoints"
sources:
  - path: plugins/deployit/bin/deployit-backend
    blob: 7938f381f5c77f195c95d8f7a120b4d38cd8fc7e
  - path: plugins/deployit/bin/deployit-cli
    blob: ea8f46203210b4801b7783512ed21732f17fa54b
  - path: plugins/deployit/bin/deployit-release
    blob: 48312b67fd29de6982d480529961efb7df6dc8a9
  - path: plugins/deployit/bin/deployit-router.sh
    blob: 344168329e019299a535c6e7c327e726f0cb5d03
generator: cartographer/4
baseline: cb09ceb006e3fb4759a91d64d9e6655e67d04bf7
---

# Module: plugins/deployit/bin

## Purpose

This module is deployit's entire runtime: `deployit-cli` orchestrates archive -> export -> stage -> notarize -> index-push -> GitHub-release for one signed build, `deployit-backend` is the long-running, launchd-supervised HTTP daemon that serves the install/listing/appcast web UI other devices hit, and `deployit-release` is a standalone script the CLI shells out to for publishing. Together they let one Mac deploy a build once and make it fetchable tailnet-wide, coordinating with the semver plugin only via a discovered subprocess (never an import — see _find_semver_cli) and treating a separate git-backed index repo as the sole shared state. If this module vanished, deployit would have no runtime at all — deployit-router.sh, the only other piece wired to the /deployit skill, does nothing but exec deployit-cli.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `Handler` | class | `plugins/deployit/bin/deployit-backend:447` | BaseHTTPRequestHandler subclass registered with ThreadingHTTPServer; `root` is bound per-instance by make_handler, not `__init__`. |
| `JsonArgumentParser` | class | `plugins/deployit/bin/deployit-cli:52` | argparse subclass whose .error() calls fail() instead of printing usage and exit(2) — keeps CLI errors one JSON object. |
| `JsonArgumentParser` | class | `plugins/deployit/bin/deployit-release:55` | argparse subclass whose .error() calls fail() instead of printing usage and exit(2) — keeps errors one JSON object. |
| `build_parser` | def | `plugins/deployit/bin/deployit-cli:1644` | Builds deployit's full argparse tree; each subcommand's func default is how main dispatches to a cmd_* handler. |
| `build_parser` | def | `plugins/deployit/bin/deployit-release:230` | Builds deployit-release's argparse tree: exactly one of --app/--zip plus repo/target/title/prerelease/clobber/attach. |
| `cmd_bootstrap` | def | `plugins/deployit/bin/deployit-cli:1058` | One-time per-machine setup: derives the tailnet base_url, writes config.toml, clones the index, installs launchd. Idempotent. |
| `cmd_bump` | def | `plugins/deployit/bin/deployit-cli:1280` | Non-interactively delegates a semver version bump to the semver plugin's CLI, pre-authorizing --dirty-action include. |
| `cmd_deploy` | def | `plugins/deployit/bin/deployit-cli:1081` | Archives, exports, stages, notarizes (macOS), pushes the index entry, and optionally publishes a GitHub release: the pipeline's core. |
| `cmd_gc` | def | `plugins/deployit/bin/deployit-cli:1446` | Archives (never deletes from the index) this machine's builds beyond --keep/--older-than, then rmtrees their local serve/ dirs. |
| `cmd_list` | def | `plugins/deployit/bin/deployit-cli:1425` | Read-only: lists recent local-index builds, optionally filtered by --platform/--project. |
| `cmd_preflight` | def | `plugins/deployit/bin/deployit-cli:1218` | Read-only: reports whether a semver bump is required before the next deploy of this (bundle_id, platform); never mutates. |
| `cmd_redeploy` | def | `plugins/deployit/bin/deployit-cli:1585` | Re-points the daemon's plugin-root symlinks, repairs a legacy plist, restarts launchd, waits for health, runs verify-live.sh. |
| `cmd_release_context` | def | `plugins/deployit/bin/deployit-cli:1322` | Read-only: gathers repo/tag/commits/closed-issues facts for release notes; degrades to commits-only without gh. |
| `cmd_rm` | def | `plugins/deployit/bin/deployit-cli:1487` | Deletes one local build or product from the shared index and its serve/ dir; backs the web UI's swipe-to-delete. |
| `cmd_status` | def | `plugins/deployit/bin/deployit-cli:1391` | Reports backend health via _healthz plus this machine's most recent local deploys. |
| `cmd_url` | def | `plugins/deployit/bin/deployit-cli:1384` | Prints this machine's listing base URL, read from config.toml. |
| `do_DELETE` | def | `plugins/deployit/bin/deployit-backend:578` | Entry point for DELETE requests; wraps _dispatch_delete and always emits a JSON response, catching every exception as a 500. |
| `do_GET` | def | `plugins/deployit/bin/deployit-backend:481` | Entry point for GET requests; wraps _dispatch_get and always emits a response, catching every exception as a 500 JSON error. |
| `do_POST` | def | `plugins/deployit/bin/deployit-backend:563` | Entry point for POST requests; wraps _dispatch_post and always emits a JSON response, catching every exception as a 500. |
| `error` | def | `plugins/deployit/bin/deployit-cli:53` | Routes an argparse parsing error through fail() so usage errors stay a single JSON object, not argparse's default exit(2). |
| `error` | def | `plugins/deployit/bin/deployit-release:56` | Routes an argparse parsing error through fail() so usage errors stay a single JSON object. |
| `fail` | def | `plugins/deployit/bin/deployit-cli:42` | Terminal error path for the whole CLI: prints {ok:false, display, ...extra} and exits 1 — the only way to abort a subcommand. |
| `fail` | def | `plugins/deployit/bin/deployit-release:49` | Terminal error path: prints {ok:false, display, ...extra} and exits 1 — the only way this script should abort. |
| `log_message` | def | `plugins/deployit/bin/deployit-backend:450` | Suppresses access-log noise for /deployit/_healthz; every other request is logged to stderr. |
| `main` | def | `plugins/deployit/bin/deployit-backend:614` | Process entry point: parses --port/--root/--plugin-root, syncs the _plugin_root symlink, then blocks in serve_forever(). |
| `main` | def | `plugins/deployit/bin/deployit-cli:1705` | Process entry point: parses argv, prints --version, or dispatches to the matched subcommand's func. |
| `main` | def | `plugins/deployit/bin/deployit-release:250` | Process entry point: resolves the version/tag, verifies Developer ID signing, then runs gh release create/edit/upload. |
| `make_handler` | def | `plugins/deployit/bin/deployit-backend:610` | Builds a fresh Handler subclass binding `root` — the only way to inject per-run state into BaseHTTPRequestHandler. |
| `mutate` | def | `plugins/deployit/bin/deployit-cli:1455` | cmd_gc's mutation for _commit_and_push_index: archives builds beyond the gc cutoff in place and returns the commit message. |
| `mutate` | def | `plugins/deployit/bin/deployit-cli:1517` | cmd_rm's mutation for _commit_and_push_index: removes matching local build/product entries and returns the commit message. |
| `not_implemented` | def | `plugins/deployit/bin/deployit-cli:48` | Fails a subcommand with a standard 'not implemented yet' message; a placeholder for stubbed commands. |
| `ok` | def | `plugins/deployit/bin/deployit-cli:37` | Prints {...payload, ok:true} — the CLI's single JSON success object every non-failing subcommand must end with. |
| `ok` | def | `plugins/deployit/bin/deployit-release:44` | Prints {...payload, ok:true} — this script's single JSON success object on the happy path. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `_append_to_index` | def | `plugins/deployit/bin/deployit-cli:877` | Deploy hot path's only writer to the shared builds.json index: pull/prepend/prune/commit/push with conflict-retry (plugins/deployit/bin/deployit-cli:885-917); called from cmd_deploy (plugins/deployit/bin/deployit-cli:1161) — guards the index's consistency invariant. |
| `_derive_metadata` | def | `plugins/deployit/bin/deployit-cli:286` | Central project-layout detector (Apps-layout vs single-app Xcode project) that cmd_deploy and cmd_preflight both depend on (plugins/deployit/bin/deployit-cli:1085,1229) to resolve bundle id, marketing version, and xcodebuild container args. |
| `_find_semver_cli` | def | `plugins/deployit/bin/deployit-cli:398` | Sole cross-plugin lookup for the semver plugin's CLI (env override -> sibling plugin -> ~/.claude glob), used by cmd_bump (plugins/deployit/bin/deployit-cli:1295) — the only bridge from deployit into the semver plugin. |
| `_install_launchd` | def | `plugins/deployit/bin/deployit-cli:203` | Writes and (re)loads the launchd plist that runs deployit-backend as a persistent daemon; called from both cmd_bootstrap and cmd_redeploy (plugins/deployit/bin/deployit-cli:1068,1609) — the sole mechanism that starts/restarts the backend service. |
| `_next_versions` | def | `plugins/deployit/bin/deployit-cli:380` | Computes the major/minor/patch semver successor labels cmd_bump presents to the operator (plugins/deployit/bin/deployit-cli:1270); a wrong computation would mislead which version a human picks to ship, even though semver-cli performs the actual bump. |
| `_parse_owner_repo` | def | `plugins/deployit/bin/deployit-cli:73` | Extracts owner/repo from a git remote URL (SSH or HTTPS, with or without .git); the sole source of GitHub repo identity for cmd_release_context (plugins/deployit/bin/deployit-cli:73). |
| `_parse_owner_repo` | def | `plugins/deployit/bin/deployit-release:179` | Extracts owner/repo from git remote get-url origin when --repo isn't passed — the fallback repo resolution behind every gh call this script makes (plugins/deployit/bin/deployit-release:179). |
| `_parse_semver_config` | def | `plugins/deployit/bin/deployit-cli:338` | Parses .semver/config.yaml's flat key:value format directly (deliberately not importing the semver plugin) — the sole read path behind _semver_active_version, _semver_prefix, and preflight's target_branch (plugins/deployit/bin/deployit-cli:338). |
| `_parse_semver_config` | def | `plugins/deployit/bin/deployit-release:69` | Parses .semver/config.yaml directly (mirroring bin/deployit-cli rather than importing it) — feeds _semver_version, the first rung of _resolve_version_and_tag's version ladder (plugins/deployit/bin/deployit-release:69). |
| `_publish_github_release` | def | `plugins/deployit/bin/deployit-cli:1005` | The only bridge from deployit-cli into bin/deployit-release: invokes it as a subprocess to publish the staged release zip, called once from cmd_deploy (plugins/deployit/bin/deployit-cli:1171); deliberately never raises so a release failure can't roll back an already-deployed tailnet build. |
| `_read_archive_build_number` | def | `plugins/deployit/bin/deployit-cli:535` | Extracts CFBundleVersion from the freshly-built archive's Info.plist to become the canonical build_number flowing through the rest of the deploy pipeline (meta_full, _stage_macos, _append_to_index); called once from cmd_deploy (plugins/deployit/bin/deployit-cli:1118). |
| `_read_config` | def | `plugins/deployit/bin/deployit-cli:458` | _read_config (plugins/deployit/bin/deployit-cli:458) is the sole config.toml loader, called by six commands — cmd_deploy:1095, cmd_url:1386, cmd_status:1393, cmd_gc:1450, cmd_rm:1503, cmd_redeploy:1601 — each depending on it for the [server] base_url/port block. |
| `_refresh_local_backend` | def | `plugins/deployit/bin/deployit-cli:979` | Best-effort POST that tells the running backend daemon to reload its in-memory index cache after any index-mutating command; called from cmd_deploy, cmd_rm, and cmd_gc (plugins/deployit/bin/deployit-cli:1162,1481,1536) to keep it consistent with the pushed builds.json. |
| `_resolve_version_and_tag` | def | `plugins/deployit/bin/deployit-release:116` | Sole authority for the release version+tag: semver VERSION takes precedence over Info.plist's CFBundleShortVersionString, normalizing the tag to carry semver's prefix; called once from main (plugins/deployit/bin/deployit-release:277) before every GitHub release publish. |
| `_semver_active_version` | def | `plugins/deployit/bin/deployit-cli:357` | Single source of truth for 'is semver tracking on for this project', gating cmd_deploy, cmd_preflight, and cmd_bump (plugins/deployit/bin/deployit-cli:1092,1230,1293) — decides whether the semver VERSION or the Info.plist version wins. |
| `_stage_macos` | def | `plugins/deployit/bin/deployit-cli:754` | The macOS packaging pipeline: builds the .dmg, optionally notarizes+staples, produces the Sparkle-signed zip and/or the GitHub-release zip, and writes _meta.json; called from cmd_deploy (plugins/deployit/bin/deployit-cli:1144) — the widest-scoped staging helper in the deploy path. |
| `_sync_plugin_root` | def | `plugins/deployit/bin/deployit-cli:131` | Points the daemon's stable indirection symlinks (_plugin_root, bin/deployit-backend) at the current plugin_root so the launchd plist never needs regenerating across upgrades; called from cmd_bootstrap and cmd_redeploy (plugins/deployit/bin/deployit-cli:1063,1604). |
| `_version_label` | def | `plugins/deployit/bin/deployit-backend:120` | Sole formatter for a build's displayed version (semver vs build-number fallback); reused across row, product, and build-landing rendering (plugins/deployit/bin/deployit-backend:169,182,255,392), so it governs every rendered page's version text. |

## Relationships

## Type notes

- Handler binds its serving `root` via a per-request dynamic subclass, not an instance attribute: make_handler creates a fresh subclass via `type('Handler', (Handler,), {'root': root})` because ThreadingHTTPServer instantiates one Handler per connection with no hook into `__init__` (plugins/deployit/bin/deployit-backend:610-611).
- `_pull_lock` is the backend's only concurrency guard: ThreadingHTTPServer serves each request on its own thread, and only `_git_pull` (which mutates the index checkout) takes it (plugins/deployit/bin/deployit-backend:41,213).
- The backend never mutates the shared index itself; `_run_cli_rm` always shells out to `deployit-cli rm`, which owns the pull/prune/commit/push sequence (plugins/deployit/bin/deployit-backend:413; plugins/deployit/bin/deployit-cli:920,877).
- `deployit-release` runs only as a subprocess invoked from `_publish_github_release`, never imported — a release-publish failure can't roll back or corrupt the already-committed tailnet deploy (plugins/deployit/bin/deployit-cli:1005).

## External deps

- argparse — imported
- datetime — imported
- email.utils — imported
- glob — imported
- html — imported
- http.server — imported
- json — imported
- mimetypes — imported
- os — imported
- pathlib — imported
- re — imported
- shutil — imported
- string — imported
- subprocess — imported
- sys — imported
- tempfile — imported
- textwrap — imported
- threading — imported
- time — imported
- tomllib — imported
- urllib.parse — imported
- urllib.request — imported

## Gotchas

- `_commit_and_push_index`'s retry loop resets --hard to origin/main on every push conflict before retrying, so a losing writer's local commit is discarded rather than merged — its `mutate` callback must be safely re-runnable (plugins/deployit/bin/deployit-cli:969,974).
- `_notarize_staple_app` points notarytool at a file-based login keychain via --keychain when `notary_keychain` is configured, because the default data-protection keychain locks when the screen locks, which otherwise breaks headless SSH/mosh deploys (plugins/deployit/bin/deployit-cli:715-716).
- `deployit-release` omits --target when the release tag already exists: `gh release create` only honors --target when creating a new tag, and a divergent --target on an existing tag makes the API reject with HTTP 422 (plugins/deployit/bin/deployit-release:216-224,312-313).
- Index pushes use an explicit insteadOf HTTPS override instead of the configured git remote, sidestepping SSH-agent prompts in non-interactive contexts (plugins/deployit/bin/deployit-cli:901,963).
