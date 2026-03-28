# Archive Format: VERSIONING_ARCHIVE.md

When `tracking stop` archives version-related information, it writes a structured file that can be read and processed by a subsequent `tracking start`.

## File Format

```markdown
---
archived_at: "2026-03-24T15:30:00Z"
last_version: "v1.2.0"
version_prefix: "v"
git_tagging: true
changelog_format: "grouped"
target_branch: "main"
auto_bump: false
auto_bump_confirm: true
items_archived:
  - version
  - changelog
  - tags
---

# Versioning Archive

This file is a historical archive of version tracking data. It was generated
by the semver plugin when version tracking was stopped. This file is static
and should not be manually edited.

To restore version tracking from this archive, run `/semver tracking start`.

## VERSION

```
v1.2.0
```

## CHANGELOG

```markdown
# Changelog

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [v1.2.0] - 2026-03-24

### Added
- User authentication flow (abc1234)

_[manual]_

## [v1.1.0] - 2026-03-20

### Fixed
- Database connection timeout (def5678)

_[auto]_

## [v0.1.0] - 2026-03-15

- Initial version tracking

_[manual]_
```

## Tags

```
v0.1.0  a1b2c3d  2026-03-15  Initial version tracking
v1.1.0  d4e5f6a  2026-03-20  chore(release): v1.1.0
v1.2.0  7b8c9d0  2026-03-24  chore(release): v1.2.0
```

## Config

```yaml
tracking: true
auto_bump: false
auto_bump_confirm: true
version_prefix: "v"
git_tagging: true
changelog_format: "grouped"
target_branch: "main"
```
```

## YAML Frontmatter

The frontmatter captures metadata needed for smart restoration:

| Field | Purpose |
|-------|---------|
| `archived_at` | ISO 8601 timestamp of when archival occurred |
| `last_version` | The version string at time of archival (with prefix) |
| `version_prefix` | Config value at archival time |
| `git_tagging` | Config value at archival time |
| `changelog_format` | Config value at archival time |
| `target_branch` | Config value at archival time |
| `auto_bump` | Config value at archival time |
| `auto_bump_confirm` | Config value at archival time |
| `items_archived` | List of which items were archived: `version`, `changelog`, `tags` |

## Sections

Each section is delimited by a `## <NAME>` header and contains the original content in a fenced code block. The code block preserves exact formatting.

| Section | Content |
|---------|---------|
| `## VERSION` | Exact contents of the VERSION file |
| `## CHANGELOG` | Exact contents of CHANGELOG.md |
| `## Tags` | Output of `git tag -l '<prefix>*' --format='%(refname:short)  %(objectname:short)  %(creatordate:short)  %(subject)'` |
| `## Config` | Exact contents of `.semver/config.yaml` |

Only sections for items the user chose to archive are included. The `Config` section is always included regardless of user selection.

## Smart Restore Protocol

When `tracking start` finds a VERSIONING_ARCHIVE.md:

1. **Parse frontmatter** for metadata and `items_archived` list
2. **Auto-restore VERSION and CHANGELOG**: Extract content from the fenced code blocks in the `## VERSION` and `## CHANGELOG` sections. Write to their respective files.
3. **Ask about tags**: If `tags` is in `items_archived`, present the tag list and ask the user if they want to recreate them. Warn about implications (tags may already exist on remote).
4. **Restore config**: Read the `## Config` section and write to `.semver/config.yaml`, with `tracking: true`.
5. **Rename archive**: After successful restoration, rename `VERSIONING_ARCHIVE.md` to `VERSIONING_ARCHIVE.md.bak`.

## Partial Archives

If the user only archived some items (e.g., VERSION and CHANGELOG but not tags), only those sections appear in the archive. The restore protocol handles missing sections gracefully — it only restores what's present.

## Tag Recreation

When restoring tags from the archive:

```bash
# Parse each line: tag_name  commit_hash  date  message
while IFS=$'\t' read -r tag hash date msg; do
  tag=$(echo "$tag" | xargs)
  hash=$(echo "$hash" | xargs)
  # Only recreate if the commit exists locally
  if git cat-file -e "$hash" 2>/dev/null; then
    git tag "$tag" "$hash" 2>/dev/null || echo "Tag $tag already exists, skipping"
  else
    echo "Warning: Commit $hash for tag $tag not found locally, skipping"
  fi
done <<< "$TAG_DATA"
```
