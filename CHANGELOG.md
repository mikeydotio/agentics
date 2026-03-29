# Changelog

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [v1.2.0] - 2026-03-29

### Added
- Conductor autonomous workflow guide — end-to-end documentation for plan-to-completion autonomous execution (`5434010`)

### Fixed
- Session-start hook now uses `additionalContext` instead of `systemMessage` for proper context injection (`2d47db8`)

### Changed
- Track tool config files (`.storyhook`, `.semver`) and gitignore `.planning/` directory (`5ec366e`)

_[manual]_

## [v1.1.0] - 2026-03-28

### Added
- Git-root enforcement — semver tracking now requires `.semver/` to be at the git root; subprojects must use separate git repos
- Configurable git tagging — new `git_tagging` config option (default: true) to enable/disable tag creation on bump
- `--no-tags` flag for `tracking start` to initialize with tagging disabled

### Changed
- Version-commit is now the primary anchor instead of git tags — `semver current` and bump pre-checks use the last VERSION-changing commit, not the last tag
- Session-start hook output simplified to `<Project> version: <version>` instead of verbose status line
- Validation checks 3, 4, 6 (tag-related) now skip gracefully when `git_tagging: false`
- Post-push hook messages reference "last version change" instead of "last tag"

_[manual]_

## [v1.0.0] - 2026-03-28

### Added
- Initial release of the Handy Plugins marketplace
- Ideate plugin — idea interrogation, design, planning, and execution with cross-functional agent teams
- RCA plugin — root cause analysis with evidence collection, hypothesis testing, and remediation planning
- Semver plugin — semantic versioning lifecycle management with auto-bump hooks, changelog generation, and sync validation

_[manual]_
