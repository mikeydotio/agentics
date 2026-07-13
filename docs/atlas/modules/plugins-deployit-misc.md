---
module: "plugins/deployit (misc)"
summary: "Deployit's plugin manifest and orchestrator skill: routes /deployit commands to the CLI and authors release notes."
read_when: "Changing /deployit's command surface or router invocation rules"
sources:
  - path: plugins/deployit/.claude-plugin/plugin.json
    blob: 0f70d363c63cb4146748f11a3a27d1f9d2788895
  - path: plugins/deployit/skills/deployit/SKILL.md
    blob: 61ac326fd6cb8ef2020cec7f05b0a81db14896e4
generator: cartographer/4
baseline: 7387d3614aaae8d5a5bc156cf01c251d22b1dd45
---

# Module: plugins/deployit (misc)

## Purpose

This is deployit's front door: the plugin manifest declares its marketplace identity, and the SKILL.md orchestrator is the single entry point that routes every /deployit subcommand through bin/deployit-router.sh, never calling the CLI directly. Its purpose is to keep judgment that a deterministic CLI can't produce — authoring GitHub release notes from commit/issue history, walking the AskUserQuestion scheme/version-bump loops, deciding which repo layout won — in the LLM layer, while all deterministic work (archiving, signing, index writes, publishing) stays in the CLI it dispatches to. If this module vanished, /deployit would have no discoverable command surface, and the hard rules guarding destructive operations (never push the index repo from here, never call gh/deployit-release directly, require qualified gc/rm flags) would go unenforced at the orchestration layer.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

- Ownership boundary: the orchestrator only routes and authors prose; it must never call deployit-cli directly and never pushes to the index repo itself — both are the CLI's job (plugins/deployit/skills/deployit/SKILL.md:21-23).
- Release ownership split: for macOS, the orchestrator's only job is authoring release notes text passed via --release-notes-file; it must never call gh or bin/deployit-release, or create tags/releases directly — the CLI owns publishing (plugins/deployit/skills/deployit/SKILL.md:33-36).
- Destructive-op invariants: gc requires --keep N or --older-than D, and rm requires --build ID or --product BUNDLE_ID --platform P — neither may run unqualified (plugins/deployit/skills/deployit/SKILL.md:63-68).
- redeploy's lifecycle role: it is the only command that refreshes the daemon's stable symlinks and verifies the live endpoint via tests/verify-live.sh, and must be re-run after every change to plugins/deployit/ since _healthz alone doesn't confirm new code is live (plugins/deployit/skills/deployit/SKILL.md:69-74).
- Deploy sequencing invariant: preflight, bump, and release-context are internal sub-steps of deploy, run in a fixed order and never invoked directly by users (plugins/deployit/skills/deployit/SKILL.md:114-117).

## External deps


## Gotchas

- Hard rule 4 hardcodes a specific host app in an otherwise generic plugin: build-number bumping stays "the host repo's responsibility," naming Lillist's `Tools/Deploy/bump-build-number.sh` Archive pre-action as the mechanism the plugin depends on but doesn't own (plugins/deployit/skills/deployit/SKILL.md:24-26).
- Layout detection is not surfaced to the user: when both Apps-layout and single-app-layout signals are present in a repo, Apps-layout silently wins with no warning (plugins/deployit/skills/deployit/SKILL.md:51).
- `MARKETING_VERSION`/`PRODUCT_BUNDLE_IDENTIFIER` parsing must tolerate both quoted and unquoted forms in project.yml, an explicit compatibility carve-out in the orchestrator's own detection notes (plugins/deployit/skills/deployit/SKILL.md:58-59).
