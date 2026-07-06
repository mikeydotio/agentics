---
name: handle-issue
description: Address a GitHub issue by spinning up a fresh, plan-mode Claude session in a new tmux window and per-issue git worktree. Marks the issue in-progress on GitHub at dispatch and hands the child session a prompt that reports its plan and PRs back to the issue. Pass an issue number to target it directly, or omit the number to pick from the repo's open issues. Use when the user says "handle issue N", "work on issue N", "let's tackle #N", or wants to start on a GitHub issue in an isolated context. Requires tmux and an authenticated gh CLI.
argument-hint: "[issue-number]"
---

# Handle Issue

Turn "I want to work on issue #N" into a running, **plan-mode** Claude session in a **new tmux
window**, launched inside a per-issue git worktree named like the window (`claude -w <repo-prefix>-<n>`,
e.g. `age-42`). You are a thin router: the
deterministic work (GitHub lookups, tmux window lifecycle, keystroke sequencing, capture-pane
confirmation) lives in `bin/handle-issue.sh`, which emits one JSON object with `ok` + `display`.
**Your job is to route and render — never call `tmux` or `gh` yourself.**

Run the helper with:

```
bash ${CLAUDE_PLUGIN_ROOT}/bin/handle-issue.sh <subcommand>
```

Every run returns JSON. **If `ok` is `false`, show the `display` string to the user and stop.**

## Command Router

Parse `ARGUMENTS` (everything after `/handle-issue`) and dispatch:

| ARGUMENTS | Meaning | Action |
|-----------|---------|--------|
| _(empty)_ | No issue chosen yet | Run **List → Pick** below, then **Dispatch**. |
| a bare integer, e.g. `42` | Target issue #42 | Go straight to **Dispatch** with `42`. |
| anything else | Malformed | Say one line: "Usage: `/handle-issue [issue-number]`", then fall back to **List → Pick**. |

## List → Pick (no number given)

1. Run `bash ${CLAUDE_PLUGIN_ROOT}/bin/handle-issue.sh list`.
2. Parse the JSON.
   - `ok:false` → show `display`, stop.
   - `count == 0` → show `display` ("No open issues …"), stop. **Do not** open an AskUserQuestion.
3. Otherwise ask the user **which issue** using **exactly one** `AskUserQuestion` call
   (one-question-at-a-time is mandatory). `AskUserQuestion` allows only **2–4 options**, so tier by
   `count` (the helper returns issues newest-first):

   | `count` | How to present |
   |---------|----------------|
   | 1 | Options: the single issue's `option`, plus a second option `{label:"Other #", description:"Enter a different issue number"}`. |
   | 2–4 | Options: every issue's pre-built `option` object, in order. |
   | > 4 | First print the full open-issue list as plain text (`#<number> — <title>`, one per line) so the user can see them all. Then AskUserQuestion with the **first 3** issues' `option` objects. The tool auto-adds an "Other" choice for typing any other number. |

   Use `header: "Which issue"` and a question like "Which open issue do you want to work on?".
4. Map the answer back to an issue number:
   - A picked option's `label` is `#<number>` → strip the `#` to get the number. (Prefer matching the
     chosen option to its `issues[]` entry and reading `.number`, so it stays correct even if the
     label format changes.)
   - If the user chose "Other" / free-form, extract the integer they typed. If it isn't a positive
     integer, tell them and re-run **List → Pick**.
5. Proceed to **Dispatch** with that number.

## Dispatch (issue number in hand)

1. Run `bash ${CLAUDE_PLUGIN_ROOT}/bin/handle-issue.sh dispatch <number>`.
2. Render the result:
   - `ok:false` → show `display`, stop. (Common causes: not in tmux, `gh` unauthenticated, not a git
     repo, issue not found, issue closed — the `display` says which.)
   - `ok:true` → show `display`. If a `warning` field is present, surface it too — the tmux window
     was opened but the handoff (claude readiness and/or prompt submission) couldn't be fully
     confirmed, so the user should glance at the new window.

On success the new window (named `<repo-prefix>-<number>`, e.g. `age-42`) is now running
`claude -w <repo-prefix>-<number> --permission-mode plan` in a fresh worktree named the **same** as
the window (`.claude/worktrees/age-42`) — in plan mode, with the prompt already submitted. The helper
also **marks the issue `in-progress`** on GitHub (creating the label in the repo if it's missing) —
this is best-effort, so if it can't, dispatch still succeeds with a `warning` rather than `ok:false`.
Nothing further is needed from you.

## Notes

- **Requires tmux** (the helper hard-fails with a clear `display` otherwise) and an **authenticated
  `gh`** CLI.
- The launch command (`claude -w <name> --permission-mode plan`, where `<name>` resolves to the
  `<repo-prefix>-<n>` window name so the worktree matches the window) and the prompt are sent
  verbatim and overridable via `HANDLE_ISSUE_LAUNCH_CMD` / `HANDLE_ISSUE_PROMPT`; the window/worktree
  name is `HANDLE_ISSUE_WINDOW_NAME` — overriding it renames both (see the README for all env knobs).
  `<n>` (the issue number) is still available in the launch template. Plan mode comes from the
  `--permission-mode plan` flag — **not** a `/plan` prompt prefix (that would route to a `/plan`
  skill like forge's planner). Don't rewrite these here — the helper owns them.
- **GitHub write-backs (all in the helper — never call `gh` yourself):** the default prompt tells
  the child session to comment its finalized plan on the issue, word every PR to close the issue
  (`Closes #<n>` in the body), and comment a link to each PR it pushes. Requirement #2–#4 of the
  child's contract live in the prompt because they happen later, inside that session, after the
  helper has already returned. The `in-progress` label is configurable via `HANDLE_ISSUE_LABEL`
  (set it to empty to disable labeling); `HANDLE_ISSUE_LABEL_COLOR` / `HANDLE_ISSUE_LABEL_DESC`
  style it on first creation.
- **Worktree hygiene (automatic):** dispatch idempotently gitignores `.claude/worktrees/` — the
  container dir `claude -w <n>` builds each per-issue worktree under — so the ephemeral worktrees
  never dirty the parent repo's `git status`. Best-effort and reported in the `gitignore` result
  field (`added` / `already-ignored` / `add-failed`); it never affects `ok`. The helper owns this —
  don't add gitignore rules yourself.
- To preview what a dispatch *would* do without opening a window, the helper supports
  `HANDLE_ISSUE_DRY_RUN=1` (used by the tests); you generally won't need it interactively.
