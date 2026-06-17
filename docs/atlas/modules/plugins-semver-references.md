---
module: plugins/semver/references
summary: "Normative contracts for semver artifacts — config, changelog, archive, locking, validation, hooks, CLAUDE.md block"
read_when: "Changing semver file formats, bump/validate/hook contracts, or the CLAUDE.md block"
sources:
  - path: plugins/semver/references/archive-format.md
  - path: plugins/semver/references/changelog-format.md
  - path: plugins/semver/references/claude-md-injection.md
  - path: plugins/semver/references/config-schema.md
  - path: plugins/semver/references/file-locking.md
  - path: plugins/semver/references/sync-validation.md
  - path: plugins/semver/references/user-hooks.md
references_modules: [plugins-semver-hooks, plugins-semver-misc, root-misc]
generator: cartographer/2
---

# Module: plugins/semver/references

## Purpose

Contract layer of the semver plugin: each doc owns exactly one on-disk format or runtime
protocol — config, changelog, archive, the CLAUDE.md block, the bump lock, sync
checks, and user hooks. `semver-cli` implements every contract and the bash hook scripts
re-implement the grep-parseable subset, so format drift surfaces here first. Some docs script the bump as SKILL.md bash
(`plugins/semver/references/file-locking.md:66`); the CLI is the implementer — read these
docs for the contracts, `semver-cli` for the mechanics.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `Archive Format` | doc | `plugins/semver/references/archive-format.md:1` | Owns VERSIONING_ARCHIVE.md: frontmatter, fenced sections, smart-restore protocol |
| `Changelog Format` | doc | `plugins/semver/references/changelog-format.md:1` | Owns CHANGELOG.md: grouped/flat layouts, prefix→group map, bump-source indicators |
| `CLAUDE.md Injection` | doc | `plugins/semver/references/claude-md-injection.md:1` | Owns the sentinel-delimited CLAUDE.md block: template, idempotent insert, removal |
| `Config Schema` | doc | `plugins/semver/references/config-schema.md:1` | Owns `.semver/config.yaml`: flat single-line fields, defaults, bash parse recipe |
| `File Locking Protocol` | doc | `plugins/semver/references/file-locking.md:1` | Owns the per-project bump lock: flock else mkdir, stale sweep, spans read→write→commit→tag |
| `Sync Validation & Repair` | doc | `plugins/semver/references/sync-validation.md:1` | Owns `/semver validate` checks, the session-start light check, guided repair scenarios |
| `User-Defined Hooks` | doc | `plugins/semver/references/user-hooks.md:1` | Owns `.semver/hooks/`: script env/exit-code contract, PROMPT_HOOK.md rules, re-entrancy |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `<!-- semver:start -->` | sentinel | `plugins/semver/references/claude-md-injection.md:61` | Marks the managed CLAUDE.md block; grep anchor for idempotent replace and removal |
| `SEMVER_BUMP_IN_PROGRESS` | env var | `plugins/semver/references/user-hooks.md:32` | Re-entrancy guard set for the whole bump flow; blocks recursive `/semver bump` from hooks |
| `VERSIONING_ARCHIVE.md` | artifact | `plugins/semver/references/archive-format.md:1` | Round-trip file: `tracking stop` writes, `tracking start` restores |
| `[!DESYNC]` | warning token | `plugins/semver/references/sync-validation.md:87` | Session-start flag emitted when VERSION and the latest git tag disagree |
| `get_config` | bash function | `plugins/semver/references/config-schema.md:65` | Canonical grep/sed config parse recipe replicated in the hook scripts |

## Relationships

- `plugins-semver-hooks.post-push-check.sh -> plugins-semver-references.config-schema.md (reads)`
- `plugins-semver-hooks.run-user-hooks.sh -> plugins-semver-references.user-hooks.md (implements)`
- `plugins-semver-hooks.session-start.sh -> plugins-semver-references.config-schema.md (reads)`
- `plugins-semver-hooks.session-start.sh -> plugins-semver-references.sync-validation.md (implements)`
- `plugins-semver-misc.README.md -> plugins-semver-references.user-hooks.md (reads)`
- `plugins-semver-misc.SKILL.md -> plugins-semver-references.user-hooks.md (reads)`
- `plugins-semver-misc.semver-cli -> plugins-semver-references.archive-format.md (implements)`
- `plugins-semver-misc.semver-cli -> plugins-semver-references.changelog-format.md (implements)`
- `plugins-semver-misc.semver-cli -> plugins-semver-references.claude-md-injection.md (implements)`
- `plugins-semver-misc.semver-cli -> plugins-semver-references.config-schema.md (implements)`
- `plugins-semver-misc.semver-cli -> plugins-semver-references.file-locking.md (implements)`
- `plugins-semver-misc.semver-cli -> plugins-semver-references.sync-validation.md (implements)`
- `plugins-semver-misc.semver-cli -> plugins-semver-references.user-hooks.md (implements)`
- `root-misc.CLAUDE.md -> plugins-semver-references.claude-md-injection.md (reads)`

## Type notes

- A failing pre-bump script aborts the bump (`plugins/semver/references/user-hooks.md:42`).
- A failing post-bump script warns, never rolls back (`plugins/semver/references/user-hooks.md:46`).
- PROMPT_HOOK.md is read by Claude, never executed (`plugins/semver/references/user-hooks.md:62`).
- Repair always asks; nothing auto-fixes (`plugins/semver/references/sync-validation.md:94`).
- Tag checks [SKIP] when `git_tagging` is false (`plugins/semver/references/sync-validation.md:23`).

## External deps

- Keep a Changelog — convention behind the grouped layout
- flock / mkdir — POSIX lock primitives; mkdir is the macOS fallback
- git — tags, log ranges, and commit anchoring behind every sync check

## Gotchas

- Hook order is byte order: `10-` before `2-` (`plugins/semver/references/user-hooks.md:283`).
- A SIGKILL leaves the mkdir lock behind (`plugins/semver/references/file-locking.md:61`).
- Comments in config break hook parsing (`plugins/semver/references/config-schema.md:81`).
- `## Config` is archived even if unselected (`plugins/semver/references/archive-format.md:114`).
