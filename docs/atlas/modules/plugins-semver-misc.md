---
module: "plugins/semver (misc)"
summary: "Deterministic versioning core — JSON Python CLI, bash router, thin /semver orchestrator skill"
read_when: "Touching /semver commands, bump/changelog/validate logic, or the CLI JSON contract"
sources:
  - path: plugins/semver/.claude-plugin/plugin.json
    blob: d0ebc69ad4829a92f79f4bd147b3d020f656951c
  - path: plugins/semver/README.md
    blob: 355c546fe806712c5d265fe9a33fde1a59d8a1fe
  - path: plugins/semver/bin/semver-cli
    blob: 201e745459e03f4865891b44105f4727ee3998f5
  - path: plugins/semver/bin/semver-router.sh
    blob: 42c4f57e3b77cdaa6e3ef2be6f730603eb0d0e20
  - path: plugins/semver/skills/semver/SKILL.md
    blob: d55b2177ff24c350b85121b63a30700a6267d4a2
references_modules: [plugins-semver-hooks, plugins-semver-references]
generator: cartographer/1
baseline: b9203a6997fdbc2248086c1aa9ee6f62b1e025b6
verified: true
---

# Module: plugins/semver (misc)

## Purpose

All deterministic versioning work — version parsing, changelog generation, sync
validation, locking — lives in one stdlib-only Python CLI. The `/semver` skill never
computes versions or writes changelog text: it routes via the bash router, relays
the CLI's `questions` to the user, and replays answers as flags. `bump run` folds
gather+execute into one call, so a clean bump is one round-trip.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `cmd_auto_bump` | def | `plugins/semver/bin/semver-cli:1884` | `auto-bump start/stop`; start may first return a confirm question |
| `cmd_bump_execute` | def | `plugins/semver/bin/semver-cli:1247` | `bump execute <type>`: locked write+commit+tag with dirty/tag flags |
| `cmd_bump_first_version` | def | `plugins/semver/bin/semver-cli:1422` | `bump first-version <ver>`: initial VERSION, CHANGELOG, commit, tag |
| `cmd_bump_gather` | def | `plugins/semver/bin/semver-cli:981` | `bump gather <type>`: pre-check state + questions; mutates nothing |
| `cmd_bump_run` | def | `plugins/semver/bin/semver-cli:1203` | `bump run <type>`: gather+execute in one call when unblocked; `--non-interactive` aborts |
| `cmd_current` | def | `plugins/semver/bin/semver-cli:810` | `current`: version + commit count + config snapshot |
| `cmd_recommend` | def | `plugins/semver/bin/semver-cli:903` | `recommend`: breaking→major, feat→minor, else patch |
| `cmd_repair_diagnose` | def | `plugins/semver/bin/semver-cli:1953` | `repair diagnose`: failed checks → repair questions |
| `cmd_repair_execute` | def | `plugins/semver/bin/semver-cli:2081` | `repair execute <action>`: create/move/delete tag, revert/update VERSION, generate entry |
| `cmd_tracking_restore_tags` | def | `plugins/semver/bin/semver-cli:1697` | `tracking restore-tags`: recreate archived tags whose commits exist |
| `cmd_tracking_start` | def | `plugins/semver/bin/semver-cli:1486` | `tracking start`: fresh init or VERSIONING_ARCHIVE.md restore |
| `cmd_tracking_stop_execute` | def | `plugins/semver/bin/semver-cli:1806` | `tracking stop-execute`: archive, delete files/tags, strip CLAUDE.md, commit |
| `cmd_tracking_stop_gather` | def | `plugins/semver/bin/semver-cli:1728` | `tracking stop-gather`: archive-items + tag-deletion questions |
| `cmd_validate` | def | `plugins/semver/bin/semver-cli:865` | `validate`: six sync checks |
| `semver` | skill | `plugins/semver/skills/semver/SKILL.md:2` | Orchestrator: router-only entry, one question at a time, no fabricated changelog |
| `semver-router.sh` | script | `plugins/semver/bin/semver-router.sh:2` | Skill entry point; `/semver` args → subcommands; `bump` → single-call `bump run` |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `_gather_bump_state` | def | `plugins/semver/bin/semver-cli:986` | Bump pre-check core; builds the `questions` array both `gather` and `run` return |
| `Config` | class | `plugins/semver/bin/semver-cli:104` | Line-based `.semver/config.yaml` parser (no YAML lib); first call in every subcommand |
| `run_validation_checks` | def | `plugins/semver/bin/semver-cli:623` | Six-check sync engine behind validate, repair diagnose, and bump gather |
| `FileLock` | class | `plugins/semver/bin/semver-cli:391` | Bump mutex at `/tmp/semver-<md5>.lock`; flock, else mkdir with 300s stale eviction |
| `generate_changelog_entry` | def | `plugins/semver/bin/semver-cli:319` | Groups commits by conventional type; filters `chore(release):`; marks entry source |
| `parse_version` | def | `plugins/semver/bin/semver-cli:268` | Prefix-aware strict `X.Y.Z` regex; gatekeeper for every bump and validation |
| `inject_claude_md` | def | `plugins/semver/bin/semver-cli:462` | Idempotent replace/append of the `<!-- semver:start/end -->` section in CLAUDE.md |

## Relationships

- `plugins-semver-misc.SKILL.md -> plugins-semver-misc.semver-router.sh (calls)`
- `plugins-semver-misc.SKILL.md -> plugins-semver-misc.semver-cli (calls)`
- `plugins-semver-misc.semver-router.sh -> plugins-semver-misc.semver-cli (calls)`
- `plugins-semver-misc.run_user_hooks -> plugins-semver-hooks.run-user-hooks.sh (calls)`
- `plugins-semver-misc.README.md -> plugins-semver-references.user-hooks.md (reads)`

## Type notes

- All output is JSON with `ok` + `display`; exit 0/1/2 (`plugins/semver/bin/semver-cli:82`).
- Answers replay as CLI flags via `flag_mapping` (`plugins/semver/skills/semver/SKILL.md:35`).
- `SEMVER_BUMP_IN_PROGRESS=1` blocks nested bumps (`plugins/semver/bin/semver-cli:1000`).
- Changelog ranges anchor on `last_version_commit`, not tags (`plugins/semver/bin/semver-cli:212`).
- A failed pre-bump user hook aborts the bump (`plugins/semver/bin/semver-cli:1285`).

## External deps

- Python 3 stdlib only — no third-party imports (`plugins/semver/bin/semver-cli:8`)
- git — every version/tag fact is a subprocess call (`plugins/semver/bin/semver-cli:158`)
- bash — runs the user-hook runner (`plugins/semver/bin/semver-cli:795`)

## Gotchas

- Only `cmd_tracking_start` requires git-root cwd (`plugins/semver/bin/semver-cli:1489`).
- `Config.get_bool` is true only for literal `true` (`plugins/semver/bin/semver-cli:137`).
- SKILL.md bans calling semver-cli directly (`plugins/semver/skills/semver/SKILL.md:17`).
- Yet its execute phases do exactly that (`plugins/semver/skills/semver/SKILL.md:65`).
