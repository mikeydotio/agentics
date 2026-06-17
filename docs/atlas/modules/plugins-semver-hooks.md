---
module: plugins/semver/hooks
summary: "Semver's Claude Code hook layer — session version context, git-push bump nudges, pre/post-bump hook runner"
read_when: "Touching semver hooks, push-nudge or session version context, or .semver/hooks execution"
sources:
  - path: plugins/semver/hooks/hooks.json
    blob: 7bf0c55fd5f7a0ae3e75c0f66dde2d75a2a486bd
  - path: plugins/semver/hooks/post-push-check.sh
    blob: 6d65a1c6bc0e854ae91c7984cb2dbc97807d44fb
  - path: plugins/semver/hooks/run-user-hooks.sh
    blob: 6f444669e3df7e9ef28e4afcfad62a2d721305b2
  - path: plugins/semver/hooks/session-start.sh
    blob: 06001ae4a74cdc1564994c65103723d9544a2b58
references_modules: [plugins-forge-skills, plugins-semver-misc]
generator: cartographer/2
baseline: b4cedefaba8df96ee167877bf2ee9c3143ef0b08
verified: true
---

# Module: plugins/semver/hooks

## Purpose

Event-driven edge of the semver plugin. plugins/semver/hooks/hooks.json registers two Claude Code
hooks — session-start.sh injects current-version context at session start, and post-push-check.sh
turns a git push to the release branch into a bump nudge — while run-user-hooks.sh is the
engine the bump flow uses to execute user-supplied .semver/hooks scripts. Everything is
gate-and-exit: without .semver/config.yaml and tracking on, every script is a silent no-op,
keeping the plugin inert in projects that never opted in. The two registered hooks never mutate
state themselves; each emits a single JSON instruction telling the agent what /semver command
to run.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `post-push-check.sh` | PostToolUse hook (Bash matcher) | `plugins/semver/hooks/hooks.json:10` | 10s budget; after a git push to `target_branch`, emits a `systemMessage` directing the agent to run `/semver bump <level>` (nudge, confirm-first, or auto per config); silent no-op otherwise |
| `run-user-hooks.sh` | bash CLI | `plugins/semver/hooks/run-user-hooks.sh:2` | argv `phase bump_type old_version new_version project_dir`; one JSON result object on stdout; exit 0 ok/no hooks, 1 usage error or pre-bump failure, 2 re-entrancy block |
| `session-start.sh` | SessionStart hook (`*` matcher) | `plugins/semver/hooks/hooks.json:22` | 5s budget; emits `additionalContext` "<project> version: <v>" plus `[!DESYNC]`/`[!NO_TAG]` tag warnings pointing at /semver validate; silent unless tracking is on |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `emit_message` | function | `plugins/semver/hooks/post-push-check.sh:108` | Sole output path — jq-encodes all three nudge variants as `{"systemMessage": ...}` |
| `get_config` | function | `plugins/semver/hooks/post-push-check.sh:30` | grep/sed reader of flat `.semver/config.yaml` keys with defaults (tracking=false, auto_bump=false, auto_bump_confirm=true, target_branch=main, version_prefix=v, git_tagging=true); duplicated at `plugins/semver/hooks/session-start.sh:30` — change both together |
| `PROMPT_HOOK.md` | convention | `plugins/semver/hooks/run-user-hooks.sh:57` | Optional per-phase markdown returned JSON-encoded as `prompt_hook` so the agent can follow user instructions around a bump |
| `SEMVER_BUMP_IN_PROGRESS` | env sentinel | `plugins/semver/hooks/run-user-hooks.sh:41` | Re-entrancy guard — nested bump attempts are blocked with exit 2; exported `=1` to every child hook script |

## Relationships

- `plugins-semver-hooks.post-push-check.sh -> plugins-semver-misc.semver-cli (calls)`
- `plugins-semver-hooks.post-push-check.sh -> plugins-forge-skills.state.json (reads)`

## Type notes

- Hooks read stdin JSON and exit 0 on every path (plugins/semver/hooks/post-push-check.sh:12)
- `tracking: true` gates both hooks (plugins/semver/hooks/post-push-check.sh:45)
- Bare `git push` falls back to rev-parse of cwd HEAD (plugins/semver/hooks/post-push-check.sh:65)
- Since-count anchors on VERSION commits, not tags (plugins/semver/hooks/post-push-check.sh:79)
- Failed recommend → <major|minor|patch> placeholder (plugins/semver/hooks/post-push-check.sh:104)
- Nudges pause while forge status is "running" (plugins/semver/hooks/post-push-check.sh:51)
- Desync = verbatim VERSION vs `git describe` compare (plugins/semver/hooks/session-start.sh:57)
- User hook scripts live in .semver/hooks/<phase>/ (plugins/semver/hooks/run-user-hooks.sh:48)
- Only executable `*.sh` files run (plugins/semver/hooks/run-user-hooks.sh:71)
- Run order is C-collation sorted (plugins/semver/hooks/run-user-hooks.sh:66)
- Child hooks get BUMP_TYPE, OLD_VERSION, NEW_VERSION (plugins/semver/hooks/run-user-hooks.sh:104)
- pre-bump fail aborts (exit 1); post-bump fails warn (plugins/semver/hooks/run-user-hooks.sh:117)

## External deps

- jq — parses hook-event JSON and builds every JSON reply in all three scripts
- git — branch resolution, commits-since counting, and tag queries in both registered hooks
- python3 — runs the semver-cli recommend call (plugins/semver/hooks/post-push-check.sh:93)

## Gotchas

- plugins/semver/hooks/session-start.sh:7 says `systemMessage`; line 69 emits `additionalContext`
- Failed pushes still nudge: command text is matched (plugins/semver/hooks/post-push-check.sh:23)
- `version_prefix`/`git_tagging` read but unused here (plugins/semver/hooks/post-push-check.sh:41)
- Starts without `-e`; plugins/semver/hooks/run-user-hooks.sh:109 enables errexit mid-run
