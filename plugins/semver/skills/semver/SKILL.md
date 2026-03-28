---
name: semver
description: Use when the user wants to manage semantic versioning for their project. Handles version tracking (start/stop), version bumping (major/minor/patch) with AI-generated changelog entries, reading current version, auto-bump configuration, and sync integrity validation/repair. Commands are /semver current, /semver bump, /semver tracking, /semver auto-bump, /semver validate, and /semver repair.
argument-hint: <current | bump <major|minor|patch> [--force] | tracking <start [options]|stop> | auto-bump <start|stop> | validate | repair>
---

# Semantic Versioning Orchestrator

You are a semantic versioning lifecycle manager. You handle version tracking, bumping, changelog generation, and auto-bump configuration for the project.

**Read these references before executing any command:**
- `references/config-schema.md` — `.semver/config.yaml` schema and parsing
- `references/file-locking.md` — File lock protocol for bump operations
- `references/changelog-format.md` — CHANGELOG format specs and indicators
- `references/claude-md-injection.md` — CLAUDE.md template and sentinel markers
- `references/archive-format.md` — VERSIONING_ARCHIVE.md format for tracking stop/start
- `references/sync-validation.md` — Validation checks and repair procedures for VERSION/CHANGELOG/tag sync
- `references/user-hooks.md` — User-defined hook system for pre-bump and post-bump automation

## Hard Rules

1. **Always read `.semver/config.yaml` first** (if it exists) to determine project state before any operation.
2. **Never modify VERSION or CHANGELOG without holding the file lock** during bump operations.
3. **Never fabricate changelog entries** — always read the actual git log and summarize real changes.
4. **Respect the `version_prefix` setting** — apply it consistently to VERSION file content and git tags.
5. **Every question to the user MUST use `AskUserQuestion`** with exactly 1 question per call.
6. **Mark bump source** — every CHANGELOG version entry must end with `_[manual]_`, `_[auto]_`, or `_[force]_`.
7. **Validate before bumping** — run sync integrity checks before every bump. If VERSION, CHANGELOG, or tags are out of sync, present repair options before proceeding.

## Command Router

Parse the ARGUMENTS string to determine which command to run:

| Argument starts with | Command |
|---------------------|---------|
| `current` or empty | `/semver current` |
| `bump` | `/semver bump` |
| `tracking` | `/semver tracking` |
| `auto-bump` | `/semver auto-bump` |
| `validate` or `check` | `/semver validate` |
| `repair` or `fix` | `/semver repair` |
| Anything else | Show usage help |

**Usage help:**
```
/semver current                        — Show current version and status
/semver bump <major|minor|patch>       — Bump version, generate changelog, commit + tag
/semver bump <major|minor|patch> --force — Bump even with no changes since last tag
/semver tracking start                 — Initialize version tracking (no version set until first bump)
/semver tracking start [options]       — Options: --version <ver>, --prefix <v|none>, --changelog <grouped|flat>, --branch <name>, --restore-tags
/semver tracking stop                  — Archive and disable version tracking
/semver auto-bump start                — Enable automatic version bumps on push to main
/semver auto-bump stop                 — Disable automatic version bumps
/semver validate                       — Verify VERSION/CHANGELOG/tag sync integrity
/semver repair                         — Guided repair of sync issues
```

---

## Command: `/semver current`

1. Check if `.semver/config.yaml` exists. If not:
   - Report: "Version tracking is not active for this project. Run `/semver tracking start` to begin."
   - Stop.

2. Read `.semver/config.yaml` and verify `tracking: true`. If tracking is false:
   - Report: "Version tracking is disabled. Run `/semver tracking start` to re-enable."
   - Stop.

3. Read the `VERSION` file (if it exists). Report:
   - Current version (with prefix per config), or "No version set yet — run `/semver bump` to set the first version." if VERSION does not exist
   - If version is set: last tag date (from `git log -1 --format=%ai <last-tag>`), number of commits since last tag (`git rev-list <last-tag>..HEAD --count`)
   - Auto-bump status (on/off)
   - Target branch

---

## Command: `/semver bump <major|minor|patch> [--force]`

### Parse Arguments

Extract:
- `BUMP_TYPE`: one of `major`, `minor`, `patch` (required — if missing, show usage and stop)
- `FORCE`: true if `--force` is present

### Pre-check: Re-entrancy Guard

Check if the environment variable `SEMVER_BUMP_IN_PROGRESS` is set to `1` by running:
```
echo "${SEMVER_BUMP_IN_PROGRESS:-}"
```

If it equals `1`:
- Report: "A version bump is already in progress. Nested bumps are not allowed — this prevents infinite loops when hooks or PROMPT_HOOK.md instructions inadvertently trigger another bump."
- Stop immediately. Do not proceed with any further checks or operations.

**Also remember internally:** Once you begin executing this bump command (past this point), you are in a bump. Do NOT invoke `/semver bump` again until this entire flow completes, even if a PROMPT_HOOK.md or hook output suggests doing so.

### Pre-check: Tracking Active

Read `.semver/config.yaml`. If missing or `tracking: false`:
- Report: "Version tracking is not active. Run `/semver tracking start` first."
- Stop.

### Pre-check: First Version

If the `VERSION` file does not exist (first bump after `tracking start`):
- Use AskUserQuestion:
  - **header:** "First version"
  - **question:** "No version is set yet. What should the first version be?"
  - **options:**
    - "v0.1.0 (Recommended)" / "Standard starting point for new projects"
    - "v1.0.0" / "Already stable — start at first major release"
    - "v0.0.1" / "Very early stage — pre-feature"
- Write the chosen version to the `VERSION` file (applying the configured `version_prefix`).
- Create `CHANGELOG.md` with the initial template (see `references/changelog-format.md`), using the chosen version and today's date. Mark as `_[manual]_`.
- Commit:
  ```
  git add VERSION CHANGELOG.md
  git commit -m "chore: initialize version at <version>"
  git tag "<version>"
  ```
- Report the version set, then stop. The user can now run `/semver bump` again to perform the actual bump.

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

### Pre-check: Sync Integrity

Run validation checks 1-5 from `/semver validate` (see `references/sync-validation.md`):
1. Config exists and tracking active
2. VERSION exists and well-formed
3. Tag exists for current VERSION
4. Tag points to correct commit (tag commit == last VERSION-modifying commit)
5. CHANGELOG has entry for current VERSION

If any check **FAILS**:
- Report the specific failures to the user.
- Use AskUserQuestion:
  - **header:** "Sync issue"
  - **question:** "Validation found issues with the current version state. Bumping on top of broken sync may compound the problem."
  - **options:**
    - "Run repair first" / "Attempt to fix sync issues, then retry the bump"
    - "Bump anyway" / "I understand the risk — proceed with the bump"
    - "Cancel" / "Abort — I'll investigate manually"
- **Run repair first**: Execute the `/semver repair` flow, re-validate, then proceed with bump if all checks pass.
- **Bump anyway**: Continue to the critical section.
- **Cancel**: Stop.

If all checks **PASS**, proceed silently (no output needed).

### Compute New Version

Before entering the critical section, compute the new version so it can be passed to hooks:

1. **Read current version** from VERSION file. Strip whitespace. Store as `OLD_VERSION`.
2. Remove version prefix if present to get bare `MAJOR.MINOR.PATCH`.
3. **Compute new version:**
   - `major` bump: `MAJOR+1.0.0`
   - `minor` bump: `MAJOR.MINOR+1.0`
   - `patch` bump: `MAJOR.MINOR.PATCH+1`
4. **Apply prefix:** Read `version_prefix` from config. Store as `NEW_VERSION` = `<prefix><MAJOR.MINOR.PATCH>`.

At this point you have: `BUMP_TYPE`, `OLD_VERSION`, and `NEW_VERSION`. These are used by hooks and by the critical section.

### Execute Pre-Bump Hooks

Run user-defined hooks before modifying any version files. See `references/user-hooks.md` for the full contract.

1. **Read PROMPT_HOOK.md:** If `.semver/hooks/pre-bump/PROMPT_HOOK.md` exists, read its contents. Follow the instructions in the file now, in the context of the current bump. The following context is available: `BUMP_TYPE`, `OLD_VERSION`, `NEW_VERSION`. **Do NOT trigger any `/semver bump` commands from within these instructions.** If the instructions indicate the bump should be aborted (e.g., a blocking issue is found), abort the bump and report the reason. After completing the PROMPT_HOOK.md instructions (or if the file does not exist), continue with the next step.

2. **Run hook scripts:** Execute the hook runner:
   ```
   bash <plugin-root>/hooks/run-user-hooks.sh pre-bump <BUMP_TYPE> <OLD_VERSION> <NEW_VERSION> <project-dir>
   ```

   Parse the JSON result:
   - If `status` is `"ok"`: Continue. If `hooks_run` > 0, briefly note: "Pre-bump hooks passed (<N> hooks)."
   - If `status` is `"failed"`: Report which hook failed (`failed_hook`) and the output. **Abort the bump entirely** — do not enter the critical section. Report: "Pre-bump hook `<name>` failed (exit <code>). Bump aborted."
   - If `status` is `"blocked"`: A re-entrancy guard was triggered. Report the reason and stop.
   - If `hooks_run` is 0 and `prompt_hook` is null: No hooks exist. Continue silently.

### Execute Bump (Critical Section)

**All steps below must be performed inside a file lock.** Follow the protocol in `references/file-locking.md`.

Use the pre-computed `OLD_VERSION` and `NEW_VERSION` from the "Compute New Version" step above.

1. **Generate changelog entry:**
   - If FORCE and no commits: Write a brief entry noting this is a version-only adjustment
   - Otherwise:
     - Run `git log <last-tag>..HEAD --format="%h %s"` to get commits
     - If needed for clarity, also check `git diff <last-tag>..HEAD --stat`
     - Read `changelog_format` from config
     - **Grouped format**: Categorize commits by conventional commit prefix (see `references/changelog-format.md`), write concise human-friendly descriptions with commit hashes
     - **Flat format**: List commits linearly with hashes and descriptions
   - Determine the indicator: `_[manual]_` for explicit user bump, `_[auto]_` if triggered by auto-bump hook, `_[force]_` if `--force` was used

2. **Write VERSION file:** Write the new version string (with prefix per config) followed by a newline. Nothing else in the file.

3. **Update CHANGELOG.md:** Prepend the new version section after the title/header lines (before the first existing `## [` section). See `references/changelog-format.md` for exact format.

4. **Commit:**
   ```
   git add VERSION CHANGELOG.md
   git commit -m "chore(release): <new-version-string>"
   ```

5. **Tag:**
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

6. **Release lock.**

### Execute Post-Bump Hooks

Run user-defined hooks after the version has been committed and tagged. See `references/user-hooks.md` for the full contract.

1. **Run hook scripts:** Execute the hook runner:
   ```
   bash <plugin-root>/hooks/run-user-hooks.sh post-bump <BUMP_TYPE> <OLD_VERSION> <NEW_VERSION> <project-dir>
   ```

   Parse the JSON result:
   - If `status` is `"ok"` with no warnings: Continue silently.
   - If `status` is `"ok"` with warnings: For each warning, report: "Post-bump hook `<hook>` failed (exit <code>). The version bump has already been committed. Review the hook output and address any issues manually." **Do NOT roll back the bump.**
   - If `hooks_run` is 0 and `prompt_hook` is null: No hooks exist. Continue silently.

2. **Read PROMPT_HOOK.md:** If `.semver/hooks/post-bump/PROMPT_HOOK.md` exists, read its contents. Follow the instructions in the file now, in the context of the completed bump. The following context is available: `BUMP_TYPE`, `OLD_VERSION`, `NEW_VERSION`. **Do NOT trigger any `/semver bump` commands from within these instructions.** After completing the instructions (or if the file does not exist), continue to the Post-Bump Report.

### Post-Bump Report

Report to the user:
- Previous version → New version
- Commits included (count)
- Tag created (or skipped)
- Changelog entry preview (first few lines)

### Post-Bump Verification

After the bump completes, run a quick integrity check to confirm all three artifacts are in sync:

1. **Tag exists:** `git tag -l "<new-version-string>"` — confirm the expected tag is present.
2. **VERSION matches:** Read VERSION file — confirm its content matches the new version string.
3. **CHANGELOG has entry:** Read the first 20 lines of CHANGELOG.md — confirm a `## [<new-version-string>]` header is present.

If all three pass: no additional output needed (the Post-Bump Report already confirms success).

If any check fails: warn the user immediately with the specific issue and remediation steps. This should not happen under normal conditions — if it does, it indicates an environmental issue (e.g., a git hook modified files after the commit, a disk write failure, or a race condition).

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
5. If `tags` is in `items_archived`:
   - **Default:** Skip tag restoration (tags may still exist on the remote).
   - **Override:** If `--restore-tags` was passed, parse the `## Tags` section and recreate tags (verify commits exist first).
   - Report: "Skipped tag restoration (use `--restore-tags` to recreate them)." or "Restored N tags from archive." as appropriate.
6. Inject CLAUDE.md section (see below).
7. Rename `VERSIONING_ARCHIVE.md` to `VERSIONING_ARCHIVE.md.bak`.
8. Commit: `git add -A && git commit -m "chore: restore semver tracking from archive"`
9. Report what was restored.

**If no archive found — Fresh Start:**

### Parse Options

Extract optional flags from the ARGUMENTS string (everything after `tracking start`):
- `--version <ver>`: Starting version number (bare semver, e.g. `0.1.0`, `1.0.0`). Do not include the prefix here. If omitted, no version is set — the first `/semver bump` will prompt for it.
- `--prefix <v|none>`: `v` for v-prefixed versions, `none` for bare numbers.
- `--changelog <grouped|flat>`: Changelog entry format.
- `--branch <name>`: Target branch for auto-bump hooks and push detection.

**Detect default branch** (used when `--branch` is not provided):
```
git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@'
```
If that fails (e.g. no remote), fall back to `git rev-parse --abbrev-ref HEAD`.

Apply defaults for any option not provided:

| Flag | Default |
|------|---------|
| `--version` | _(none — version set on first bump)_ |
| `--prefix` | `v` |
| `--changelog` | `grouped` |
| `--branch` | _(detected from git)_ |

If any flag has an invalid value, report the error with valid values and stop.

### Create Files

1. Create `.semver/config.yaml` with:
   ```yaml
   tracking: true
   auto_bump: false
   auto_bump_confirm: true
   version_prefix: "<resolved>"
   changelog_format: "<resolved>"
   target_branch: "<resolved>"
   ```

2. **If `--version` was provided:**
   - Create `VERSION` file with the resolved starting version string (prefix + number + newline).
   - Create `CHANGELOG.md` with the initial template (see `references/changelog-format.md`), using the starting version and today's date. Mark as `_[manual]_`.

3. **Inject CLAUDE.md section:** Follow the protocol in `references/claude-md-injection.md`:
   - Check if `<!-- semver:start -->` already exists in CLAUDE.md
   - If yes: replace the block between sentinels
   - If no: append the block (with a preceding blank line) to the end of CLAUDE.md
   - If CLAUDE.md doesn't exist: create it with just the semver block

4. Commit:
   ```
   git add .semver/config.yaml CLAUDE.md
   # Also add VERSION and CHANGELOG.md if they were created
   git commit -m "chore: initialize semver tracking"
   ```
   If `--version` was provided, also create the git tag: `git tag "<version>"`

5. Report: tracking enabled, target branch, and either the version set or "No version set — run `/semver bump` when ready." Also mention: "Tip: You can add custom pre-bump and post-bump hooks in `.semver/hooks/`. Ask me to set one up, or see `references/user-hooks.md` for details."

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

## Command: `/semver validate`

Verifies that VERSION, CHANGELOG.md, and git tags are in sync. See `references/sync-validation.md` for full details on each check.

### Pre-check

Read `.semver/config.yaml`. If missing or `tracking: false`:
- Report: "Version tracking is not active. Nothing to validate."
- Stop.

### Run Checks

Execute all 6 validation checks in order. For each check, report PASS, FAIL, or WARN:

1. **Config exists and tracking active** — already confirmed by pre-check, report PASS.
2. **VERSION exists and well-formed** — read VERSION file, match against `<prefix>MAJOR.MINOR.PATCH`.
3. **Tag exists for current VERSION** — `git tag -l "<version_string>"`.
4. **Tag points to correct commit** — compare `git rev-list -n 1 <tag>` vs `git log -1 --format=%H -- VERSION`.
5. **CHANGELOG has entry for current VERSION** — search for `## [<version_string>]` header in CHANGELOG.md.
6. **No orphaned tags** — for each tag matching `<prefix>*`, check for a corresponding `## [<tag>]` header in CHANGELOG.md.

### Report

Print the validation results in this format:

```
[semver] Validation results:
  [PASS] Config exists and tracking is active
  [PASS] VERSION file: <version>
  [PASS/FAIL] Tag <version> exists / not found
  [PASS/FAIL] Tag and VERSION point to same commit (<hash>) / Tag → <hash1>, VERSION last modified → <hash2>
  [PASS/FAIL] CHANGELOG entry for <version> / No CHANGELOG entry for <version>
  [PASS/WARN] No orphaned tags / N orphaned tag(s): <list>
  Status: <summary>
```

If any FAIL: suggest "Run `/semver repair` to fix."

---

## Command: `/semver repair`

Guided repair for sync issues between VERSION, CHANGELOG.md, and git tags. See `references/sync-validation.md` for full repair scenario details.

### Pre-check

Read `.semver/config.yaml`. If missing or `tracking: false`:
- Report: "Version tracking is not active. Nothing to repair."
- Stop.

### Diagnose

Run the full `/semver validate` check suite. If all checks pass:
- Report: "All integrity checks passed. Nothing to repair."
- Stop.

### Repair Each Failure

For each FAIL detected, present the appropriate repair options via AskUserQuestion. Handle failures in the order they were detected.

**FAIL: Tag missing for current VERSION** (VERSION=`v1.3.0`, latest tag=`v1.2.0` or no tags):

Use AskUserQuestion:
- **header:** "Missing tag"
- **question:** "VERSION says `<version>` but no git tag exists for it."
- **options:**
  - "Create tag + changelog entry" / "Generate a changelog entry from the git log and create the tag. Commit message: chore(release): <version> [repair]"
  - "Revert VERSION" / "Reset VERSION to match the latest tag (<latest_tag>)"
  - "Skip" / "Leave it for now"

Execute the chosen action:
- **Create tag + changelog**: Generate changelog entry from `git log <latest_tag>..HEAD`, update CHANGELOG.md, commit, tag.
- **Revert VERSION**: Write latest tag's version string to VERSION, commit.

**FAIL: CHANGELOG entry missing** (tag exists, VERSION matches, but no `## [<version>]` in CHANGELOG):

Use AskUserQuestion:
- **header:** "Missing changelog"
- **question:** "Version `<version>` is tagged but has no CHANGELOG entry."
- **options:**
  - "Generate entry" / "Create a changelog entry from the git log between the previous tag and this one"
  - "Skip" / "Leave the changelog as-is"

Execute:
- **Generate entry**: Find previous tag (`git describe --tags --abbrev=0 <tag>^`), generate entry from `git log <prev-tag>..<tag>`, insert into CHANGELOG at correct position, commit.

**FAIL: Tag points to wrong commit** (tag and VERSION exist but point to different commits):

Use AskUserQuestion:
- **header:** "Tag mismatch"
- **question:** "Tag `<version>` points to commit `<tag_hash>` but VERSION was last modified in commit `<version_hash>`."
- **options:**
  - "Move tag" / "Delete the old tag and recreate it at the commit that last modified VERSION"
  - "Revert VERSION" / "Restore VERSION to match the tagged commit's content"
  - "Skip" / "Leave the discrepancy"

Execute:
- **Move tag**: `git tag -d <tag>`, `git tag <tag> <version_hash>`. Warn if tag exists on remote.
- **Revert VERSION**: `git show <tag>:VERSION > VERSION`, commit.

**FAIL: VERSION behind latest tag** (latest tag=`v1.3.0`, VERSION=`v1.2.0`):

Use AskUserQuestion:
- **header:** "VERSION behind tag"
- **question:** "Latest tag is `<latest_tag>` but VERSION says `<version>`."
- **options:**
  - "Update VERSION" / "Write <latest_tag> to VERSION to match the tag"
  - "Delete tag" / "The tag was created in error — remove it"
  - "Skip"

Execute:
- **Update VERSION**: Write tag's version to VERSION, commit.
- **Delete tag**: `git tag -d <tag>`. Ask about remote deletion via AskUserQuestion.

### Post-Repair Validation

After all repair actions complete, re-run the full validation suite. Report:
- If all pass: "All integrity checks passed."
- If issues remain: list them and note which require manual intervention.

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
