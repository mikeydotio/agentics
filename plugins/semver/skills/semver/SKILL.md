---
name: semver
description: Use when the user wants to manage semantic versioning for their project. Handles version tracking (start/stop), version bumping (major/minor/patch) with AI-generated changelog entries, reading current version, and auto-bump configuration. Commands are /semver current, /semver bump, /semver tracking, and /semver auto-bump.
argument-hint: <current | bump <major|minor|patch> [--force] | tracking <start|stop> | auto-bump <start|stop>>
---

# Semantic Versioning Orchestrator

You are a semantic versioning lifecycle manager. You handle version tracking, bumping, changelog generation, and auto-bump configuration for the project.

**Read these references before executing any command:**
- `references/config-schema.md` — `.semver/config.yaml` schema and parsing
- `references/file-locking.md` — File lock protocol for bump operations
- `references/changelog-format.md` — CHANGELOG format specs and indicators
- `references/claude-md-injection.md` — CLAUDE.md template and sentinel markers
- `references/archive-format.md` — VERSIONING_ARCHIVE.md format for tracking stop/start

## Hard Rules

1. **Always read `.semver/config.yaml` first** (if it exists) to determine project state before any operation.
2. **Never modify VERSION or CHANGELOG without holding the file lock** during bump operations.
3. **Never fabricate changelog entries** — always read the actual git log and summarize real changes.
4. **Respect the `version_prefix` setting** — apply it consistently to VERSION file content and git tags.
5. **Every question to the user MUST use `AskUserQuestion`** with exactly 1 question per call.
6. **Mark bump source** — every CHANGELOG version entry must end with `_[manual]_`, `_[auto]_`, or `_[force]_`.

## Command Router

Parse the ARGUMENTS string to determine which command to run:

| Argument starts with | Command |
|---------------------|---------|
| `current` or empty | `/semver current` |
| `bump` | `/semver bump` |
| `tracking` | `/semver tracking` |
| `auto-bump` | `/semver auto-bump` |
| Anything else | Show usage help |

**Usage help:**
```
/semver current                        — Show current version and status
/semver bump <major|minor|patch>       — Bump version, generate changelog, commit + tag
/semver bump <major|minor|patch> --force — Bump even with no changes since last tag
/semver tracking start                 — Initialize version tracking for this project
/semver tracking stop                  — Archive and disable version tracking
/semver auto-bump start                — Enable automatic version bumps on push to main
/semver auto-bump stop                 — Disable automatic version bumps
```

---

## Command: `/semver current`

1. Check if `.semver/config.yaml` exists. If not:
   - Report: "Version tracking is not active for this project. Run `/semver tracking start` to begin."
   - Stop.

2. Read `.semver/config.yaml` and verify `tracking: true`. If tracking is false:
   - Report: "Version tracking is disabled. Run `/semver tracking start` to re-enable."
   - Stop.

3. Read the `VERSION` file. Report:
   - Current version (with prefix per config)
   - Last tag date (from `git log -1 --format=%ai <last-tag>`)
   - Number of commits since last tag (`git rev-list <last-tag>..HEAD --count`)
   - Auto-bump status (on/off)
   - Target branch

---

## Command: `/semver bump <major|minor|patch> [--force]`

### Parse Arguments

Extract:
- `BUMP_TYPE`: one of `major`, `minor`, `patch` (required — if missing, show usage and stop)
- `FORCE`: true if `--force` is present

### Pre-check: Tracking Active

Read `.semver/config.yaml`. If missing or `tracking: false`:
- Report: "Version tracking is not active. Run `/semver tracking start` first."
- Stop.

### Pre-check: Commits Since Last Tag

Run `git describe --tags --abbrev=0` to find the last version tag. Then `git rev-list <last-tag>..HEAD --count`.

If count is 0 and `FORCE` is false:
- Report: "No commits since the last tag (<last-tag>). Nothing to bump. Use `--force` if you want a version-only bump (e.g., consolidating minor versions into a major release)."
- Stop.

If count is 0 and `FORCE` is true:
- Continue. The changelog entry will note this is a forced version-only bump.

### Pre-check: Dirty Working Tree

Run `git status --porcelain`. If there are uncommitted changes:

1. Summarize the changes for the user (modified files, untracked files).
2. Use AskUserQuestion:
   - **header:** "Dirty tree"
   - **question:** "You have uncommitted changes. What would you like to do with them before bumping?"
   - **options:**
     - "Include all in bump commit" / "Stage everything and include it in the version bump commit"
     - "Stash and bump clean" / "Stash changes, do the bump, then unstash"
     - "Let me choose files" / "I'll tell you which changes to include"
     - "Cancel" / "Abort the bump — I'll clean up first"
3. Execute the user's choice:
   - **Include all**: `git add -A` before the bump commit
   - **Stash and bump clean**: `git stash push -m "semver: pre-bump stash"`, do bump, then `git stash pop`
   - **Let me choose**: Ask user which files to include (use AskUserQuestion with file list), `git add` those files, `git stash push --keep-index -m "semver: pre-bump stash"` for the rest, do bump, then `git stash pop`
   - **Cancel**: Stop.
4. After the bump, if stash was used, remind the user: "Your stashed changes have been restored. Consider committing or cleaning up your working tree."

### Pre-check: Current Branch

Run `git rev-parse --abbrev-ref HEAD`. Read `target_branch` from config.

If current branch != target_branch:
- Warn the user:
  > "You're on branch `<current>`, not `<target>`. Bumping from a non-target branch means:
  > - The version tag will point to a commit on this branch
  > - The tag may not be reachable from the target branch until merged
  > - Auto-bump hooks check the target branch, so this version may trigger another bump later
  >
  > It's recommended to switch to `<target>` first."
- Use AskUserQuestion:
  - **header:** "Branch"
  - **question:** "Proceed with bump on this branch?"
  - **options:**
    - "Proceed anyway" / "I know what I'm doing"
    - "Cancel" / "I'll switch branches first"
- If cancel, stop.

### Execute Bump (Critical Section)

**All steps below must be performed inside a file lock.** Follow the protocol in `references/file-locking.md`.

1. **Read current version** from VERSION file. Strip whitespace. Remove version prefix if present to get bare `MAJOR.MINOR.PATCH`.

2. **Compute new version:**
   - Parse `MAJOR.MINOR.PATCH` from current version
   - `major` bump: `MAJOR+1.0.0`
   - `minor` bump: `MAJOR.MINOR+1.0`
   - `patch` bump: `MAJOR.MINOR.PATCH+1`

3. **Apply prefix:** Read `version_prefix` from config. New version string = `<prefix><MAJOR.MINOR.PATCH>`.

4. **Generate changelog entry:**
   - If FORCE and no commits: Write a brief entry noting this is a version-only adjustment
   - Otherwise:
     - Run `git log <last-tag>..HEAD --format="%h %s"` to get commits
     - If needed for clarity, also check `git diff <last-tag>..HEAD --stat`
     - Read `changelog_format` from config
     - **Grouped format**: Categorize commits by conventional commit prefix (see `references/changelog-format.md`), write concise human-friendly descriptions with commit hashes
     - **Flat format**: List commits linearly with hashes and descriptions
   - Determine the indicator: `_[manual]_` for explicit user bump, `_[auto]_` if triggered by auto-bump hook, `_[force]_` if `--force` was used

5. **Write VERSION file:** Write the new version string (with prefix per config) followed by a newline. Nothing else in the file.

6. **Update CHANGELOG.md:** Prepend the new version section after the title/header lines (before the first existing `## [` section). See `references/changelog-format.md` for exact format.

7. **Commit:**
   ```
   git add VERSION CHANGELOG.md
   git commit -m "chore(release): <new-version-string>"
   ```

8. **Tag:**
   - Check if the tag already exists: `git tag -l "<new-version-string>"`
   - If it exists:
     - Use AskUserQuestion:
       - **header:** "Tag conflict"
       - **question:** "Git tag `<new-version-string>` already exists. How should this be handled?"
       - **options:**
         - "Overwrite" / "Delete the existing tag and create a new one on this commit"
         - "Skip tagging" / "Keep the commit but don't create a tag"
         - "Cancel" / "Abort — revert the commit and restore previous version"
     - **Overwrite**: `git tag -d <tag>` then `git tag <tag>`
     - **Skip tagging**: Continue without tagging
     - **Cancel**: `git reset --soft HEAD~1`, restore VERSION and CHANGELOG from before, release lock, stop
   - If it doesn't exist: `git tag "<new-version-string>"`

9. **Release lock.**

### Post-Bump Report

Report to the user:
- Previous version → New version
- Commits included (count)
- Tag created (or skipped)
- Changelog entry preview (first few lines)

---

## Command: `/semver tracking start`

### Check for Existing Config

If `.semver/config.yaml` exists and `tracking: true`:
- Report: "Version tracking is already active. Current version: <version>."
- Stop.

### Check for Archive

Look for `VERSIONING_ARCHIVE.md` in the project root.

**If archive found — Smart Restore:**

1. Read the archive's YAML frontmatter for metadata.
2. Report what was found: "Found a versioning archive from <archived_at>. Last version: <last_version>."
3. Auto-restore VERSION and CHANGELOG from the archive sections (extract content from fenced code blocks).
4. Restore config from the `## Config` section, setting `tracking: true`.
5. If `tags` is in `items_archived`, ask about tag restoration:
   - Use AskUserQuestion:
     - **header:** "Tags"
     - **question:** "The archive contains version tags. Recreating tags is safe locally but may conflict with remote tags if they still exist. Restore them?"
     - **options:**
       - "Restore tags" / "Recreate local tags from the archive"
       - "Skip tags" / "Don't recreate tags — they may still exist on the remote"
   - If restore: Parse the `## Tags` section and recreate tags (verify commits exist first)
6. Inject CLAUDE.md section (see below).
7. Rename `VERSIONING_ARCHIVE.md` to `VERSIONING_ARCHIVE.md.bak`.
8. Commit: `git add -A && git commit -m "chore: restore semver tracking from archive"`
9. Report what was restored.

**If no archive found (or user chooses fresh start):**

1. Ask for starting version:
   - Use AskUserQuestion:
     - **header:** "Version"
     - **question:** "What starting version number should this project use?"
     - **options:**
       - "v0.1.0 (Recommended)" / "Standard starting point for new projects"
       - "v1.0.0" / "Already stable — start at first major release"
       - "v0.0.1" / "Very early stage — pre-feature"

2. Ask about version prefix:
   - Use AskUserQuestion:
     - **header:** "Prefix"
     - **question:** "Should version strings include a 'v' prefix?"
     - **options:**
       - "Yes — v1.2.3" / "Common convention: VERSION file and tags use v prefix"
       - "No — 1.2.3" / "Bare numbers: VERSION file and tags have no prefix"

3. Ask about changelog format:
   - Use AskUserQuestion:
     - **header:** "Changelog"
     - **question:** "Which changelog format do you prefer?"
     - **options:**
       - "Grouped (Recommended)" / "Entries organized by type: Added, Fixed, Changed, etc."
       - "Flat" / "Simple linear bullet list of changes"

4. Ask about target branch:
   - Use AskUserQuestion:
     - **header:** "Branch"
     - **question:** "Which branch should trigger auto-bump hooks? (This is also used for push detection.)"
     - **options:**
       - "main (Recommended)" / "Standard default branch"
       - "master" / "Legacy default branch name"
   - The user can type a custom branch name via "Other"

5. Create `.semver/config.yaml` with:
   ```yaml
   tracking: true
   auto_bump: false
   auto_bump_confirm: true
   version_prefix: "<chosen>"
   changelog_format: "<chosen>"
   target_branch: "<chosen>"
   ```

6. Create `VERSION` file with the chosen starting version string (prefix + number + newline).

7. Create `CHANGELOG.md` with the initial template (see `references/changelog-format.md`), using the starting version and today's date. Mark as `_[manual]_`.

8. **Inject CLAUDE.md section:** Follow the protocol in `references/claude-md-injection.md`:
   - Check if `<!-- semver:start -->` already exists in CLAUDE.md
   - If yes: replace the block between sentinels
   - If no: append the block (with a preceding blank line) to the end of CLAUDE.md
   - If CLAUDE.md doesn't exist: create it with just the semver block

9. Commit:
   ```
   git add .semver/config.yaml VERSION CHANGELOG.md CLAUDE.md
   git commit -m "chore: initialize semver tracking at <version>"
   git tag "<version>"
   ```

10. Report: version set, files created, CLAUDE.md updated.

---

## Command: `/semver tracking stop`

### Pre-check

Read `.semver/config.yaml`. If missing or `tracking: false`:
- Report: "Version tracking is not active."
- Stop.

### Ask What to Archive

Use AskUserQuestion:
- **header:** "Archive"
- **question:** "Which version-related items would you like to archive? Archived items will be saved to VERSIONING_ARCHIVE.md before deletion."
- **options:**
  - "VERSION file" / "Archive the current version number"
  - "CHANGELOG" / "Archive the full changelog history"
  - "Git tags" / "Archive the list of version tags"
- **multiSelect:** true

### Handle Git Tags

If the user selected git tags for archival:

1. List the version tags: `git tag -l '<prefix>*' --sort=-v:refname`
2. Use AskUserQuestion:
   - **header:** "Remote tags"
   - **question:** "Should version tags also be deleted from the remote? Warning: deleting remote tags affects all collaborators and is irreversible. For multi-collaborator repositories, it's recommended to keep remote tags."
   - **options:**
     - "Delete local only (Recommended)" / "Remove local tags but leave remote tags intact"
     - "Delete local and remote" / "Remove tags everywhere — I understand the impact"
     - "Don't delete tags" / "Archive the tag list but leave all tags in place"

### Build Archive

Write `VERSIONING_ARCHIVE.md` following the format in `references/archive-format.md`:
1. YAML frontmatter with metadata and `items_archived` list
2. `## VERSION` section (if archived): embed VERSION file content in fenced code block
3. `## CHANGELOG` section (if archived): embed CHANGELOG.md content in fenced code block
4. `## Tags` section (if archived): embed output of `git tag -l '<prefix>*' --format='%(refname:short)  %(objectname:short)  %(creatordate:short)  %(subject)'`
5. `## Config` section (always): embed `.semver/config.yaml` content

### Clean Up

1. Set `tracking: false` in `.semver/config.yaml` (also set `auto_bump: false`)
2. Delete archived files (VERSION, CHANGELOG.md — only the ones the user chose to archive)
3. Delete local tags if the user chose to:
   - Local only: `git tag -d <tag>` for each version tag
   - Local + remote: `git tag -d <tag>` then `git push origin --delete <tag>` for each
4. Remove CLAUDE.md injection: delete everything between `<!-- semver:start -->` and `<!-- semver:end -->` inclusive
5. Commit:
   ```
   git add -A
   git commit -m "chore: stop semver tracking — archived to VERSIONING_ARCHIVE.md"
   ```

6. Report: what was archived, what was deleted, where the archive is.

---

## Command: `/semver auto-bump start`

### Pre-check

Read `.semver/config.yaml`. If missing or `tracking: false`:
- Report: "Version tracking must be active before enabling auto-bump. Run `/semver tracking start` first."
- Stop.

If `auto_bump: true` already:
- Report: "Auto-bump is already enabled."
- Stop.

### Configure

Use AskUserQuestion:
- **header:** "Confirm"
- **question:** "When auto-bump triggers after a push, should Claude ask you to confirm the bump level before executing?"
- **options:**
  - "Yes — confirm first (Recommended)" / "Claude proposes major/minor/patch and waits for your approval"
  - "No — fully automatic" / "Claude decides and executes the bump without asking"

### Apply

1. Update `.semver/config.yaml`: set `auto_bump: true` and `auto_bump_confirm: <chosen>`.
2. Report:
   - Auto-bump is now enabled
   - The PostToolUse hook will detect pushes to `<target_branch>` and trigger version analysis
   - Confirmation mode: on/off
   - Note: the hook reads config on every invocation, so this takes effect immediately

---

## Command: `/semver auto-bump stop`

### Pre-check

Read `.semver/config.yaml`. If missing or `tracking: false` or `auto_bump: false`:
- Report: "Auto-bump is not currently enabled."
- Stop.

### Apply

1. Update `.semver/config.yaml`: set `auto_bump: false`.
2. Report:
   - Auto-bump is now disabled
   - The hook will now show a nudge message instead of triggering automatic bumps
   - You can still bump manually with `/semver bump <major|minor|patch>`

---

## File Lock Protocol

For bump operations, follow the locking protocol in `references/file-locking.md`. The key points:

1. Generate a per-project lock path: `/tmp/semver-<hash>.lock`
2. Detect platform: `command -v flock` → use flock; else use mkdir fallback
3. Acquire lock before reading VERSION
4. Release lock after tagging (or on error)
5. If lock cannot be acquired: report "Another semver operation is in progress" and stop
6. On any failure inside the lock: clean up partial changes (`git checkout VERSION CHANGELOG.md`), release lock, report error

## Version Increment Logic

```
Given current version MAJOR.MINOR.PATCH:
  major → (MAJOR+1).0.0
  minor → MAJOR.(MINOR+1).0
  patch → MAJOR.MINOR.(PATCH+1)
```

To parse: strip the version prefix (if any), split on `.`, extract three integers.
To format: rejoin with `.`, prepend the configured version prefix.
