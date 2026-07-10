---
module: "plugins/deployit/bin (chunk 2)"
summary: "Publishes a Developer-ID-signed macOS app as a GitHub release; routes /deployit subcommands to deployit-cli."
read_when: "Touching GitHub release publishing, version-tag resolution, or /deployit routing"
sources:
  - path: plugins/deployit/bin/deployit-release
    blob: 48312b67fd29de6982d480529961efb7df6dc8a9
  - path: plugins/deployit/bin/deployit-router.sh
    blob: 344168329e019299a535c6e7c327e726f0cb5d03
generator: cartographer/4
baseline: a4486d2b70ad4124762f9d777af6a7dc007bdc6c
---

# Module: plugins/deployit/bin (chunk 2)

## Purpose

deployit-release is the last mile of the macOS deploy pipeline: it turns a signed .app into an immutable, versioned GitHub release, and it is the sole place deciding what that release's tag actually is via a strict ladder — semver VERSION, then the app's own CFBundleShortVersionString, then a loud failure — so an unversioned release can never ship (plugins/deployit/bin/deployit-release:116-130). deployit-router.sh is the stateless front door for every /deployit subcommand: it does nothing but confirm python3 exists and exec deployit-cli with the resolved plugin root, so all routing logic and behavior lives in the CLI, not here (plugins/deployit/bin/deployit-router.sh:9-17). Both scripts share a JSON-only-output discipline (ok()/fail() at plugins/deployit/bin/deployit-release:44-52) so every caller — success, argument error, or gh failure — gets machine-parseable output instead of free text.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `JsonArgumentParser` | class | `plugins/deployit/bin/deployit-release:55` | argparse subclass whose .error() calls fail() instead of printing usage and exit(2) — keeps errors one JSON object. |
| `build_parser` | def | `plugins/deployit/bin/deployit-release:230` | Builds deployit-release's argparse tree: exactly one of --app/--zip plus repo/target/title/prerelease/clobber/attach. |
| `error` | def | `plugins/deployit/bin/deployit-release:56` | Routes an argparse parsing error through fail() so usage errors stay a single JSON object. |
| `fail` | def | `plugins/deployit/bin/deployit-release:49` | Terminal error path: prints {ok:false, display, ...extra} and exits 1 — the only way this script should abort. |
| `main` | def | `plugins/deployit/bin/deployit-release:250` | Process entry point: resolves the version/tag, verifies Developer ID signing, then runs gh release create/edit/upload. |
| `ok` | def | `plugins/deployit/bin/deployit-release:44` | Prints {...payload, ok:true} — this script's single JSON success object on the happy path. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `_parse_owner_repo` | def | `plugins/deployit/bin/deployit-release:179` | Extracts owner/repo from git remote get-url origin when --repo isn't passed — the fallback repo resolution behind every gh call this script makes (plugins/deployit/bin/deployit-release:179). |
| `_parse_semver_config` | def | `plugins/deployit/bin/deployit-release:69` | Parses .semver/config.yaml directly (mirroring bin/deployit-cli rather than importing it) — feeds _semver_version, the first rung of _resolve_version_and_tag's version ladder (plugins/deployit/bin/deployit-release:69). |
| `_resolve_version_and_tag` | def | `plugins/deployit/bin/deployit-release:116` | Sole authority for the release version+tag: semver VERSION takes precedence over Info.plist's CFBundleShortVersionString, normalizing the tag to carry semver's prefix; called once from main (plugins/deployit/bin/deployit-release:277) before every GitHub release publish. |

## Relationships

## Type notes

- `JsonArgumentParser` (plugins/deployit/bin/deployit-release:55-57) overrides argparse's `error()` to route argument-parsing failures through `fail()` instead of argparse's default text-to-stderr-plus-exit(2), so even a malformed CLI invocation still emits the `{"ok": false, "display": ...}` contract.
- `ok()`/`fail()` (plugins/deployit/bin/deployit-release:44-52) are the single output surface for the whole script — every code path ends in exactly one of them, and `fail()` owns the process's only `sys.exit(1)`.
- `main()` scopes all packaging work to a `tempfile.TemporaryDirectory` (plugins/deployit/bin/deployit-release:261-262): the extracted-or-zipped `.app` and its `.zip` live only for the process's lifetime and are never persisted by this script.
- Version resolution is stateless and re-derived per run: `_semver_version`/`_semver_prefix` re-parse `.semver/config.yaml` directly (plugins/deployit/bin/deployit-release:69-96) rather than importing the semver plugin, deliberately keeping this script standalone (comment at plugins/deployit/bin/deployit-release:65-67).
- `DEPLOYIT_SKIP_CODESIGN_VERIFY` and `DEPLOYIT_GH_BIN` (plugins/deployit/bin/deployit-release:60-61, 138-139) are the only mutable environment seams — the former exists purely for tests, short-circuiting Developer ID verification without a real certificate.
- `deployit-router.sh` holds no state and forwards all arguments verbatim via `exec` (plugins/deployit/bin/deployit-router.sh:17), so its own process image is replaced by `deployit-cli` — it never runs code after dispatch.

## External deps

- argparse — imported
- json — imported
- os — imported
- pathlib — imported
- re — imported
- subprocess — imported
- sys — imported
- tempfile — imported

## Gotchas

- `_tag_exists` exists only to decide whether `--target` is safe to pass: `gh release create` sets the tag's commit only when creating it, so passing `--target` on an *existing* tag whose commit has since diverged (e.g. semver tagged the release commit, then a build-number bump moved HEAD) makes the GitHub API reject the create with HTTP 422; the target is silently omitted whenever the tag already exists (plugins/deployit/bin/deployit-release:216-227, plugins/deployit/bin/deployit-release:310-313).
- Exactly one of `--app`/`--zip` is required, enforced via `bool(args.app) == bool(args.zip)` (true — and rejected — when both or neither are set) rather than argparse's mutually-exclusive-group machinery (plugins/deployit/bin/deployit-release:253-254).
- `_read_app_short_version` probes both `Contents/Info.plist` and a root-level `Info.plist` because macOS bundles nest the plist under `Contents/` while iOS/visionOS keep it at the bundle root — the check exists so an app extracted from a `--zip` (of unknown platform origin) still resolves (plugins/deployit/bin/deployit-release:99-104).
- The tag is only prefixed with the semver `version_prefix` if the version doesn't already start with it, making tag construction idempotent against a version string that's already prefixed (plugins/deployit/bin/deployit-release:128-129).
- `deployit-router.sh` pre-checks for `python3` on PATH itself, before exec'ing the Python CLI, printing a hand-rolled JSON failure — the one piece of output in this bash file not produced by the delegated CLI, so a missing interpreter never leaks as bare shell text (plugins/deployit/bin/deployit-router.sh:12-15).
