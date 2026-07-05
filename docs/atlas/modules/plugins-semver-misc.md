---
module: "plugins/semver (misc)"
summary: "semver-cli engine, router, and skill orchestrator: deterministic version bump, changelog, tracking, and repair logic."
read_when: "Touching /semver commands, bump/changelog/validate logic, or the CLI JSON contract"
sources:
  - path: plugins/semver/.claude-plugin/plugin.json
    blob: ed707b53bc2cf4fbf6cd6e50059cad24b39a4d14
  - path: plugins/semver/README.md
    blob: 355c546fe806712c5d265fe9a33fde1a59d8a1fe
  - path: plugins/semver/bin/semver-cli
    blob: 201e745459e03f4865891b44105f4727ee3998f5
  - path: plugins/semver/bin/semver-router.sh
    blob: 42c4f57e3b77cdaa6e3ef2be6f730603eb0d0e20
  - path: plugins/semver/skills/semver/SKILL.md
    blob: d55b2177ff24c350b85121b63a30700a6267d4a2
generator: cartographer/4
baseline: 50c998d53e2ed58951ac5f794afd32bfa729f658
---

# Module: plugins/semver (misc)

## Purpose

This module is semver's deterministic execution core: semver-cli (plugins/semver/bin/semver-cli) implements every stateful operation — config load/parse, git plumbing, version arithmetic, changelog generation, file locking, archive round-tripping, validation and repair — as JSON-emitting subcommands, while semver-router.sh translates /semver's argument shape into CLI calls and SKILL.md tells Claude how to relay the CLI's questions/display back to the user. The organizing idea is that Claude never improvises versioning logic: every decision (bump math, changelog grouping, validation status, repair options) is computed by the CLI and handed back as structured data for the orchestrator to relay verbatim. Without this module /semver has no implementation at all — the skill's AskUserQuestion loop and the router's dispatch table both exist only to shuttle this CLI's JSON contracts to and from the user.

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
| `cmd_auto_bump` | def | `plugins/semver/bin/semver-cli:1884` | Handles `auto-bump start|stop`; requires tracking active first, may return a `needs_input` question before writing config. |
| `cmd_bump_execute` | def | `plugins/semver/bin/semver-cli:1247` | Executes a version bump under FileLock: writes VERSION+CHANGELOG, commits, tags, runs pre/post hooks; always exits via output(). |
| `cmd_bump_first_version` | def | `plugins/semver/bin/semver-cli:1422` | Sets the initial VERSION+CHANGELOG+commit(+tag) when no version exists yet; exits via output()/output_error(). |
| `cmd_bump_gather` | def | `plugins/semver/bin/semver-cli:981` | Prints `_gather_bump_state(args)` as the CLI's JSON response for `bump gather` (never executes the bump). |
| `cmd_bump_run` | def | `plugins/semver/bin/semver-cli:1203` | Single round-trip bump: gathers then executes when no questions/hooks block; else returns gather state or aborts (non-interactive). |
| `cmd_current` | def | `plugins/semver/bin/semver-cli:810` | Reports tracking status, current VERSION, and commit count since last version change as JSON with a `display` summary. |
| `cmd_recommend` | def | `plugins/semver/bin/semver-cli:903` | Recommends a bump level (major/minor/patch) deterministically from conventional-commit types since the last version. |
| `cmd_repair_diagnose` | def | `plugins/semver/bin/semver-cli:1953` | Runs validation and, for each FAIL, emits a `repairs_needed` entry with an embedded question and `command_mapping` for the fix. |
| `cmd_repair_execute` | def | `plugins/semver/bin/semver-cli:2081` | Executes one named repair action (create-tag, revert-version, move-tag, generate-entry, update-version, delete-tag). |
| `cmd_tracking_restore_tags` | def | `plugins/semver/bin/semver-cli:1697` | Restores git tags from a `.bak`/live archive file's `tags` section after a prior restore skipped them. |
| `cmd_tracking_start` | def | `plugins/semver/bin/semver-cli:1486` | Entry point for `tracking start`; dispatches to fresh-start or archive-restore based on whether VERSIONING_ARCHIVE.md exists. |
| `cmd_tracking_stop_execute` | def | `plugins/semver/bin/semver-cli:1806` | Writes VERSIONING_ARCHIVE.md, disables tracking, optionally deletes archived files/tags, and commits the change. |
| `cmd_tracking_stop_gather` | def | `plugins/semver/bin/semver-cli:1728` | Builds the `archive_items`/`tag_deletion` questions for `tracking stop` without modifying any state. |
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
| `main` | def | `plugins/semver/bin/semver-cli:2185` | argparse entry point; parses subcommands and dispatches to the `cmd_*` handlers, each of which exits via output()/output_error(). |
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

## Relationships

## Type notes

output()/output_error() are terminal, not returning: every cmd_* handler ends by calling one of them, which calls sys.exit() (plugins/semver/bin/semver-cli:82-94), so a mid-function call like the early guards in cmd_current (plugins/semver/bin/semver-cli:816-822) exits the whole process rather than falling through. _gather_bump_state() (plugins/semver/bin/semver-cli:986) is the one exception — it is pure and returns a plain dict without exiting — which is what lets cmd_bump_run (plugins/semver/bin/semver-cli:1203) inspect the gathered state and decide whether to execute inline or hand it back for cmd_bump_gather (plugins/semver/bin/semver-cli:981) to print unchanged. Config values are always strings in memory; get_bool() (plugins/semver/bin/semver-cli:137) is the only place a `'true'`/`'false'` string becomes a real boolean. FileLock's lock path is a fixed `/tmp/semver-<md5(project_dir)>.lock` (plugins/semver/bin/semver-cli:394-398), so repeated runs against the same project_dir reuse the same lock file across process lifetimes, and a stale mkdir-based lock older than 300s is force-removed on the next acquire() (plugins/semver/bin/semver-cli:420-426). Reentrancy across pre/post-bump hook scripts is guarded only by the `SEMVER_BUMP_IN_PROGRESS` env-var check inside _gather_bump_state (plugins/semver/bin/semver-cli:999-1002) — a courtesy check, not OS-level protection.

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

FileLock's docstring claims a mkdir-based fallback for macOS, but _check_flock() only tests hasattr(fcntl, 'flock') (plugins/semver/bin/semver-cli:404-405), which is true on macOS as well as Linux — so the mkdir path is effectively unreachable in practice, not a real cross-platform fallback. Separately, pre-bump hooks run before the FileLock is acquired 'per original design' (plugins/semver/bin/semver-cli:1280,1293), so two concurrent bumps can both execute pre-bump scripts before either one wins the lock.
