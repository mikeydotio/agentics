---
name: handle-issue
description: Address a GitHub issue by spinning up a fresh, plan-mode Claude session in a new tmux window and per-issue git worktree. Pass an issue number to target it directly, or omit the number to pick from the repo's open issues. Use when the user says "handle issue N", "work on issue N", "let's tackle #N", or wants to start on a GitHub issue in an isolated context. Requires tmux and an authenticated gh CLI.
argument-hint: "[issue-number]"
---

# Handle Issue

Turn "I want to work on issue #N" into a running, **plan-mode** Claude session in a **new tmux
window**, launched inside a per-issue git worktree (`claude -w <n>`). You are a thin router: the
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
`claude -w <number> --permission-mode plan` in a fresh worktree — in plan mode, with the prompt
already submitted. Nothing further is needed from you.

## Notes

- **Requires tmux** (the helper hard-fails with a clear `display` otherwise) and an **authenticated
  `gh`** CLI.
- The launch command (`claude -w <n> --permission-mode plan`) and the prompt are sent verbatim and
  overridable via `HANDLE_ISSUE_LAUNCH_CMD` / `HANDLE_ISSUE_PROMPT`; the window name is
  `HANDLE_ISSUE_WINDOW_NAME` (see the README for all env knobs). Plan mode comes from the
  `--permission-mode plan` flag — **not** a `/plan` prompt prefix (that would route to a `/plan`
  skill like forge's planner). Don't rewrite these here — the helper owns them.
- To preview what a dispatch *would* do without opening a window, the helper supports
  `HANDLE_ISSUE_DRY_RUN=1` (used by the tests); you generally won't need it interactively.
