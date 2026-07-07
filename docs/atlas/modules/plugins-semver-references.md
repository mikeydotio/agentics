---
module: plugins/semver/references
summary: "Reference specs for semver's VERSION/CHANGELOG/tag formats, config schema, file locking, and bump hook protocols."
read_when: "Changing semver's file formats, bump/hook contracts, or the CLAUDE.md injection block"
sources:
  - path: plugins/semver/references/archive-format.md
    blob: 19e8d809d697e0eff37c2ba2859189966d5c1a85
  - path: plugins/semver/references/changelog-format.md
    blob: 9a19b979419d9c82c6498374f09f447ce28f0648
  - path: plugins/semver/references/claude-md-injection.md
    blob: e2de01106a3e3a54eab381facc3cacb0e089d2cd
  - path: plugins/semver/references/config-schema.md
    blob: 097ecc3495c8566e0458f0f3b7e49ab220a8a7e2
  - path: plugins/semver/references/file-locking.md
    blob: b8ac09df7a2d89649f2c7c5e46a0d6ba79353c51
  - path: plugins/semver/references/set-and-init.md
    blob: 5e32d26ef08f3b33324765bd9f803aedae1728ae
  - path: plugins/semver/references/sync-validation.md
    blob: 1100011114eb836ee91e61945651835351cc0e1d
  - path: plugins/semver/references/user-hooks.md
    blob: b8909535d97ccea22cb97d62b935a12cd57f77ad
generator: cartographer/4
baseline: cb09ceb006e3fb4759a91d64d9e6655e67d04bf7
---

# Module: plugins/semver/references

## Purpose

This module is the semver plugin's specification layer: seven reference docs pin down the exact byte-level contracts — VERSIONING_ARCHIVE.md structure, CHANGELOG.md formats, the sentinel-delimited CLAUDE.md injection, config.yaml schema, cross-platform file locking, sync validation/repair scenarios, and pre/post-bump hook execution — that the semver SKILL.md commands implement. What holds it together is determinism: every format is specified precisely enough (field names, exit codes, sentinel markers, hash comparisons, group-category mappings) that hook scripts can parse config with grep/sed and validation can compare exact commit hashes instead of guessing. If this module vanished, the skill would lose its single source of truth for VERSION/CHANGELOG/tag sync rules and hook contracts, and separate bump runs could silently drift into incompatible formats.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

- `.semver/config.yaml` must always be written in full (never partial fields) so grep/sed-based hook parsing stays valid — plugins/semver/references/config-schema.md:79.
- `VERSIONING_ARCHIVE.md` is a one-shot handoff artifact: written by `tracking stop`, consumed by `tracking start`, then renamed to `.bak` once restored so it is never re-consumed — plugins/semver/references/archive-format.md:124.
- The per-project lock at `/tmp/semver-<hash>.lock` (or `.lock.d` on macOS) scopes exactly the read-modify-write-commit-tag sequence of one bump, not the whole SKILL.md flow — plugins/semver/references/file-locking.md:100-108.
- `SEMVER_BUMP_IN_PROGRESS=1` is a re-entrancy guard set for the lifetime of one bump flow and checked as the bump's first step, blocking any hook-triggered nested bump — plugins/semver/references/user-hooks.md:98,110.
- The injected CLAUDE.md block is owned by the `<!-- semver:start -->`/`<!-- semver:end -->` sentinel pair and is idempotently replaced in place by `tracking start` / removed by `tracking stop`, never duplicated — plugins/semver/references/claude-md-injection.md:59-62,69-70.

## External deps


## Gotchas

- Hook execution order is strict ASCII byte-order, not natural sort: `10-build.sh` runs before `2-x.sh` unless prefixes are zero-padded (plugins/semver/references/user-hooks.md:283).
- `.semver/config.yaml` must never contain comments — hooks parse it with grep/sed, and comments would break that parsing (plugins/semver/references/config-schema.md:82).
- The macOS `mkdir`-based lock fallback is not released if the process is SIGKILLed, so a >300s stale-lock age check is the only recovery path (plugins/semver/references/file-locking.md:61-62).
- Orphaned git tags (tag with no matching CHANGELOG entry) are reported as WARN, not FAIL, during `/semver validate` since they don't corrupt current version state (plugins/semver/references/sync-validation.md:51-53).
