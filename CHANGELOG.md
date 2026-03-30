# Changelog

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [v1.4.0] - 2026-03-30

### Removed
- **Memory plugin** (`/memory`) — collides with built-in Claude Code command; memory functionality will move to the memlayer repo as its own plugin (`a64050e`)

### Changed
- Cleaned up pilot plugin references to memory (execution loop, handoff format, completion sequence) (`a64050e`)

_[manual]_

## [v1.3.0] - 2026-03-30

### Added
- **Pilot plugin** (`/pilot`) — autonomous execution harness with generator-evaluator loop, story decomposition, session locking, auto-resume via crontab, canary mode, and architectural drift detection (`c6cab14`)
- **Memory plugin** (`/memory`) — graph memory interface with local JSONL cache, entity/relation storage, two-tier recall (local + memlayer), and scale-aware warnings (`c6cab14`)
- **Ideate Phase 4.5** — conductor handoff gate offering autonomous execution via `/pilot` after plan approval (`c6cab14`)
- Test infrastructure using bats-core with 15 tests covering state machine, locking, and plan mapping (`c6cab14`)

### Changed
- Renamed project from handy-plugins to agentic-workflows; tracked `.planning/` directory (`ce06592`)
- Updated marketplace to register 5 plugins (ideate, rca, semver, pilot, memory) (`c6cab14`)

_[manual]_

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
- Initial release of the Agentic Workflows marketplace
- Ideate plugin — idea interrogation, design, planning, and execution with cross-functional agent teams
- RCA plugin — root cause analysis with evidence collection, hypothesis testing, and remediation planning
- Semver plugin — semantic versioning lifecycle management with auto-bump hooks, changelog generation, and sync validation

_[manual]_
