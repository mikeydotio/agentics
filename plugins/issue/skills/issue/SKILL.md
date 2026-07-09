---
name: issue
description: GitHub-issue lifecycle toolkit. `/issue do <n>` spins up a fresh plan-mode Claude session for an issue in a new tmux window + per-issue git worktree; `/issue new <desc>` interrogates you then files an issue; `/issue view <n>` prints an issue and stops; `/issue complete <n>` closes it and safely cleans up merged branches + worktrees; `/issue <n>` views it then offers to work on it; bare `/issue` lists open issues to pick from. Use when the user wants to file, view, start work on, or wrap up a GitHub issue. Deterministic work lives in bin/issue.sh; requires an authenticated gh CLI (and tmux for `do`).
argument-hint: "<do <n> | view <n> | new <desc> | complete <n> | <n>>"
---

# Issue — GitHub-issue lifecycle toolkit

You are a **thin router**. All deterministic work (GitHub lookups, tmux lifecycle, git cleanup,
keystroke sequencing) lives in `bin/issue.sh`, which emits **one JSON object** with `ok` +
`display`. **Route and render — never call `git`, `gh`, or `tmux` yourself.** Run the helper with:

```
bash ${CLAUDE_PLUGIN_ROOT}/bin/issue.sh <subcommand> …
```

**Universal rule:** every run returns JSON. If `ok` is `false`, show the `display` string and
**stop**. On `ok:true`, show `display` (plus any `warning`/`pane_tail`).

## Dispatch

Parse `ARGUMENTS` (everything after `/issue`) — the first token is the verb:

| ARGUMENTS | Verb | Action |
|-----------|------|--------|
| `do <n>` | Work on it | **Dispatch** flow below with `<n>`. |
| `view <n>` | Show it | Run `bin/issue.sh view <n>`; print `display`; **stop**. |
| `new <desc>` | File one | **Read `references/new.md`** and follow it: interrogate, draft, confirm, then `bin/issue.sh create …`. |
| `complete <n>` | Wrap it up | **Read `references/complete.md`** and follow it: `complete plan <n>` → one confirmation → `complete execute <n>`. |
| a bare integer, e.g. `55` | View, then offer | **View + Offer** flow below. |
| _(empty)_ | Pick one | **List → Pick** below, then **View + Offer** on the choice. |
| `doctor` | Readiness self-test | Run `bin/issue.sh doctor`; show its `display`. A drift check after a Claude Code upgrade — reports which readiness tier matched. No GitHub side effects. |
| anything else | Malformed | Say one line: "Usage: `/issue <do <n> \| view <n> \| new <desc> \| complete <n> \| <n>>`", then stop. |

## View + Offer (`/issue <n>`)

1. Run `bin/issue.sh view <n>`; show its `display` (`ok:false` → show + stop).
2. Ask **one** `AskUserQuestion` (`header: "Issue #<n>"`): "Work on issue #<n> now?" — options
   **Yes** / **No**.
3. **No** → stop. **Yes** → run the **Dispatch** flow with `<n>`.

## List → Pick (bare `/issue`)

1. Run `bin/issue.sh list`.
   - `ok:false` → show `display`, stop.
   - `count == 0` → show `display` ("No open issues …"), stop. **Do not** open an AskUserQuestion.
2. Ask the user **which issue** with **exactly one** `AskUserQuestion` (one-question-at-a-time is
   mandatory). `AskUserQuestion` allows only **2–4 options**, so tier by `count` (issues arrive
   newest-first):

   | `count` | How to present |
   |---------|----------------|
   | 1 | The single issue's `option`, plus `{label:"Other #", description:"Enter a different issue number"}`. |
   | 2–4 | Every issue's pre-built `option` object, in order. |
   | > 4 | First print the full list as plain text (`#<number> — <title>`, one per line), then AskUserQuestion with the **first 3** issues' `option` objects (the tool auto-adds an "Other" choice). |

   Use `header: "Which issue"` and a question like "Which open issue do you want to work on?".
3. Map the answer to a number: a picked `label` is `#<number>` (prefer matching the chosen option
   to its `issues[]` entry and reading `.number`). For "Other"/free-form, extract the integer;
   reject a non-positive-integer and re-run **List → Pick**.
4. Run the **View + Offer** flow on that number.

## Dispatch (the `do` flow)

1. Run `bash ${CLAUDE_PLUGIN_ROOT}/bin/issue.sh dispatch <number>`.
2. Render:
   - `ok:false` → show `display`, stop. (Common causes: not in tmux, `gh` unauthenticated, not a git
     repo, issue not found, issue closed — the `display` says which.)
   - `ok:true` → show `display`. If a `warning` field is present, surface it too — the tmux window
     opened but the handoff (claude readiness and/or prompt submission) couldn't be fully confirmed,
     so the user should glance at the new window. When a `pane_tail` accompanies the warning, include
     it (fenced) as diagnostic evidence.

On success a new window (`<repo-prefix>-<number>`, e.g. `age-42`) is running
`claude -w <repo-prefix>-<number> --permission-mode plan` in a fresh worktree named the **same** as
the window (`.claude/worktrees/age-42`) — in plan mode, prompt already submitted. The helper also
**marks the issue `in-progress`** on GitHub (best-effort; a failure adds a `warning`, never
`ok:false`). Nothing further is needed from you.

## Notes

- **`do` requires tmux** (the helper hard-fails otherwise); **all verbs need an authenticated
  `gh`** CLI.
- The `do` launch command (`claude -w <name> --permission-mode plan`) and handoff prompt are sent
  verbatim and overridable via `ISSUE_LAUNCH_CMD` / `ISSUE_PROMPT`; the window/worktree name is
  `ISSUE_WINDOW_NAME` (renames both). Plan mode comes from the `--permission-mode plan` flag — **not**
  a `/plan` prompt prefix. The helper owns these; don't rewrite them here.
- **GitHub write-backs live in the helper — never call `gh`/`git` yourself.** `do`'s default prompt
  briefs the child session to comment its finalized plan on the issue, word every PR to close it
  (`Closes #<n>`), and comment each PR link. `complete`'s cleanup (close, worktree/branch removal)
  and `new`'s filing are likewise the helper's job.
- **Worktree hygiene (automatic):** `do` idempotently gitignores `.claude/worktrees/` so the
  per-issue worktrees never dirty `git status` (reported in the `gitignore` field; never affects
  `ok`).
- `ISSUE_DRY_RUN=1` previews `dispatch`, `create`, and `complete execute` without side effects (used
  by the tests); you generally won't need it interactively.
</content>
