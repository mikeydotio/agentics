# handle-issue

Turn "I want to work on issue #N" into a running, **plan-mode** Claude session in a **new tmux
window**, launched inside a per-issue git **worktree** (`claude -w <n>`). Pick an issue by number
or interactively from the repo's open issues; the plugin opens a window named `<repo-prefix>-<n>`
(e.g. `age-42`), `cd`s it to the repo root, launches Claude in a worktree **directly in plan mode**
(`--permission-mode plan`), and submits a prompt asking it to plan a fix — all in one command.

It also keeps GitHub in sync: dispatch **marks the issue `in-progress`** (creating the label if the
repo doesn't have it), and the handoff prompt briefs the child session to **comment its finalized
plan** on the issue, **word every PR to close the issue** (`Closes #N`), and **comment a link to
each PR** it pushes.

## When to use

`/handle-issue` is for kicking off work on a GitHub issue in an **isolated context** without the
manual dance of: open a window, make a worktree, launch Claude, switch to plan mode, paste a
prompt. Reach for it when you're triaging a backlog and want to spin up a focused session per
issue.

It is **not** a background agent — it hands off to a fresh interactive Claude that plans a solution
(in plan mode, so nothing is changed until you approve). You review and drive that session yourself.

## Requirements

- **tmux** — Claude must be running inside a tmux session (the plugin opens a sibling window).
  Outside tmux it bails with a clear message.
- **GitHub CLI** — `gh` must be installed and authenticated (`gh auth login`, or a `GH_TOKEN`).
- A git checkout with a GitHub **origin** remote (used to resolve `owner/repo` and to satisfy
  `claude -w`'s requirement that it run from a git-tracked location).

## Usage

```
/handle-issue [issue-number]
```

Examples:

```
/handle-issue 42      # open a plan-mode Claude on issue #42 in a new window + worktree
/handle-issue         # list the repo's open issues and let you pick one
```

With no number, you get a single question listing open issues (newest first). Pick one — or choose
"Other" to type any issue number — and it dispatches.

## How it works

1. **List** (only when no number is given) — `bin/handle-issue.sh list` derives `owner/repo` from
   the origin remote and calls `gh issue list --state open`, returning each issue with a pre-built
   pick option. The skill presents them via one `AskUserQuestion`.
2. **Dispatch** — `bin/handle-issue.sh dispatch <n>` runs a strict, ordered sequence:
   - Hard preconditions first (tmux present, inside a git repo, `gh` authenticated, the issue
     exists and is open) — any failure stops **before** anything is opened.
   - `tmux new-window -c <repo-root> -n <repo-prefix>-<n>` — open the window with a stable name
     (`age-42`-style) and capture its pane id. tmux's `automatic-rename` and program-driven
     `allow-rename` are turned **off** on the window so the name sticks even though Claude sets its
     own terminal title.
   - **Worktree hygiene** — before launching Claude, idempotently ensure `.claude/worktrees/` is
     gitignored (the container dir `claude -w <n>` builds its per-issue worktree under), so the
     ephemeral worktrees never dirty the parent repo's `git status`. It respects a broader existing
     rule (e.g. `.claude/`) and is a no-op when already ignored. Best-effort: a write failure only
     leaves the pre-fix status quo (an untracked worktree dir), never an `ok:false`. Override the
     ignored path with `HANDLE_ISSUE_WORKTREE_IGNORE_PATH`.
   - Launch `claude -w <n> --permission-mode plan` (literal send + Enter) — the `--permission-mode
     plan` flag opens the session **in plan mode deterministically**, with no keystrokes.
   - **Readiness gate** — poll `capture-pane` until Claude's TUI is up (it also has to build the
     worktree first), with a bounded fallback delay, so the prompt keystrokes aren't lost.
   - Type and submit the prompt, confirmed via a `capture-pane` read-back (resend if it never lands).
     The default prompt briefs the child session to comment its finalized plan on the issue, word
     PRs to close it (`Closes #<n>`), and comment each PR link — those steps happen later, inside
     that session, so the prompt is the only place they can be requested.
   - **Mark the issue `in-progress`** — `gh label create` (create-if-missing, existing styling left
     alone) then `gh issue edit --add-label`. Best-effort: a failure adds a `warning`, never an
     `ok:false`. Disable with `HANDLE_ISSUE_LABEL=`.
3. The original pane shows a one-line status. If the handoff or the label couldn't be fully
   confirmed, you get a `warning` telling you to glance at the new window.

Once a side effect has happened (the window exists), the helper reports `ok:true` with a `warning`
rather than a hard failure — so a status line never falsely implies "nothing happened."

## Configuration (environment variables)

All optional; sensible defaults. Useful for customizing the launch/prompt or for testing.

| Variable | Default | Purpose |
|----------|---------|---------|
| `HANDLE_ISSUE_LAUNCH_CMD` | `claude -w <n> --permission-mode plan` | Command typed into the new window. `<n>` → issue number. `--permission-mode plan` is what forces plan mode. |
| `HANDLE_ISSUE_PROMPT` | _(GitHub-reporting prompt)_ | Prompt typed + submitted once Claude is ready. Default asks the child to plan the fix, comment the finalized plan on the issue, word PRs to close it (`Closes #<n>`), and comment each PR link. `<n>` → issue number. Deliberately has no `/plan` prefix. |
| `HANDLE_ISSUE_LABEL` | `in-progress` | Label applied to the issue at dispatch (created in the repo if missing). Set to **empty** (`HANDLE_ISSUE_LABEL=`) to disable labeling entirely. |
| `HANDLE_ISSUE_LABEL_COLOR` | `fbca04` | Hex color (no `#`) used only when the label doesn't yet exist — existing labels keep their styling. |
| `HANDLE_ISSUE_LABEL_DESC` | `Actively being worked on` | Description used only when the label is first created. |
| `HANDLE_ISSUE_WINDOW_NAME` | _(computed)_ | Overrides the window name. Default is `<first-3-alnum-of-repo-lowercased>-<n>` (e.g. `age-42`). `<n>` → issue number. |
| `HANDLE_ISSUE_WORKTREE_IGNORE_PATH` | `.claude/worktrees/` | Path idempotently added to the repo's root `.gitignore` at dispatch so `claude -w`'s per-issue worktrees don't dirty `git status`. No-op if already ignored (respects a broader rule like `.claude/`). |
| `HANDLE_ISSUE_BACKGROUND` | _(unset)_ | Set to `1` to open the window with `-d` (don't switch focus to it). |
| `HANDLE_ISSUE_ALLOW_CLOSED` | _(unset)_ | Set to `1` to dispatch even if the issue is closed. |
| `HANDLE_ISSUE_LIST_LIMIT` | `50` | Max open issues fetched for the picker. |
| `HANDLE_ISSUE_GH_BIN` | `gh` | Path to the `gh` binary (tests inject a fake). |
| `HANDLE_ISSUE_READY_PATTERN` | `for shortcuts` | Regex marking Claude's TUI as ready. TUI text is version-specific — override if it changes. |
| `HANDLE_ISSUE_READY_ATTEMPTS` / `_READY_DELAY` | `40` / `0.25` | Readiness poll bound (≈10s). |
| `HANDLE_ISSUE_READY_FALLBACK_DELAY` | `3` | Extra settle (seconds) if readiness never confirms. |
| `HANDLE_ISSUE_CONFIRM_ATTEMPTS` / `_CONFIRM_DELAY` / `_SEND_RETRIES` | `8` / `0.3` / `2` | Prompt-submission confirm/resend bounds. |
| `HANDLE_ISSUE_DRY_RUN` | _(unset)_ | Set to `1` to run the read-only checks and print the exact tmux commands it *would* run, without opening a window. |

> **Plan mode is forced by the `--permission-mode plan` launch flag, not keystrokes.** `-w` is
> Claude Code's official `--worktree` switch (creates a named per-issue worktree; only valid from a
> git-tracked location), and `--permission-mode plan` opens the session in plan mode with no
> `Shift+Tab` guesswork. That flag sets the *initial* mode only — you can still `Shift+Tab` out of
> plan mode once you've approved the plan. The prompt intentionally does **not** begin with `/plan`:
> that is a slash command that routes to a registered `/plan` skill (e.g. forge's planner), not
> Claude's built-in plan mode.

See `skills/handle-issue/SKILL.md` for the routing logic and `bin/handle-issue.sh` for the full
dispatch sequence.
