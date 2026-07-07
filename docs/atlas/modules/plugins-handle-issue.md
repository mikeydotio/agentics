---
module: plugins/handle-issue
summary: "Dispatches a GitHub issue to a new tmux window, git worktree, and plan-mode Claude session via a bash CLI."
read_when: "Changing handle-issue's dispatch, tmux sequencing, or issue picking"
sources:
  - path: plugins/handle-issue/.claude-plugin/plugin.json
    blob: effb6e00b20f2b9413a7a7f70c53a901220e156a
  - path: plugins/handle-issue/README.md
    blob: 78f9a4ba7ef99ba1e932c9044d2f13a4c861be46
  - path: plugins/handle-issue/bin/handle-issue.sh
    blob: 9e739101988751a2a42ef2508b0125ccbde7ae2d
  - path: plugins/handle-issue/skills/handle-issue/SKILL.md
    blob: aa868eed12b2910a432667dd9fcdf0511909da13
  - path: plugins/handle-issue/tests/fakes/gh
    blob: e46b26b4d6b459f785f8ba49245e7b319192f59f
  - path: plugins/handle-issue/tests/fakes/tmux
    blob: 8886849d8b4a975499e4689f48dbe3bc08799ccc
  - path: plugins/handle-issue/tests/lib.sh
    blob: 9fb1050377b32f46eb31b1a35d08747321712f6c
  - path: plugins/handle-issue/tests/run-tests.sh
    blob: 221d6216190bad707c257d7bfe75b4147ef2c226
  - path: plugins/handle-issue/tests/test-arg-validation.sh
    blob: 3485d11f170adab9113b98cbb6e8033940fb0b1e
  - path: plugins/handle-issue/tests/test-dispatch-dryrun.sh
    blob: 37c9a8558929a01c0737b287d1c8158adb967e7c
  - path: plugins/handle-issue/tests/test-gitignore.sh
    blob: 9db415f96f48a32ddcbc9813445ac6bbb61d532b
  - path: plugins/handle-issue/tests/test-list-shaping.sh
    blob: 6d544dd4a10a7fc64543767287cfc966d398b5c9
  - path: plugins/handle-issue/tests/test-owner-repo.sh
    blob: 0badffd1d9e8bed05f6a865910a503466446f935
  - path: plugins/handle-issue/tests/test-preconditions.sh
    blob: 856ec062f3eaf1efc456cb265225f90bb4d637ee
generator: cartographer/4
baseline: cb09ceb006e3fb4759a91d64d9e6655e67d04bf7
---

# Module: plugins/handle-issue

## Purpose

handle-issue turns "work on issue #N" into a fully isolated Claude session: it opens a new tmux window, launches `claude -w <n>` to build a per-issue git worktree, gates on the TUI becoming ready, flips to plan mode via two Shift+Tabs, and types + submits a prompt asking Claude to plan a fix — all in one command the calling session never has to drive by hand. The idea holding it together is a strict ok/warning boundary: every hard precondition (tmux, git repo, authenticated gh, issue exists and is open) must pass before any side effect, but once the tmux window is opened, further confirmation failures degrade to a warning rather than a false `ok:false`, because a status line must never imply nothing happened when it did. Without this module, spinning up an isolated per-issue Claude session would mean manually repeating the same window/worktree/plan-mode/prompt sequence by hand every time.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

All configuration is environment-variable driven with defaults in bin/handle-issue.sh's config block (plugins/handle-issue/bin/handle-issue.sh:34-54) — unlike most plugins in this repo, there is no persisted state file or artifact directory; each `dispatch` run is stateless. `cmd_dispatch` enforces a hard-fail/soft-warning lifecycle boundary: precondition checks (steps 1-4) exit `ok:false` before any tmux side effect, but once `tmux new-window` succeeds (step 5, plugins/handle-issue/bin/handle-issue.sh:231-238) every later confirmation failure degrades to `{ok:true, warning}` instead of `ok:false` (plugins/handle-issue/bin/handle-issue.sh:19-23,265-278). `render_template` does plain `<n>` string substitution (plugins/handle-issue/bin/handle-issue.sh:65-68), and both the launch command and the prompt are sent through `tmux send-keys -l` (literal mode) so no character in them is ever key-interpreted (plugins/handle-issue/bin/handle-issue.sh:127-128,242).

## External deps


## Gotchas

The tmux send/confirm logic is deliberately duplicated from plugins/freshen/lib/pane-confirm.sh rather than sourced, since handle-issue must keep working when freshen isn't installed (plugins/handle-issue/bin/handle-issue.sh:29-31) — a fix to one send/confirm bug needs mirroring in the other. The plan-mode readiness gate depends on a version-specific TUI marker (`HANDLE_ISSUE_READY_PATTERN` default "for shortcuts"); if Claude's UI text changes and it stops matching, `wait_ready` doesn't fail — it silently falls through to a fixed settle delay and proceeds best-effort (plugins/handle-issue/bin/handle-issue.sh:40-46,104-120). Tests deliberately create throwaway repos under `/tmp` rather than `$TMPDIR`, because macOS Spotlight indexes the latter and can stall file-heavy git operations (plugins/handle-issue/tests/lib.sh:5-6,27-28).
