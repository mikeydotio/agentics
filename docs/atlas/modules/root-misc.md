---
module: "root (misc)"
summary: "Repo wiring layer — marketplace plugin registry, agent instructions, pre-push test gate, artifact conventions"
read_when: "Registering/installing plugins, changing root agent instructions, or wiring make test"
sources:
  - path: .claude-plugin/marketplace.json
    blob: 974cf2ed0e780503f38268b18bdc85848a2105be
  - path: .gitignore
    blob: a9bf4882e230d3761b915e566cecfb49630a25af
  - path: .semver/config.yaml
    blob: 34a5c2bfa206393f2256834b5bd999e9aec3f077
  - path: AGENTS.md
    blob: 04fef50d2517e57a411f7f23a09af90a44b24dba
  - path: CLAUDE.md
    blob: 370157c29cb3943526846444e4b0fa46dbef6e56
  - path: Makefile
    blob: b183c37836c8dbbcc10676db66113d62dad41652
  - path: README.md
    blob: 5f28be43c59b3bb49b0976dc3199d42abfee9fea
  - path: docs/forge-workflow.md
    blob: 829219590927e60d40bc6b2e7d19bbedba22613d
references_modules: [plugins-agents-misc, plugins-atlas-misc, plugins-atlas-tests, plugins-council, plugins-deployit-misc, plugins-deployit-tests-chunk-1, plugins-forge-misc, plugins-freshen, plugins-greenlight, plugins-hook-guard, plugins-rca, plugins-semver-misc, plugins-semver-tests, tests]
generator: cartographer/1
baseline: 545be2bb7ff18f328277446829f1be6457ac6363
verified: true
---

# Module: root (misc)

## Purpose

Declarative wiring — the files that bind independently developed plugins into one marketplace.
marketplace.json is the sole registry; CLAUDE.md and AGENTS.md are the agent instruction surface.
The Makefile is the lone pre-push test gate; .gitignore splits ephemeral from committed artifacts.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `plugins` | JSON array | `.claude-plugin/marketplace.json:8` | Registry of installable plugins; each entry binds a name and description to a `plugins/` source dir |
| `test` | make target | `Makefile:7` | Aggregate gate the global pre-push hook runs; must cover every headless plugin suite (`Makefile:2`) |
| `test-atlas` | make target | `Makefile:24` | Runs `plugins/atlas/tests/run-tests.sh` |
| `test-deployit` | make target | `Makefile:21` | Runs `plugins/deployit/tests/run-tests.sh` |
| `test-root-bats` | make target | `Makefile:11` | Runs `tests/run-tests.sh` when bats-core is installed; otherwise skips with a notice |
| `test-semver` | make target | `Makefile:18` | Runs `plugins/semver/tests/run-tests.sh` |

## Load-bearing internals

None — declarative JSON/YAML/markdown with no internal symbols that clear the ranking bar.

## Relationships

- `root-misc.marketplace.json -> plugins-agents-misc.plugin.json (owns)`
- `root-misc.marketplace.json -> plugins-atlas-misc.plugin.json (owns)`
- `root-misc.marketplace.json -> plugins-council.plugin.json (owns)`
- `root-misc.marketplace.json -> plugins-deployit-misc.plugin.json (owns)`
- `root-misc.marketplace.json -> plugins-forge-misc.plugin.json (owns)`
- `root-misc.marketplace.json -> plugins-freshen.plugin.json (owns)`
- `root-misc.marketplace.json -> plugins-greenlight.plugin.json (owns)`
- `root-misc.marketplace.json -> plugins-hook-guard.plugin.json (owns)`
- `root-misc.marketplace.json -> plugins-rca.plugin.json (owns)`
- `root-misc.marketplace.json -> plugins-semver-misc.plugin.json (owns)`
- `root-misc.test-atlas -> plugins-atlas-tests.run-tests.sh (calls)`
- `root-misc.test-deployit -> plugins-deployit-tests-chunk-1.run-tests.sh (calls)`
- `root-misc.test-root-bats -> tests.run-tests.sh (calls)`
- `root-misc.test-semver -> plugins-semver-tests.run-tests.sh (calls)`

## Type notes

- Adding a plugin requires registering it in marketplace.json (checklist at `CLAUDE.md:41-46`).
- Installs resolve via `/plugin install <name>@agentics` against this manifest (`README.md:8-14`).
- Ephemeral plugin state is gitignored: .freshen/, .rca/, .forge/ runtime files (`.gitignore:13-23`).
- .storyhook/ and .planning/ are version-controlled project data — never ignore them (`.gitignore:10`).
- .forge/config.json, plan-mapping.json, handoffs/, and fix-cycles/ stay committed (`.gitignore:22`).
- .semver/config.yaml carries the semver plugin's settings (auto_bump, git_tagging, target_branch).
- `CLAUDE.md:76` forbids editing .semver/config.yaml unless the user explicitly asks.
- `AGENTS.md:5-27` mandates the storyhook loop for every agent: context, next, done, handoff.

## External deps

- storyhook — `story` CLI and MCP server for task tracking; the workflow is mandated by `AGENTS.md:3`
- bats-core — optional runner for the root bats suite; absence skips it (`Makefile:12-16`)
- tmux — hard requirement for freshen and all hook-based context clearing (`CLAUDE.md:37`)

## Gotchas

- `CLAUDE.md:48-77` is a `<!-- semver:start -->` managed block — change it via /semver, not by hand.
- `docs/forge-workflow.md:145-156` and `CLAUDE.md:31` describe different forge pipelines — verify first.
- `make test` passes even without bats: the root suite skips with a notice (`Makefile:12-16`).
