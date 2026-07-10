---
module: "root (misc)"
summary: "Root-level scaffolding: marketplace registry, semver version-sync hook, storyhook workflow, and the Makefile test gate."
read_when: "Registering/installing plugins, changing root agent instructions, or wiring make test"
sources:
  - path: .claude-plugin/marketplace.json
    blob: f36f8676b7fe7d6db4e8d6cec733a62acdc06841
  - path: .semver/config.yaml
    blob: 34a5c2bfa206393f2256834b5bd999e9aec3f077
  - path: .semver/hooks/post-bump/01-sync-plugin-versions.sh
    blob: 29c1f99416d5f42410c2da7ea59165ed979b2c80
  - path: AGENTS.md
    blob: 04fef50d2517e57a411f7f23a09af90a44b24dba
  - path: HANDOFF.md
    blob: 907df53e9f7c3f6e449693c13adab0e710396e13
  - path: Makefile
    blob: 926cb27a1499a300ddf88a0975e754ec445c37f6
  - path: README.md
    blob: 5f28be43c59b3bb49b0976dc3199d42abfee9fea
  - path: docs/forge-workflow.md
    blob: 829219590927e60d40bc6b2e7d19bbedba22613d
generator: cartographer/4
baseline: a4486d2b70ad4124762f9d777af6a7dc007bdc6c
---

# Module: root (misc)

## Purpose

root-misc is the repo's top-level wiring layer: .claude-plugin/marketplace.json is the sole registry binding independently developed plugins into one installable marketplace, while .semver/config.yaml plus its post-bump sync hook keep every plugin manifest's version field in lockstep with the single repo VERSION. AGENTS.md mandates the storyhook task-tracking workflow every agent must follow, the Makefile is the sole pre-push test-aggregation gate, and HANDOFF.md/docs/forge-workflow.md carry cross-cutting project status and the forge autonomous-pipeline narrative. If these files vanished, plugins would stop being discoverable/installable, manifest versions would drift silently apart, and there would be no single test gate or shared task-tracking discipline tying the plugins together.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

- .claude-plugin/marketplace.json:3-4 — the top-level `version` field is the marketplace-wide source of truth; every plugin.json's `version` is derived one-way from it and never read back (.semver/hooks/post-bump/01-sync-plugin-versions.sh:12-14).
- .semver/hooks/post-bump/01-sync-plugin-versions.sh:13-24,103 — runs in two auto-detected modes (bump vs standalone) keyed off the `SEMVER_BUMP_IN_PROGRESS`/`NEW_VERSION` env vars; only bump mode touches git history.
- Makefile:7 — the `test` target aggregates every plugin's suite; several targets (e.g. Makefile:11-16) gate on `command -v bats` before running.
- AGENTS.md:45-47 — `.storyhook/` is deliberately excluded from .gitignore; it is committed, version-controlled project state, not ephemeral output.
- .semver/config.yaml:1-7 — declares this repo's semver plugin settings (auto_bump, git_tagging, target_branch: main), consumed by the semver plugin rather than enforced here.
- README.md:19-21 — spells out the contract for adding a new plugin: a `plugins/<name>/.claude-plugin/plugin.json` manifest, `skills/`/`commands/` directories, and a marketplace.json entry.

## External deps


## Gotchas

- .semver/hooks/post-bump/01-sync-plugin-versions.sh:107-115 (safety rationale at 18-20) — in bump mode the hook amends the just-created release commit and force-moves its tag (`git tag -f`); safe only because that tag was created seconds earlier in the same run and has not yet been pushed.
- Makefile:12-16, and the same pattern repeated at 41-45, 51-55, 61-65, 72-76 — every bats-based suite silently degrades to a printed skip notice when bats-core isn't installed, so a green `make test` doesn't guarantee those suites actually ran.
- AGENTS.md:45-47 — explicitly instructs NOT to gitignore `.storyhook/`; a deliberate exception to typical ephemeral-state-directory hygiene that's easy to violate out of habit.
