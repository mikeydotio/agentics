# semver — Semantic Versioning Plugin

Lifecycle management for semantic versioning in Claude Code projects. Tracks version numbers, generates changelogs, manages git tags, and keeps Claude version-aware across sessions.

## Commands

| Command | Description |
|---------|-------------|
| `/semver current` | Show current version, commit count since last tag, and config status |
| `/semver bump <major\|minor\|patch>` | Increment version, generate changelog entry from git log, commit and tag |
| `/semver bump <type> --force` | Bump even with no commits since last tag (e.g., consolidating versions) |
| `/semver tracking start` | Initialize version tracking — creates VERSION, CHANGELOG, config, and CLAUDE.md injection |
| `/semver tracking stop` | Archive version data and disable tracking |
| `/semver auto-bump start` | Enable automatic version bumps when pushing to the target branch |
| `/semver auto-bump stop` | Disable auto-bump (falls back to nudge reminders) |

## How It Works

### Files Created

When you run `/semver tracking start`, the plugin creates:

- **`VERSION`** — Contains only the current version string (e.g., `v1.2.3`)
- **`CHANGELOG.md`** — Bulleted list of changes organized by version, newest at top
- **`.semver/config.yaml`** — Per-project configuration
- **CLAUDE.md section** — Injected instructions that make Claude version-aware

### Version Bumping

`/semver bump minor` will:
1. Check for uncommitted changes and handle them interactively
2. Acquire a file lock (thread-safe)
3. Read the current version and increment it
4. Summarize the git log since the last tag into a human-friendly changelog entry
5. Write the new VERSION and CHANGELOG
6. Commit with message `chore(release): v1.3.0`
7. Create a git tag `v1.3.0`
8. Release the lock

### Hooks

The plugin includes two Claude Code hooks that activate based on `.semver/config.yaml`:

**SessionStart hook** — At the beginning of every Claude session, injects the current version and tracking status into context. No-op if tracking is inactive.

**PostToolUse hook** — After any `git push` to the target branch:
- **Auto-bump off**: Shows a nudge reminder with commit count since last tag
- **Auto-bump on, confirm on**: Analyzes the git log and proposes a bump level for user approval
- **Auto-bump on, confirm off**: Analyzes and executes the bump automatically

Both hooks exit silently when semver is not active in the project.

### User-Defined Hooks

Projects can define custom pre-bump and post-bump hooks in `.semver/hooks/`:

```
.semver/hooks/
├── pre-bump/
│   ├── PROMPT_HOOK.md    # AI agent instructions (optional)
│   └── *.sh              # Shell scripts run before VERSION is updated
└── post-bump/
    ├── PROMPT_HOOK.md    # AI agent instructions (optional)
    └── *.sh              # Shell scripts run after commit + tag
```

- **Pre-bump scripts** can abort the bump (non-zero exit code)
- **Post-bump scripts** warn on failure but don't roll back
- **PROMPT_HOOK.md** files contain instructions the AI agent follows during the bump
- Scripts receive `BUMP_TYPE`, `OLD_VERSION`, `NEW_VERSION` as environment variables
- Scripts run in alphabetical order — use numeric prefixes (`01-test.sh`, `02-lint.sh`)
- A re-entrancy guard (`SEMVER_BUMP_IN_PROGRESS=1`) prevents infinite loops

Ask Claude to set up hooks for you, or create them manually. See `references/user-hooks.md` for the full contract and sample hooks.

### CLAUDE.md Integration

The tracking start command injects a section (between `<!-- semver:start -->` and `<!-- semver:end -->` markers) that teaches Claude:
- To read VERSION at session start
- To write meaningful conventional-commit-style messages
- When to suggest major vs minor vs patch bumps

This section is automatically removed by `tracking stop`.

## Configuration

`.semver/config.yaml` controls all settings:

```yaml
tracking: true              # Master switch
auto_bump: false            # Auto-bump on push to target branch
auto_bump_confirm: true     # Ask before auto-bumping
version_prefix: "v"         # "" or "v" — applied to VERSION file and tags
changelog_format: "grouped" # "grouped" (by type) or "flat" (linear list)
target_branch: "main"       # Branch that triggers hooks
```

## Archiving and Restoring

`/semver tracking stop` offers to archive VERSION, CHANGELOG, and git tags to a `VERSIONING_ARCHIVE.md` file. This structured archive can be restored by a subsequent `/semver tracking start`, which detects the archive and offers smart restore (auto-restores VERSION + CHANGELOG, asks separately about tags).

## Edge Cases Handled

- **No commits since tag**: Refuses bump unless `--force` is used
- **Dirty working tree**: Summarizes changes, offers stash/include/cancel options
- **Tag already exists**: Offers overwrite, skip, or cancel
- **Wrong branch**: Warns about consequences, allows override
- **Concurrent bumps**: File lock prevents corruption (flock on Linux, mkdir fallback on macOS)
