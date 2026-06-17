---
module: "root (misc)"
summary: "Repo wiring layer — marketplace plugin registry, agent instructions, pre-push test gate, artifact conventions"
read_when: "Registering/installing plugins, changing root agent instructions, or wiring make test"
sources:
  - path: .claude-plugin/marketplace.json
  - path: .gitignore
  - path: .semver/config.yaml
  - path: AGENTS.md
  - path: CLAUDE.md
  - path: Makefile
  - path: README.md
  - path: docs/forge-workflow.md
references_modules: [plugins-agents-misc, plugins-atlas-chunk-1, plugins-atlas-tests-chunk-1, plugins-council, plugins-deployit-misc, plugins-deployit-tests-chunk-1, plugins-forge-misc, plugins-freshen, plugins-greenlight, plugins-hook-guard, plugins-rca, plugins-semver-misc, plugins-semver-tests, tests]
generator: cartographer/2
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
- `root-misc.marketplace.json -> plugins-atlas-chunk-1.plugin.json (owns)`
- `root-misc.marketplace.json -> plugins-council.plugin.json (owns)`
- `root-misc.marketplace.json -> plugins-deployit-misc.plugin.json (owns)`
- `root-misc.marketplace.json -> plugins-forge-misc.plugin.json (owns)`
- `root-misc.marketplace.json -> plugins-freshen.plugin.json (owns)`
- `root-misc.marketplace.json -> plugins-greenlight.plugin.json (owns)`
- `root-misc.marketplace.json -> plugins-hook-guard.plugin.json (owns)`
- `root-misc.marketplace.json -> plugins-rca.plugin.json (owns)`
- `root-misc.marketplace.json -> plugins-semver-misc.plugin.json (owns)`
- `root-misc.test-atlas -> plugins-atlas-tests-chunk-1.run-tests.sh (calls)`
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
