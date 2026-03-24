# Changelog Format

The CHANGELOG.md file records version history with newest versions at the top. Two formats are supported, controlled by `changelog_format` in `.semver/config.yaml`.

## Grouped Format (`changelog_format: "grouped"`)

Entries are organized by change type following Keep a Changelog conventions:

```markdown
# Changelog

## [v1.2.0] - 2026-03-24

### Added
- Implement user authentication flow (abc1234)
- Add rate limiting to API endpoints (def5678)

### Fixed
- Resolve race condition in queue processor (789abcd)

### Changed
- Improve error messages for validation failures (bcd4567)

_[manual]_

## [v1.1.0] - 2026-03-20

### Added
- Initial API endpoint scaffolding (1234567)

_[auto]_
```

### Group Categories

Map conventional commit prefixes to groups:

| Commit Prefix | Group |
|--------------|-------|
| `feat:` | **Added** |
| `fix:` | **Fixed** |
| `refactor:`, `perf:` | **Changed** |
| `docs:` | **Documentation** |
| `test:` | **Testing** |
| `chore:`, `build:`, `ci:` | **Maintenance** |
| `BREAKING CHANGE` or `!:` | **Breaking** |
| (no prefix) | **Changed** (default) |

Only include groups that have entries — do not show empty groups.

When Claude generates the summary, it should read the actual git diff/log and write human-friendly descriptions, not just copy commit messages verbatim. Short commit hashes in parentheses link entries to their commits.

## Flat Format (`changelog_format: "flat"`)

Simple linear bullet list:

```markdown
# Changelog

## [v1.2.0] - 2026-03-24
- abc1234 Implement user authentication flow
- def5678 Add rate limiting to API endpoints
- 789abcd Fix race condition in queue processor
- bcd4567 Improve error messages for validation failures

_[manual]_

## [v1.1.0] - 2026-03-20
- 1234567 Initial API endpoint scaffolding

_[auto]_
```

## Bump Source Indicators

Every version section ends with an indicator showing how the bump was triggered:

| Indicator | Meaning |
|-----------|---------|
| `_[manual]_` | User explicitly ran `/semver bump` |
| `_[auto]_` | Auto-bump hook triggered the version change |
| `_[force]_` | User ran `/semver bump --force` with no changes since last tag |

## Initial CHANGELOG Template

When `tracking start` creates the CHANGELOG for the first time:

```markdown
# Changelog

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [v0.1.0] - 2026-03-24

- Initial version tracking

_[manual]_
```

The version and prefix should match the user's chosen starting version and config settings.

## Version Header Format

```
## [<version_prefix><version>] - <YYYY-MM-DD>
```

- `version_prefix`: from config (`""` or `"v"`)
- `version`: semver string (e.g., `1.2.0`)
- Date: ISO 8601 date of the bump

## Claude's Changelog Generation Process

When generating a changelog entry for a bump, Claude should:

1. Run `git log <last-tag>..HEAD --format="%h %s"` to get commits since last tag
2. Read the diffs if commit messages are unclear: `git diff <last-tag>..HEAD --stat`
3. Group commits by type (for grouped format) or list linearly (for flat format)
4. Write concise, user-friendly descriptions — not raw commit messages
5. Include short commit hashes for traceability
6. Prepend the new version section to CHANGELOG.md (after the title line)
