---
module: "plugins/semver (misc)"
summary: "Plugin manifest, README, and SKILL.md orchestrator defining /semver's command surface and CLI-routing contract."
read_when: "Changing /semver commands, routing, or plugin manifest identity"
sources:
  - path: plugins/semver/.claude-plugin/plugin.json
    blob: 74e01753fc6b7d4cd4f01ffc02ff628b5cd61fe3
  - path: plugins/semver/README.md
    blob: 22ec64306da43a6a4e9b4b7a4270770508d3a7c0
  - path: plugins/semver/skills/semver/SKILL.md
    blob: 11fab2c938ab5be0798d073f4328428d101c78c0
generator: cartographer/4
baseline: 7387d3614aaae8d5a5bc156cf01c251d22b1dd45
---

# Module: plugins/semver (misc)

## Purpose

This module is the /semver plugin's front door: the plugin manifest declares its identity, the README documents every subcommand and lifecycle detail (tracking, bump, set, init, auto-bump, user hooks, archiving), and SKILL.md is the orchestrator that turns each subcommand into a router/CLI invocation plus AskUserQuestion loops — it computes nothing itself, only relays the CLI's JSON responses (questions, display, prompt hooks) back to the user. The organizing discipline is a strict routing contract: Hard Rules forbid calling semver-cli directly except four documented execute paths, and forbid ever re-triggering /semver bump or /semver set from inside a hook, guarding against infinite recursion. Without this module /semver would have no entry point, no documented command surface, and no protocol for how Claude should relay the CLI's structured responses to the user.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

Hard Rule 1 requires every subcommand to route through semver-router.sh, with exactly four documented exceptions — the second-call execute paths `bump execute`, `tracking stop-execute`, `set execute`, and `init execute` — each invoked directly against semver-cli only after a Question Loop has resolved (plugins/semver/skills/semver/SKILL.md:16). Bump, Set, and Init share a single-round-trip 'happy path' lifecycle: their router `run` call (`bump run`, `set run`, `init run`) gathers state and executes inline when no interaction is needed (`executed: true`), falling back to a second explicit `*_execute` CLI call only when dirty-tree/wrong-branch/tag-conflict questions or a pre-bump prompt hook require user input (plugins/semver/skills/semver/SKILL.md:52-54,73-75,90-97). Init's non-clean path (`executed: false`, prior artifacts detected) branches into four mutually exclusive modes — fresh, enable, adopt, reinit — selected via a single `init_existing` question, where only reinit additionally requires a separately-collected `--version` flag (plugins/semver/skills/semver/SKILL.md:98-104).

## External deps


## Gotchas

SKILL.md repeatedly guards against re-triggering /semver bump or /semver set from within post-bump PROMPT_HOOK.md instructions or mid-flow steps, since doing so causes infinite recursion (plugins/semver/skills/semver/SKILL.md:20,58,63,67); the underlying reentrancy protection scripts must respect is the SEMVER_BUMP_IN_PROGRESS=1 env-var guard (plugins/semver/README.md:74). Separately, the Simple Commands section explicitly forbids extra analysis (e.g. reading git log) for current/validate/recommend/auto-bump stop/tracking start, since those commands are documented as pure passthrough with no Question Loop (plugins/semver/skills/semver/SKILL.md:129-134).
