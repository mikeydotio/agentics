---
module: plugins/semver/hooks
summary: "Bash hooks that surface version status at session start and nudge/auto-bump after a push."
read_when: "Touching push-nudge/auto-bump hooks or the session-start version banner"
sources:
  - path: plugins/semver/hooks/hooks.json
    blob: 7bf0c55fd5f7a0ae3e75c0f66dde2d75a2a486bd
  - path: plugins/semver/hooks/post-push-check.sh
    blob: 6d65a1c6bc0e854ae91c7984cb2dbc97807d44fb
  - path: plugins/semver/hooks/run-user-hooks.sh
    blob: 6f444669e3df7e9ef28e4afcfad62a2d721305b2
  - path: plugins/semver/hooks/session-start.sh
    blob: 06001ae4a74cdc1564994c65103723d9544a2b58
generator: cartographer/4
baseline: 50c998d53e2ed58951ac5f794afd32bfa729f658
---

# Module: plugins/semver/hooks

## Purpose

Wires two Claude Code hook events into the semver plugin's config-driven awareness: SessionStart injects a one-line version banner (with a tag/VERSION desync warning) so every session opens version-aware, and the PostToolUse(Bash) hook watches for `git push` to the tracked branch and nudges or auto-triggers `/semver bump`, using a deterministic conventional-commit recommendation from semver-cli and deferring silently when a forge run is in progress. run-user-hooks.sh is a separate execution engine, invoked by the semver CLI's bump command itself (not by these two Claude Code hooks) to run project-defined pre-bump/post-bump scripts under a re-entrancy guard. If this module vanished, the session version banner and push-triggered bump nudges would disappear silently, along with the ability to run user-defined bump hooks.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

- Both `post-push-check.sh` and `session-start.sh` independently reimplement the same flat `key: value` YAML reader via a local `get_config()` (grep+sed) rather than sharing one — plugins/semver/hooks/post-push-check.sh:30-35, plugins/semver/hooks/session-start.sh:30-35; a nested or list-valued config entry silently falls back to the hardcoded default.
- `post-push-check.sh` anchors its "commits since last change" message on the last commit that touched `VERSION`, not on the latest git tag, by design — plugins/semver/hooks/post-push-check.sh:79-87.
- `post-push-check.sh` reads `.forge/state.json` and no-ops entirely when `status` is `"running"`, so during an active forge pipeline run all push-bump nudging is deferred to forge's own commit flow — plugins/semver/hooks/post-push-check.sh:48-52.
- `run-user-hooks.sh` guards against a bump re-entering itself via the `SEMVER_BUMP_IN_PROGRESS` env var, exported only for the duration of each user script it runs — plugins/semver/hooks/run-user-hooks.sh:41-44,103.

## External deps


## Gotchas

- session-start.sh must drain stdin even when `CLAUDE_PROJECT_DIR` is already set and unused, specifically "to avoid broken pipe" against Claude Code's hook invocation — plugins/semver/hooks/session-start.sh:19-20.
- run-user-hooks.sh treats pre-bump and post-bump hook failures asymmetrically: a failing pre-bump script aborts the whole run (exit 1), but a failing post-bump script only appends a warning and the run still reports `status: "ok"` — plugins/semver/hooks/run-user-hooks.sh:12-13,116-132,167-179.
- run-user-hooks.sh re-sorts its already-glob-ordered script list under `LC_COLLATE=C` "to be explicit," per its own comment, rather than trusting the glob's collation alone — plugins/semver/hooks/run-user-hooks.sh:75-76.
