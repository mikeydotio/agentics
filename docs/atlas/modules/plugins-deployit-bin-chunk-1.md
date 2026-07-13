---
module: "plugins/deployit/bin (chunk 1)"
summary: "deployit's stdlib-only HTTP backend (listing/serve/delete) and CLI (archive/export/stage/publish to the index)."
read_when: "Touching deployit subcommands, the deploy/publish flow, or backend endpoints"
sources:
  - path: plugins/deployit/bin/deployit-backend
    blob: 7938f381f5c77f195c95d8f7a120b4d38cd8fc7e
  - path: plugins/deployit/bin/deployit-cli
    blob: bd116b7df05a9cd21831731a8740f87fcaf2f439
generator: cartographer/4
baseline: 7387d3614aaae8d5a5bc156cf01c251d22b1dd45
---

# Module: plugins/deployit/bin (chunk 1)

## Purpose

deployit turns a developer's Mac into a private, Tailscale-only app-distribution point for iOS/macOS/visionOS builds: the CLI (deployit-cli) drives xcodebuild archive/export, packages installers (OTA manifest.plist, notarized .dmg, optional Sparkle-signed zip), and is the sole writer of the shared git-backed build index (index/builds.json), reconciling concurrent-writer races and branch-protection rulesets on every publish. The backend (deployit-backend) is a read-mostly stdlib HTTP server that renders the listing/build/product/appcast pages from that same index and serves artifacts directly, but delegates every destructive action (build/product delete) back to the CLI's `rm` subcommand over subprocess rather than touching the index itself. Without this split, either the index would gain multiple uncoordinated writers (silent corruption under concurrent deploys) or the CLI's archive/export/notarize machinery would have to be duplicated inside a long-running server process.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `Handler` | class | `plugins/deployit/bin/deployit-backend:447` | BaseHTTPRequestHandler subclass registered with ThreadingHTTPServer; `root` is bound per-instance by make_handler, not `__init__`. |
| `JsonArgumentParser` | class | `plugins/deployit/bin/deployit-cli:57` | argparse subclass whose .error() calls fail() instead of printing usage and exit(2) — keeps CLI errors one JSON object. |
| `build_parser` | def | `plugins/deployit/bin/deployit-cli:1933` | Builds deployit's full argparse tree; each subcommand's func default is how main dispatches to a cmd_* handler. |
| `cmd_bootstrap` | def | `plugins/deployit/bin/deployit-cli:1306` | One-time per-machine setup: derives the tailnet base_url, writes config.toml, clones the index, installs launchd. Idempotent. |
| `cmd_bump` | def | `plugins/deployit/bin/deployit-cli:1544` | Non-interactively delegates a semver version bump to the semver plugin's CLI, pre-authorizing --dirty-action include. |
| `cmd_deploy` | def | `plugins/deployit/bin/deployit-cli:1329` | Archives, exports, stages, notarizes (macOS), pushes the index entry, and optionally publishes a GitHub release: the pipeline's core. |
| `cmd_gc` | def | `plugins/deployit/bin/deployit-cli:1711` | Archives (never deletes from the index) this machine's builds beyond --keep/--older-than, then rmtrees their local serve/ dirs. |
| `cmd_list` | def | `plugins/deployit/bin/deployit-cli:1690` | Read-only: lists recent local-index builds, optionally filtered by --platform/--project. |
| `cmd_preflight` | def | `plugins/deployit/bin/deployit-cli:1482` | Read-only: reports whether a semver bump is required before the next deploy of this (bundle_id, platform); never mutates. |
| `cmd_redeploy` | def | `plugins/deployit/bin/deployit-cli:1874` | Re-points the daemon's plugin-root symlinks, repairs a legacy plist, restarts launchd, waits for health, runs verify-live.sh. |
| `cmd_release_context` | def | `plugins/deployit/bin/deployit-cli:1587` | Read-only: gathers repo/tag/commits/closed-issues facts for release notes; degrades to commits-only without gh. |
| `cmd_rm` | def | `plugins/deployit/bin/deployit-cli:1764` | Deletes one local build or product from the shared index and its serve/ dir; backs the web UI's swipe-to-delete. |
| `cmd_status` | def | `plugins/deployit/bin/deployit-cli:1656` | Reports backend health via _healthz plus this machine's most recent local deploys. |
| `cmd_url` | def | `plugins/deployit/bin/deployit-cli:1649` | Prints this machine's listing base URL, read from config.toml. |
| `do_DELETE` | def | `plugins/deployit/bin/deployit-backend:578` | Entry point for DELETE requests; wraps _dispatch_delete and always emits a JSON response, catching every exception as a 500. |
| `do_GET` | def | `plugins/deployit/bin/deployit-backend:481` | Entry point for GET requests; wraps _dispatch_get and always emits a response, catching every exception as a 500 JSON error. |
| `do_POST` | def | `plugins/deployit/bin/deployit-backend:563` | Entry point for POST requests; wraps _dispatch_post and always emits a JSON response, catching every exception as a 500. |
| `error` | def | `plugins/deployit/bin/deployit-cli:58` | Routes an argparse parsing error through fail() so usage errors stay a single JSON object, not argparse's default exit(2). |
| `fail` | def | `plugins/deployit/bin/deployit-cli:47` | Terminal error path for the whole CLI: prints {ok:false, display, ...extra} and exits 1 — the only way to abort a subcommand. |
| `log_message` | def | `plugins/deployit/bin/deployit-backend:450` | Suppresses access-log noise for /deployit/_healthz; every other request is logged to stderr. |
| `main` | def | `plugins/deployit/bin/deployit-backend:614` | Process entry point: parses --port/--root/--plugin-root, syncs the _plugin_root symlink, then blocks in serve_forever(). |
| `main` | def | `plugins/deployit/bin/deployit-cli:1994` | Process entry point: parses argv, prints --version, or dispatches to the matched subcommand's func. |
| `make_handler` | def | `plugins/deployit/bin/deployit-backend:610` | Builds a fresh Handler subclass binding `root` — the only way to inject per-run state into BaseHTTPRequestHandler. |
| `mutate` | def | `plugins/deployit/bin/deployit-cli:1720` | cmd_gc's mutation for _commit_and_push_index: archives builds beyond the gc cutoff in place and returns the commit message. |
| `mutate` | def | `plugins/deployit/bin/deployit-cli:1794` | cmd_rm's mutation for _commit_and_push_index: removes matching local build/product entries and returns the commit message. |
| `not_implemented` | def | `plugins/deployit/bin/deployit-cli:53` | Fails a subcommand with a standard 'not implemented yet' message; a placeholder for stubbed commands. |
| `ok` | def | `plugins/deployit/bin/deployit-cli:42` | Prints {...payload, ok:true} — the CLI's single JSON success object every non-failing subcommand must end with. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `_append_to_index` | def | `plugins/deployit/bin/deployit-cli:1134` | The high-frequency deploy path's sole writer to the shared index: prepends the new build entry, prunes this origin's older builds, commits, and publishes, resetting to a clean origin/main on each retry attempt so concurrent deploys never corrupt builds.json. Called from cmd_deploy at plugins/deployit/bin/deployit-cli:1374; delegates the push-classification/retry/PR-fallback decision to _publish_index_commit (plugins/deployit/bin/deployit-cli:1127). |
| `_classify_push_failure` | def | `plugins/deployit/bin/deployit-cli:961` | The single decision point for every index push: classifies git push stderr into ruleset/protected (→ PR fallback), auth (→ preserve-and-fail, no PR attempt), non_fast_forward/other (→ retry from a fresh origin/main). Consumed at plugins/deployit/bin/deployit-cli:1086 inside _publish_index_commit, which both _append_to_index and _commit_and_push_index depend on for every publish. |
| `_derive_metadata` | def | `plugins/deployit/bin/deployit-cli:309` | Central project-layout detector (Apps-layout vs single-app Xcode project) that cmd_deploy and cmd_preflight both depend on (plugins/deployit/bin/deployit-cli:1085,1229) to resolve bundle id, marketing version, and xcodebuild container args. |
| `_find_semver_cli` | def | `plugins/deployit/bin/deployit-cli:421` | Sole cross-plugin lookup for the semver plugin's CLI (env override -> sibling plugin -> ~/.claude glob), used by cmd_bump (plugins/deployit/bin/deployit-cli:1295) — the only bridge from deployit into the semver plugin. |
| `_install_launchd` | def | `plugins/deployit/bin/deployit-cli:226` | Writes and (re)loads the launchd plist that runs deployit-backend as a persistent daemon; called from both cmd_bootstrap and cmd_redeploy (plugins/deployit/bin/deployit-cli:1068,1609) — the sole mechanism that starts/restarts the backend service. |
| `_next_versions` | def | `plugins/deployit/bin/deployit-cli:403` | Computes the major/minor/patch semver successor labels cmd_bump presents to the operator (plugins/deployit/bin/deployit-cli:1270); a wrong computation would mislead which version a human picks to ship, even though semver-cli performs the actual bump. |
| `_parse_owner_repo` | def | `plugins/deployit/bin/deployit-cli:96` | Extracts owner/repo from a git remote URL (SSH or HTTPS, with or without .git); the sole source of GitHub repo identity for cmd_release_context (plugins/deployit/bin/deployit-cli:73). |
| `_parse_semver_config` | def | `plugins/deployit/bin/deployit-cli:361` | Parses .semver/config.yaml's flat key:value format directly (deliberately not importing the semver plugin) — the sole read path behind _semver_active_version, _semver_prefix, and preflight's target_branch (plugins/deployit/bin/deployit-cli:338). |
| `_publish_github_release` | def | `plugins/deployit/bin/deployit-cli:1253` | The only bridge from deployit-cli into bin/deployit-release: invokes it as a subprocess to publish the staged release zip, called once from cmd_deploy (plugins/deployit/bin/deployit-cli:1171); deliberately never raises so a release failure can't roll back an already-deployed tailnet build. |
| `_read_archive_build_number` | def | `plugins/deployit/bin/deployit-cli:602` | Extracts CFBundleVersion from the freshly-built archive's Info.plist to become the canonical build_number flowing through the rest of the deploy pipeline (meta_full, _stage_macos, _append_to_index); called once from cmd_deploy (plugins/deployit/bin/deployit-cli:1118). |
| `_read_config` | def | `plugins/deployit/bin/deployit-cli:516` | _read_config (plugins/deployit/bin/deployit-cli:458) is the sole config.toml loader, called by six commands — cmd_deploy:1095, cmd_url:1386, cmd_status:1393, cmd_gc:1450, cmd_rm:1503, cmd_redeploy:1601 — each depending on it for the [server] base_url/port block. |
| `_refresh_local_backend` | def | `plugins/deployit/bin/deployit-cli:1227` | Best-effort POST that tells the running backend daemon to reload its in-memory index cache after any index-mutating command; called from cmd_deploy, cmd_rm, and cmd_gc (plugins/deployit/bin/deployit-cli:1162,1481,1536) to keep it consistent with the pushed builds.json. |
| `_semver_active_version` | def | `plugins/deployit/bin/deployit-cli:380` | Single source of truth for 'is semver tracking on for this project', gating cmd_deploy, cmd_preflight, and cmd_bump (plugins/deployit/bin/deployit-cli:1092,1230,1293) — decides whether the semver VERSION or the Info.plist version wins. |
| `_stage_macos` | def | `plugins/deployit/bin/deployit-cli:821` | The macOS packaging pipeline: builds the .dmg, optionally notarizes+staples, produces the Sparkle-signed zip and/or the GitHub-release zip, and writes _meta.json; called from cmd_deploy (plugins/deployit/bin/deployit-cli:1144) — the widest-scoped staging helper in the deploy path. |
| `_sync_plugin_root` | def | `plugins/deployit/bin/deployit-cli:154` | Points the daemon's stable indirection symlinks (_plugin_root, bin/deployit-backend) at the current plugin_root so the launchd plist never needs regenerating across upgrades; called from cmd_bootstrap and cmd_redeploy (plugins/deployit/bin/deployit-cli:1063,1604). |
| `_version_label` | def | `plugins/deployit/bin/deployit-backend:120` | Sole formatter for a build's displayed version (semver vs build-number fallback); reused across row, product, and build-landing rendering (plugins/deployit/bin/deployit-backend:169,182,255,392), so it governs every rendered page's version text. |

## Relationships

## Type notes

- The backend never mutates the index; all destructive routes shell out to deployit-cli's `rm` subcommand so there is exactly one index writer — plugins/deployit/bin/deployit-backend:413-419, 585-607.
- CLI state is a per-machine directory (~/Library/Application Support/deployit, overridable via DEPLOYIT_STATE_DIR) that owns config.toml, the index clone, serve/ artifacts, and launchd logs — plugins/deployit/bin/deployit-cli:62-67, 138-141.
- The launchd plist is generated once against STABLE indirection symlinks (<state>/_plugin_root, <state>/bin/deployit-backend); plugin upgrades only repoint the symlinks via `_sync_plugin_root`, never regenerate the plist — plugins/deployit/bin/deployit-cli:196-201, 154-166.
- Every index-mutating operation resets the local checkout to a clean origin/main before mutating (`_reset_index_to_origin_main`), so a concurrent-writer conflict simply retries from a fresh base rather than merging — plugins/deployit/bin/deployit-cli:989-1001, 1113-1114.
- A commit that can neither be published nor pushed to a fallback branch is never dropped: `_preserve_and_fail` stashes it on a local `<branch>-local` recovery branch before resetting main — plugins/deployit/bin/deployit-cli:1004-1015.
- `Handler.root` is a class attribute injected per-process by `make_handler`'s dynamic subclass, not an instance field — plugins/deployit/bin/deployit-backend:447-448, 610-611.

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
- textwrap — imported
- threading — imported
- time — imported
- tomllib — imported
- urllib.parse — imported
- urllib.request — imported

## Gotchas

- Single path segments that merely look like a build id ("p", "_healthz", "icons", static asset filenames) are hard-coded as reserved words so the DELETE build route can't be tricked into deleting health/internal/static paths — plugins/deployit/bin/deployit-backend:34-40, 601.
- `_classify_push_failure` must check ruleset/protected signals before the non-fast-forward signals: a ruleset rejection's stderr also contains the generic "failed to push some refs" line that would otherwise be misclassified as a retryable non-fast-forward — plugins/deployit/bin/deployit-cli:933-935 (comment), 950-957 (check order).
- `deployit-backend`'s `main()` skips recreating the `_plugin_root` symlink when invoked with `--plugin-root` already pointing at that same symlink, to avoid a self-referential symlink loop — plugins/deployit/bin/deployit-backend:627-634.
- `_gh_bin()` resolves an absolute path to `gh` (probing Homebrew locations) rather than trusting PATH, because the launchd daemon's swipe-to-delete → `deployit-cli rm` → PR-fallback path runs with the minimal `/usr/bin:/bin:/usr/sbin:/sbin` PATH that lacks Homebrew's `gh` — plugins/deployit/bin/deployit-cli:74-93.
- `_read_config` has two parse paths (tomllib on Python 3.11+, a hand-rolled regex fallback otherwise) with a comment noting the target OS/Python version rather than requiring the modern path unconditionally — plugins/deployit/bin/deployit-cli:482-534.
