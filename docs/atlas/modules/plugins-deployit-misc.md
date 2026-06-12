---
module: "plugins/deployit (misc)"
summary: "Plugin manifest plus the /deployit orchestrator skill that routes every command through the bin router"
read_when: "Changing /deployit command surface, deploy/semver protocol, or router invocation rules"
sources:
  - path: plugins/deployit/.claude-plugin/plugin.json
    blob: 3a91c808b94584bbdad0de0e9a980992708382d5
  - path: plugins/deployit/skills/deployit/SKILL.md
    blob: b59f2fd2e6557a951f56b986c7efd54ab3a77a29
references_modules: [plugins-deployit-bin, plugins-deployit-references, plugins-deployit-tests-chunk-2]
generator: cartographer/1
baseline: b1e1f9d1dbced518c625c38bb87814de5af1a1b7
verified: true
---

# Module: plugins/deployit (misc)

## Purpose

User-facing entry of the deployit plugin: `plugin.json` registers it in the marketplace, and the
`/deployit` skill turns bootstrap/deploy/list/url/status/gc/redeploy into `deployit-router.sh`
calls whose JSON verdicts it renders. The design idea is zero deploy logic in this layer; the
skill only enforces protocol (router-only access, halt on `ok: false`, semver preflight before
deploy, question replay via AskUserQuestion) and defers mechanics to the bin layer and platform
detail to the references docs.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `deployit` | plugin manifest | `plugins/deployit/.claude-plugin/plugin.json:2` | Marketplace-facing name; description advertises tailnet OTA deploys with semver awareness |
| `deployit` | skill | `plugins/deployit/skills/deployit/SKILL.md:2` | `/deployit <cmd>` entry; every subcommand goes through the router and halts on `ok: false` |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `Hard rules` | protocol section | `plugins/deployit/skills/deployit/SKILL.md:17` | Routing, no-index-push, and version-ownership invariants binding every command |
| `Question loop` | protocol section | `plugins/deployit/skills/deployit/SKILL.md:92` | Maps CLI `questions` through `flag_mapping`/`command_mapping`, then re-runs the router |
| `Semver-aware deploy` | protocol section | `plugins/deployit/skills/deployit/SKILL.md:65` | Orders preflight, optional bump, then deploy so builds stay version-correct |

## Relationships

- `plugins-deployit-misc.deployit -> plugins-deployit-bin.deployit-router.sh (calls)`
- `plugins-deployit-misc.deployit -> plugins-deployit-tests-chunk-2.verify-live.sh (calls)`
- `plugins-deployit-misc.deployit -> plugins-deployit-references.bootstrap.md (reads)`
- `plugins-deployit-misc.deployit -> plugins-deployit-references.ios.md (reads)`
- `plugins-deployit-misc.deployit -> plugins-deployit-references.macos.md (reads)`
- `plugins-deployit-misc.deployit -> plugins-deployit-references.semver.md (reads)`
- `plugins-deployit-misc.deployit -> plugins-deployit-references.tailscale-serve.md (reads)`
- `plugins-deployit-misc.deployit -> plugins-deployit-references.troubleshooting.md (reads)`
- `plugins-deployit-misc.deployit -> plugins-deployit-references.visionos.md (reads)`

## Type notes

- Show router `display` and stop when `ok` is false (plugins/deployit/skills/deployit/SKILL.md:20)
- Only the CLI pushes to the index repo (plugins/deployit/skills/deployit/SKILL.md:21)
- `preflight`/`bump` are internal to `deploy` only (plugins/deployit/skills/deployit/SKILL.md:88)
- A failed `bump` halts deploy; no stale versions (plugins/deployit/skills/deployit/SKILL.md:84)
- Builds archive from the fresh release commit (plugins/deployit/skills/deployit/SKILL.md:89)
- Semver gate: host `tracking: true` + `VERSION` file (plugins/deployit/skills/deployit/SKILL.md:27)
- Semver display never edits `MARKETING_VERSION` (plugins/deployit/skills/deployit/SKILL.md:29)
- `CFBundleVersion` bumping is the host repo's job (plugins/deployit/skills/deployit/SKILL.md:22-24)
- Apps-layout beats single-app when both match (plugins/deployit/skills/deployit/SKILL.md:45)

## External deps

- Xcode — archive/export of signed builds (performed by the CLI layer, not the skill)
- Tailscale Serve — serves staged builds; every deploy ends at a tailnet URL
- launchd — daemon plist rewrite + kickstart during bootstrap and redeploy
- GitHub repo `mikeydotio/deployit-index` — shared cross-machine deploy listing
- AskUserQuestion (Claude Code tool) — one question per call for bump and scheme picks

## Gotchas

- `gc` requires `--keep N` or `--older-than D` (plugins/deployit/skills/deployit/SKILL.md:57)
- Layout-detect failure usually means wrong cwd (plugins/deployit/skills/deployit/SKILL.md:54)
- Re-run `bootstrap` after plugin version changes (plugins/deployit/skills/deployit/SKILL.md:41)
- Run `redeploy` after every change to this plugin (plugins/deployit/skills/deployit/SKILL.md:62)
- `_healthz` alone doesn't prove new code is live (plugins/deployit/skills/deployit/SKILL.md:63)
