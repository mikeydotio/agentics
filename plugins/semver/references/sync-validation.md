# Sync Validation & Repair

The semver plugin maintains three artifacts that must stay in sync: the **VERSION file**, the **CHANGELOG.md**, and **git tags**. This reference documents the validation checks and guided repair procedures.

## Validation Checks

Run via `/semver validate`. All checks execute in order; each reports PASS, FAIL, or WARN.

### Check 1: Config exists, tracking active

- **How:** Read `.semver/config.yaml`, verify `tracking: true`
- **PASS:** Config found and tracking is active
- **FAIL:** Config missing or `tracking: false`

### Check 2: VERSION exists and well-formed

- **How:** Read VERSION file, match against `<prefix>MAJOR.MINOR.PATCH` where prefix is from config
- **PASS:** File exists and content matches expected format (e.g., `v1.2.3` or `1.2.3`)
- **FAIL:** File missing, empty, or malformed

### Check 3: Tag exists for current VERSION

**Only run if `git_tagging: true` in config. If `git_tagging: false`, report `[SKIP] Git tagging disabled`.**

- **How:** `git tag -l "<version_string>"` where version_string is the content of VERSION
- **PASS:** Tag exists
- **FAIL:** No matching tag found — tag was never created or was deleted

### Check 4: Tag points to correct commit

**Only run if `git_tagging: true` in config. If `git_tagging: false`, report `[SKIP] Git tagging disabled`.**

- **How:** Compare two commit hashes:
  - Tag's commit: `git rev-list -n 1 <tag>`
  - Last VERSION modification: `git log -1 --format=%H -- VERSION`
- **PASS:** Both hashes match — the tag was created on the same commit that last wrote VERSION
- **FAIL:** Hashes differ — VERSION was modified after the tag was created (manual edit detected)

### Check 5: CHANGELOG has entry for current VERSION

- **How:** Search CHANGELOG.md for a header matching `## [<version_string>]`
- **PASS:** Header found
- **FAIL:** No matching header — changelog entry is missing for this version

### Check 6: No orphaned tags

**Only run if `git_tagging: true` in config. If `git_tagging: false`, report `[SKIP] Git tagging disabled`.**

- **How:** List all tags matching the version prefix pattern (`git tag -l '<prefix>*'`), then for each tag check that CHANGELOG.md contains a `## [<tag>]` header
- **PASS:** Every tag has a corresponding changelog entry
- **WARN:** One or more tags have no changelog entry (orphaned tags)

This is a WARN rather than FAIL because orphaned tags don't break the current version state — they're historical inconsistencies.

## Validation Output Format

```
[semver] Validation results:
  [PASS] Config exists and tracking is active
  [PASS] VERSION file: v1.2.0
  [PASS] Tag v1.2.0 exists
  [FAIL] Tag → abc1234, VERSION last modified → def5678
  [PASS] CHANGELOG entry for v1.2.0
  [WARN] 1 orphaned tag(s): v0.8.0 has no CHANGELOG entry
  Status: 1 failure, 1 warning. Run /semver repair to fix.
```

When all checks pass:
```
[semver] Validation results:
  [PASS] Config exists and tracking is active
  [PASS] VERSION file: v1.2.0
  [PASS] Tag v1.2.0 exists
  [PASS] Tag and VERSION point to same commit (abc1234)
  [PASS] CHANGELOG entry for v1.2.0
  [PASS] No orphaned tags
  Status: All checks passed.
```

## Session-Start Lightweight Check

The session-start hook runs a subset of the above to provide early warning without slowing down session startup:

- **Primary anchor:** Find the commit that last modified VERSION via `git log -1 --format=%H -- VERSION`. Use this to count commits since the last version change.
- **Tag check (only if `git_tagging: true`):** Compare VERSION content against the latest tag name from `git describe --tags --abbrev=0`
  - If they differ: append `[!DESYNC]` warning and suggest running `/semver validate`
  - If no tag exists for the VERSION content: append `[!NO_TAG]` warning
- **When `git_tagging: false`:** Skip tag-based checks entirely. No DESYNC/NO_TAG warnings.

This is intentionally lightweight — the full `/semver validate` command runs the complete check suite.

## Repair Scenarios

Run via `/semver repair`. Runs `/semver validate` first to identify issues, then presents guided options for each failure. Repair is never automatic — the user always chooses.

### Scenario 1: VERSION ahead of latest tag

**Detection:** VERSION says `v1.3.0`, latest tag is `v1.2.0`, no tag `v1.3.0` exists.

**Options (via AskUserQuestion):**
- **"Create tag + changelog entry"** — Treat the VERSION as a legitimate release. Generate a changelog entry from `git log v1.2.0..HEAD`, commit it, then create the `v1.3.0` tag. Commit message: `chore(release): v1.3.0 [repair]`
- **"Revert VERSION"** — The VERSION was edited by mistake. Write the latest tag's version back to VERSION. Commit message: `chore: revert VERSION to match tag v1.2.0`
- **"Skip"** — Leave it for manual handling.

### Scenario 2: Tag exists, CHANGELOG entry missing

**Detection:** Tag `v1.2.0` exists, VERSION says `v1.2.0`, but CHANGELOG has no `## [v1.2.0]` header.

**Options:**
- **"Generate entry"** — Find the previous tag (`git describe --tags --abbrev=0 v1.2.0^ `), generate a changelog entry from `git log <prev-tag>..v1.2.0`, insert it at the correct position in CHANGELOG.md. Commit message: `chore: add missing CHANGELOG entry for v1.2.0 [repair]`
- **"Skip"**

### Scenario 3: Tag points to wrong commit

**Detection:** Tag `v1.2.0` exists, VERSION says `v1.2.0`, but the tag's commit differs from the commit that last modified VERSION.

**Options:**
- **"Move tag"** — Delete the old tag and recreate it at the commit that last modified VERSION. This is a local-only operation; if the tag exists on a remote, warn about divergence.
- **"Revert VERSION"** — The VERSION file was edited by mistake. Restore it to match the tagged commit's content using `git show <tag>:VERSION`.
- **"Skip"**

### Scenario 4: VERSION behind latest tag

**Detection:** Latest tag is `v1.3.0` but VERSION says `v1.2.0`.

**Options:**
- **"Update VERSION"** — Write `v1.3.0` to VERSION to match the tag. Commit message: `chore: sync VERSION to match tag v1.3.0`
- **"Delete tag"** — The tag was created in error. Delete it locally (and optionally from remote after confirmation).
- **"Skip"**

## Post-Repair

After all repair actions complete, re-run the full validation suite and report the final status. If issues remain, list them. If all pass, report: "All integrity checks passed."
