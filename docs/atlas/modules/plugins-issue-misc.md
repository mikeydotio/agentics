---
module: "plugins/issue (misc)"
summary: "GitHub-issue lifecycle toolkit: skill routes verbs to issue.sh, which owns all git/gh/tmux work and emits JSON."
read_when: "Touching issue dispatch, complete cleanup, or new-issue filing flows"
sources:
  - path: plugins/issue/.claude-plugin/plugin.json
    blob: 9654c1b6d364bceade1f180af54a305a8c7912e4
  - path: plugins/issue/README.md
    blob: 70adbf01c15105d88704acf31c179329c778182f
  - path: plugins/issue/bin/issue.sh
    blob: 26ef55654364027cfed37fa0f9a9f7e02a394b99
  - path: plugins/issue/references/complete.md
    blob: e78243246be2041358cce327b932e1721898284c
  - path: plugins/issue/references/new.md
    blob: c2bc904a4f678b127beb57457f95b1ef5ab1db81
  - path: plugins/issue/skills/issue/SKILL.md
    blob: 0f52d2aedff41f4a526332f5ab5a3688dab67802
generator: cartographer/4
baseline: 7387d3614aaae8d5a5bc156cf01c251d22b1dd45
---

# Module: plugins/issue (misc)

## Purpose

The issue plugin is a GitHub-issue lifecycle toolkit: a thin skill router dispatches list/view/new/do/complete/doctor verbs to a single deterministic bash helper (bin/issue.sh) that owns every git/gh/tmux side effect and returns one JSON object with `ok`+`display` (plugins/issue/skills/issue/SKILL.md:9-11). Its most delicate concern is the `dispatch` handoff: launching a plan-mode Claude session in a new tmux window plus a per-issue worktree needs a two-tiered readiness gate — a footer-marker fast path and a structural frame+glyph stabilization fallback — so a future Claude Code TUI copy change can't silently break the handoff (plugins/issue/bin/issue.sh:82-103). `complete`'s two-phase plan/execute split and hard git-native backstops (never touch unmerged/dirty/locked/current/protected refs) exist so a scan bug can never destroy work (plugins/issue/bin/issue.sh:927-934).

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `flush` | function | `plugins/issue/bin/issue.sh:280` | Flushes the pending worktree record (path, branch-or-'-', locked flag) once per porcelain block and at EOF; never emits when p is empty. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

Every issue.sh subcommand owns its own git/gh/tmux side effects and emits exactly one JSON object with ok+display; the skill never calls git/gh/tmux itself (plugins/issue/bin/issue.sh:4-6, plugins/issue/skills/issue/SKILL.md:9-11). Dispatch's ok-vs-warning boundary is a hard lifecycle line: steps 0-4 are preconditions that fail before any side effect, but from step 5 (the first `tmux new-window`) onward a failure degrades to ok:true+warning because the window already exists (plugins/issue/bin/issue.sh:23-27). resolve_wname() is the single naming authority shared by dispatch (which creates the window/worktree) and complete (which looks the same name up to clean it), so the two subcommands must stay in lock-step (plugins/issue/bin/issue.sh:172-183). collect_targets() is read-only and shared verbatim by complete plan (preview) and complete execute (deletion), so both phases always act on identical scanned data (plugins/issue/bin/issue.sh:225-237). WAIT_READY_TIER is a global set as a side-channel by wait_ready() so both dispatch and doctor can read which readiness tier matched (plugins/issue/bin/issue.sh:360-366). Deletion invariants are enforced with git-native backstops, not just script logic: `git worktree remove` (no --force) and `git branch -d` both refuse dirty/current/unmerged targets even if collect_targets' classification has a bug (plugins/issue/bin/issue.sh:1051,1065).

## External deps


## Gotchas

The top-of-file doc comment claims 'Two subcommands' (list, dispatch) but the router now dispatches six — list, dispatch, view, create, complete, doctor — the header is stale, don't treat it as the full subcommand list (plugins/issue/bin/issue.sh:4, plugins/issue/bin/issue.sh:1144-1152). LABEL is set with `${ISSUE_LABEL-in-progress}` (`-` not `:-`), so an explicit `ISSUE_LABEL=""` disables labeling entirely while only an *unset* var falls back to "in-progress" — an easy bash pitfall to get backwards (plugins/issue/bin/issue.sh:59-61). READY_PATTERN is deliberately kept free of ERE metacharacters (`+`, `(`, `)`) because they would silently mismatch literal footer text like "shift+tab" (plugins/issue/bin/issue.sh:87-89). `doctor` is deliberately excluded from `make test` (it needs a live `claude` binary and the pre-push gate must stay deterministic/offline) — run it by hand after a Claude Code upgrade (plugins/issue/bin/issue.sh:851-853, plugins/issue/README.md:97-98).
