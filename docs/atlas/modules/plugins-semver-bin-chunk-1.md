---
module: "plugins/semver/bin (chunk 1)"
summary: "Deterministic JSON-in/out CLI implementing semver's init, set, bump, tracking, auto-bump, repair, validate ops."
read_when: "Touching semver-cli's bump, set, init, tracking, or config logic"
sources:
  - path: plugins/semver/bin/semver-cli
    blob: 13aa5d0b8c8deb4c82f0518e9a54fa41bd61d2b6
generator: cartographer/4
baseline: cb09ceb006e3fb4759a91d64d9e6655e67d04bf7
---

# Module: plugins/semver/bin (chunk 1)

## Purpose

semver-cli is the single deterministic, JSON-in/out Python executable behind the /semver skill: every subcommand (init, set, bump, tracking start/stop, auto-bump, repair, validate, recommend) is a pure function of cwd + .semver/config.yaml + git state, with all mutating writes serialized through a per-project FileLock (plugins/semver/bin/semver-cli:391-457). Its unifying idea is a gather/run/execute split — read-only assessment functions (cmd_*_run, _init_snapshot/_init_assess) surface AskUserQuestion-shaped blockers to the calling skill, while *_execute functions perform the actual git/file writes — so the skill layer never reimplements version-bump logic. If this file vanished, the /semver plugin would have no version tracking, bumping, tagging, changelog generation, or CLAUDE.md injection at all; nothing else in the repo re-implements it.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `Config` | class | `plugins/semver/bin/semver-cli:104` | Loads .semver/config.yaml (or DEFAULTS if absent) into string values; .exists flags whether the file was found on disk. |
| `FileLock` | class | `plugins/semver/bin/semver-cli:391` | Cross-repo mutual-exclusion lock: flock-based lock file under /tmp keyed by an md5 hash of project_dir; use as a context manager. |
| `acquire` | def | `plugins/semver/bin/semver-cli:409` | Non-blocking lock attempt; returns True if acquired, False if another process holds it (never blocks). |
| `all_version_tags` | def | `plugins/semver/bin/semver-cli:252` | Returns all git tags matching `<prefix>*`, sorted newest-version-first via git's -v:refname sort. |
| `build_archive` | def | `plugins/semver/bin/semver-cli:505` | Renders VERSIONING_ARCHIVE.md content (YAML frontmatter + selected sections) for the given `items` list; does not write the file. |
| `build_display` | def | `plugins/semver/bin/semver-cli:97` | Joins a list of lines into the CLI's human-readable `display` string, one per line. |
| `clean_commit_subject` | def | `plugins/semver/bin/semver-cli:314` | Strips a conventional-commit prefix (`type(scope)!: `) from a subject line for changelog display. |
| `cmd_auto_bump` | def | `plugins/semver/bin/semver-cli:2650` | Handles `auto-bump start|stop`; requires tracking active first, may return a `needs_input` question before writing config. |
| `cmd_bump_execute` | def | `plugins/semver/bin/semver-cli:1332` | Executes a version bump under FileLock: writes VERSION+CHANGELOG, commits, tags, runs pre/post hooks; always exits via output(). |
| `cmd_bump_first_version` | def | `plugins/semver/bin/semver-cli:1467` | Sets the initial VERSION+CHANGELOG+commit(+tag) when no version exists yet; exits via output()/output_error(). |
| `cmd_bump_gather` | def | `plugins/semver/bin/semver-cli:1061` | Prints `_gather_bump_state(args)` as the CLI's JSON response for `bump gather` (never executes the bump). |
| `cmd_bump_run` | def | `plugins/semver/bin/semver-cli:1227` | Single round-trip bump: gathers then executes when no questions/hooks block; else returns gather state or aborts (non-interactive). |
| `cmd_current` | def | `plugins/semver/bin/semver-cli:810` | Reports tracking status, current VERSION, and commit count since last version change as JSON with a `display` summary. |
| `cmd_init_execute` | def | `plugins/semver/bin/semver-cli:2632` | Given --mode (fresh|enable|adopt|reinit), performs that init action and writes/commits; errors on unknown mode (semver-cli:2632). |
| `cmd_init_run` | def | `plugins/semver/bin/semver-cli:2473` | No artifacts: runs a fresh init. Artifacts present: returns a read-only assessment/questions, no writes (semver-cli:2473). |
| `cmd_recommend` | def | `plugins/semver/bin/semver-cli:903` | Recommends a bump level (major/minor/patch) deterministically from conventional-commit types since the last version. |
| `cmd_repair_diagnose` | def | `plugins/semver/bin/semver-cli:2719` | Runs validation and, for each FAIL, emits a `repairs_needed` entry with an embedded question and `command_mapping` for the fix. |
| `cmd_repair_execute` | def | `plugins/semver/bin/semver-cli:2847` | Executes one named repair action (create-tag, revert-version, move-tag, generate-entry, update-version, delete-tag). |
| `cmd_set_execute` | def | `plugins/semver/bin/semver-cli:1721` | Writes VERSION/CHANGELOG under FileLock, commits, tags, runs post-bump hooks; re-cuts (no dup commit) if new_version == old_version. |
| `cmd_set_run` | def | `plugins/semver/bin/semver-cli:1588` | Validates target version, gathers dirty/branch/tag/validation blockers; none → calls cmd_set_execute; else returns questions. |
| `cmd_tracking_restore_tags` | def | `plugins/semver/bin/semver-cli:2092` | Restores git tags from a `.bak`/live archive file's `tags` section after a prior restore skipped them. |
| `cmd_tracking_start` | def | `plugins/semver/bin/semver-cli:1851` | Entry point for `tracking start`; dispatches to fresh-start or archive-restore based on whether VERSIONING_ARCHIVE.md exists. |
| `cmd_tracking_stop_execute` | def | `plugins/semver/bin/semver-cli:2201` | Writes VERSIONING_ARCHIVE.md, disables tracking, optionally deletes archived files/tags, and commits the change. |
| `cmd_tracking_stop_gather` | def | `plugins/semver/bin/semver-cli:2123` | Builds the `archive_items`/`tag_deletion` questions for `tracking stop` without modifying any state. |
| `cmd_validate` | def | `plugins/semver/bin/semver-cli:865` | Runs `run_validation_checks` and reports PASS/FAIL/WARN/SKIP counts plus a formatted `display`. |
| `commit_count_since` | def | `plugins/semver/bin/semver-cli:234` | Returns the number of commits reachable from HEAD since `commit_hash` (or all history if None). |
| `commits_since` | def | `plugins/semver/bin/semver-cli:218` | Returns [{hash, subject}, ...] for commits after commit_hash in git-log order (or full history if commit_hash is None). |
| `create_initial_changelog` | def | `plugins/semver/bin/semver-cli:382` | Writes a brand-new CHANGELOG.md with a single 'Initial version tracking' entry for the given version. |
| `current_branch` | def | `plugins/semver/bin/semver-cli:191` | Returns the current branch name via `git rev-parse --abbrev-ref HEAD`, or None if not resolvable. |
| `detect_default_branch` | def | `plugins/semver/bin/semver-cli:259` | Returns the origin's default branch, falling back to the current branch or `'main'`. |
| `dirty_files` | def | `plugins/semver/bin/semver-cli:201` | Returns the list of paths from `git status --porcelain`'s changed-file lines. |
| `ensure_git_root` | def | `plugins/semver/bin/semver-cli:179` | Aborts (via output_error) unless cwd is exactly the git repository root — commands must run from the project root. |
| `format_version` | def | `plugins/semver/bin/semver-cli:288` | Formats (major, minor, patch) as `<prefix>major.minor.patch`, the canonical VERSION file string. |
| `generate_changelog_entry` | def | `plugins/semver/bin/semver-cli:319` | Builds one changelog Markdown section from commits, grouped or flat per `fmt`, tagging the source as manual/auto/force. |
| `get` | def | `plugins/semver/bin/semver-cli:134` | Returns the config value for `key`, defaulting to Config.DEFAULTS if unset. |
| `get_bool` | def | `plugins/semver/bin/semver-cli:137` | Returns True only when the stored string value for `key` is exactly `'true'`. |
| `git` | def | `plugins/semver/bin/semver-cli:158` | Runs a git subprocess with a 30s timeout; returns (returncode, stdout, stderr) and never raises for git failures. |
| `git_root` | def | `plugins/semver/bin/semver-cli:173` | Returns the absolute git top-level directory for `cwd`, or None if not inside a repo. |
| `increment_version` | def | `plugins/semver/bin/semver-cli:279` | Applies one semver bump step (major resets minor/patch, minor resets patch, patch increments) — pure function. |
| `inject_claude_md` | def | `plugins/semver/bin/semver-cli:462` | Idempotently inserts/replaces the semver `<!-- semver:start/end -->` block in CLAUDE.md, creating the file if needed. |
| `is_dirty` | def | `plugins/semver/bin/semver-cli:196` | Returns True if `git status --porcelain` reports any changes. |
| `last_version_commit` | def | `plugins/semver/bin/semver-cli:212` | Returns the hash of the commit that most recently modified the VERSION file, or None if VERSION was never committed. |
| `main` | def | `plugins/semver/bin/semver-cli:2951` | argparse entry point; parses subcommands and dispatches to the `cmd_*` handlers, each of which exits via output()/output_error(). |
| `output` | def | `plugins/semver/bin/semver-cli:82` | Prints `data` as indented JSON to stdout and terminates the process with exit code 0 — never returns to the caller. |
| `output_error` | def | `plugins/semver/bin/semver-cli:88` | Prints an `{ok: false, error, message}` JSON envelope and terminates the process with exit code 1 — never returns. |
| `parse_archive` | def | `plugins/semver/bin/semver-cli:581` | Parses VERSIONING_ARCHIVE.md's YAML frontmatter and fenced sections into `{metadata, sections}`, or None if absent. |
| `parse_commit_type` | def | `plugins/semver/bin/semver-cli:303` | Classifies a commit subject into a changelog group (Breaking, Added, Fixed, Changed, ...) via its conventional-commit prefix. |
| `parse_version` | def | `plugins/semver/bin/semver-cli:268` | Parses a `<prefix>MAJOR.MINOR.PATCH` string into an (int,int,int) tuple, or None if it doesn't match that exact shape. |
| `prepend_changelog_entry` | def | `plugins/semver/bin/semver-cli:354` | Inserts a new entry right after the CHANGELOG header and before the first existing `## [` entry, creating the file if absent. |
| `read_version_file` | def | `plugins/semver/bin/semver-cli:292` | Returns the stripped contents of `<project_dir>/VERSION`, or None if the file doesn't exist. |
| `release` | def | `plugins/semver/bin/semver-cli:433` | Releases the lock: closes/removes the flock file, or rmdir's the mkdir-based lock directory. |
| `remove_claude_md` | def | `plugins/semver/bin/semver-cli:483` | Strips the semver `<!-- semver:start/end -->` block from CLAUDE.md; returns False if the file or block is absent. |
| `run_user_hooks` | def | `plugins/semver/bin/semver-cli:787` | Runs `hooks/run-user-hooks.sh <phase>` under a 120s timeout and returns its parsed JSON, or an error dict if none was produced. |
| `run_validation_checks` | def | `plugins/semver/bin/semver-cli:623` | Runs the 6 fixed sync-integrity checks (config/version/tag existence/tag commit/changelog/orphaned tags) and returns results. |
| `set` | def | `plugins/semver/bin/semver-cli:140` | Stores `value` (stringified) under `key` in memory only — call `write()` to persist to config.yaml. |
| `tag_commit` | def | `plugins/semver/bin/semver-cli:247` | Returns the commit hash a git tag points to, or None if the tag doesn't exist. |
| `tag_exists` | def | `plugins/semver/bin/semver-cli:242` | Returns True if the given git tag name exists locally. |
| `write` | def | `plugins/semver/bin/semver-cli:143` | Persists all `KEYS_ORDER` config keys to `path` (or the original config path) as simple `key: value` lines. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `__init__` | def | `plugins/semver/bin/semver-cli:122` | Config's constructor is the single config-parsing path in the CLI: every cmd_* handler creates a Config() here, and its naive line-based key:value split (not real YAML) is the sole source of all config state (plugins/semver/bin/semver-cli:122-132). |
| `__init__` | def | `plugins/semver/bin/semver-cli:394` | FileLock's constructor fixes the lock's backend and location for the whole lifetime of the lock: it derives a fixed /tmp path by md5-hashing project_dir and picks flock vs mkdir via _check_flock(), which in practice always selects flock on POSIX (plugins/semver/bin/semver-cli:394-399). |
| `_init_fresh_core` | def | `plugins/semver/bin/semver-cli:1876` | Single fresh-init implementation shared by two independent entry points: _tracking_start_fresh (semver-cli:1964) and init's no-artifacts path _init_do_fresh (semver-cli:2359); centralizes config write, optional VERSION/CHANGELOG seeding, CLAUDE.md injection, commit, and tag creation so the two command families can't drift out of sync. |

## Relationships

## Type notes

Config (plugins/semver/bin/semver-cli:104) is a per-invocation, in-memory parse of .semver/config.yaml with string-typed values only — get_bool (semver-cli:137) is a literal "true" string comparison, so any other truthy-looking value reads as false. FileLock (semver-cli:391) is keyed by an md5 hash of project_dir and lives under /tmp for the process lifetime; every mutating command path acquires it as a context manager around the write+commit+tag critical section, e.g. cmd_set_execute (semver-cli:1752), _init_do_fresh (semver-cli:2356), _init_reinit (semver-cli:2590), cmd_bump_execute (semver-cli:1378). The SEMVER_BUMP_IN_PROGRESS re-entrancy guard is read at three entry points (semver-cli:1080, 1598, 2480) but never set anywhere in this file — the invoking hook/skill layer owns setting/clearing it around nested calls.

## External deps

- argparse — imported
- datetime — imported
- fcntl — imported
- hashlib — imported
- json — imported
- os — imported
- re — imported
- subprocess — imported
- sys — imported
- time — imported

## Gotchas

FileLock's docstring says flock is Linux-only and mkdir is the macOS fallback, but _check_flock only tests hasattr(fcntl, "flock") (true on macOS too), so the mkdir path is effectively unreachable on any POSIX system (plugins/semver/bin/semver-cli:392,401-407).
