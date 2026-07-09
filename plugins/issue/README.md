# issue

Turn "I want to work on issue #N" into a running, **plan-mode** Claude session in a **new tmux
window**, launched inside a per-issue git **worktree named the same as the window** (`claude -w
<repo-prefix>-<n>`). Pick an issue by number or interactively from the repo's open issues; the
plugin opens a window named `<repo-prefix>-<n>` (e.g. `age-42`) **without stealing your focus**,
`cd`s it to the repo root, launches Claude in a worktree of the same name
(`.claude/worktrees/age-42`) **directly in plan mode** (`--permission-mode plan`), and submits a
prompt asking it to plan a fix — all in one command.

It also keeps GitHub in sync: dispatch **marks the issue `in-progress`** (creating the label if the
repo doesn't have it), and the handoff prompt briefs the child session to **comment its finalized
plan** on the issue, **word every PR to close the issue** (`Closes #N`), and **comment a link to
each PR** it pushes.

## When to use

`/issue` is for kicking off work on a GitHub issue in an **isolated context** without the
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
/issue [issue-number]
```

Examples:

```
/issue 42      # open a plan-mode Claude on issue #42 in a new window + worktree
/issue         # list the repo's open issues and let you pick one
```

With no number, you get a single question listing open issues (newest first). Pick one — or choose
"Other" to type any issue number — and it dispatches.

## How it works

1. **List** (only when no number is given) — `bin/issue.sh list` derives `owner/repo` from
   the origin remote and calls `gh issue list --state open`, returning each issue with a pre-built
   pick option. The skill presents them via one `AskUserQuestion`.
2. **Dispatch** — `bin/issue.sh dispatch <n>` runs a strict, ordered sequence:
   - Hard preconditions first (tmux present, inside a git repo, `gh` authenticated, the issue
     exists and is open) — any failure stops **before** anything is opened.
   - `tmux new-window -d -c <repo-root> -n <repo-prefix>-<n>` — open the window **detached** (`-d`),
     so **your focus stays on the current window**, with a stable name (`age-42`-style), and capture
     its pane id. Every later keystroke targets that pane **by id**, so the handoff still lands in
     the new window without stealing focus. tmux's `automatic-rename` and program-driven
     `allow-rename` are turned **off** on the window so the name sticks even though Claude sets its
     own terminal title. (Set `ISSUE_FOREGROUND=1` to switch focus to the new window instead.)
   - **Worktree hygiene** — before launching Claude, idempotently ensure `.claude/worktrees/` is
     gitignored (the container dir `claude -w <repo-prefix>-<n>` builds its per-issue worktree
     under), so the ephemeral worktrees never dirty the parent repo's `git status`. It respects a
     broader existing rule (e.g. `.claude/`) and is a no-op when already ignored. Best-effort: a
     write failure only leaves the pre-fix status quo (an untracked worktree dir), never an
     `ok:false`. Override the ignored path with `ISSUE_WORKTREE_IGNORE_PATH`.
   - Launch `claude -w <repo-prefix>-<n> --permission-mode plan` (literal send + Enter) — the `-w`
     argument matches the window name, so the worktree is `.claude/worktrees/<repo-prefix>-<n>`; the
     `--permission-mode plan` flag opens the session **in plan mode deterministically**, with no
     keystrokes.
   - **Readiness gate** — poll `capture-pane` until Claude's TUI is up (it also has to build the
     worktree first), then type the prompt. Detection is **two-tier** so a Claude-Code footer-copy
     change can't false-negative it (issue #67): a **fast path** matches a broadened alternation of
     known idle-footer markers, and a **structural** fallback (input-box frame `─` **and** idle
     prompt glyph `❯`, held stable across polls) confirms readiness even when the footer copy has
     drifted entirely. A bounded blind fallback delay is the last resort so keystrokes aren't lost.
   - Type and submit the prompt, confirmed via a `capture-pane` read-back (resend if it never lands).
     A non-gating acceptance check additionally records whether a *ready* TUI consumed the prompt
     (`prompt_accepted`) without ever re-coupling confirmation to fragile TUI copy.
     The default prompt briefs the child session to comment its finalized plan on the issue, word
     PRs to close it (`Closes #<n>`), and comment each PR link — those steps happen later, inside
     that session, so the prompt is the only place they can be requested.
   - **Mark the issue `in-progress`** — `gh label create` (create-if-missing, existing styling left
     alone) then `gh issue edit --add-label`. Best-effort: a failure adds a `warning`, never an
     `ok:false`. Disable with `ISSUE_LABEL=`.
3. The original pane shows a one-line status. If the handoff or the label couldn't be fully
   confirmed, you get a `warning` telling you to glance at the new window — and, on that path, a
   `pane_tail` field carrying the last few non-blank lines of the new pane as diagnostic evidence,
   so you can triage without switching windows.

## Readiness self-test (`doctor`)

After upgrading Claude Code, run the readiness self-test to confirm the fast-path marker still
matches the installed build:

```
bash ${CLAUDE_PLUGIN_ROOT}/bin/issue.sh doctor
```

It spins a throwaway `claude` in a scratch **detached** tmux window, checks readiness, tears the
window down, and reports `{ok, readiness_confirmed, matched_tier}` where `matched_tier` is `marker`
(the footer marker still current), `structural` (the marker drifted but the frame+glyph fallback
carried it — consider updating `ISSUE_READY_PATTERN`), or `none` (readiness never confirmed —
see the `pane_tail`). It has **no** GitHub side effects and needs a live `claude`, so it is a manual
diagnostic, deliberately **not** part of `make test` (the pre-push gate stays deterministic/offline).

Once a side effect has happened (the window exists), the helper reports `ok:true` with a `warning`
rather than a hard failure — so a status line never falsely implies "nothing happened."

## Configuration (environment variables)

All optional; sensible defaults. Useful for customizing the launch/prompt or for testing.

| Variable | Default | Purpose |
|----------|---------|---------|
| `ISSUE_LAUNCH_CMD` | `claude -w <name> --permission-mode plan` | Command typed into the new window. `<name>` → the resolved window/worktree name (`<repo-prefix>-<n>`, so the worktree matches the window); `<n>` → issue number (still available). `--permission-mode plan` is what forces plan mode. |
| `ISSUE_PROMPT` | _(GitHub-reporting prompt)_ | Prompt typed + submitted once Claude is ready. Default asks the child to plan the fix, comment the finalized plan on the issue, word PRs to close it (`Closes #<n>`), and comment each PR link. `<n>` → issue number. Deliberately has no `/plan` prefix. |
| `ISSUE_LABEL` | `in-progress` | Label applied to the issue at dispatch (created in the repo if missing). Set to **empty** (`ISSUE_LABEL=`) to disable labeling entirely. |
| `ISSUE_LABEL_COLOR` | `fbca04` | Hex color (no `#`) used only when the label doesn't yet exist — existing labels keep their styling. |
| `ISSUE_LABEL_DESC` | `Actively being worked on` | Description used only when the label is first created. |
| `ISSUE_WINDOW_NAME` | _(computed)_ | Overrides the window **and worktree** name (the default launch renders `<name>` from this). Default is `<first-3-alnum-of-repo-lowercased>-<n>` (e.g. `age-42`). `<n>` → issue number. |
| `ISSUE_WORKTREE_IGNORE_PATH` | `.claude/worktrees/` | Path idempotently added to the repo's root `.gitignore` at dispatch so `claude -w`'s per-issue worktrees don't dirty `git status`. No-op if already ignored (respects a broader rule like `.claude/`). |
| `ISSUE_FOREGROUND` | _(unset)_ | By default the new window opens **detached** (`-d`), so your focus stays on the current window. Set to `1` to switch focus to the new window instead. |
| `ISSUE_ALLOW_CLOSED` | _(unset)_ | Set to `1` to dispatch even if the issue is closed. |
| `ISSUE_LIST_LIMIT` | `50` | Max open issues fetched for the picker. |
| `ISSUE_GH_BIN` | `gh` | Path to the `gh` binary (tests inject a fake). |
| `ISSUE_READY_PATTERN` | `for shortcuts\|for agents\|mode on\|to cycle` | **Fast-path** readiness marker — an ERE **alternation** of known idle-footer variants (kept metacharacter-free and mode-agnostic). TUI copy is version-specific, so this is only the fast path; if it drifts entirely the **structural** tier still confirms. Override to add/replace variants. |
| `ISSUE_READY_FRAME_GLYPH` / `_READY_PROMPT_GLYPH` | `─` / `❯` | **Structural-path** signals — the input-box frame rule and the idle prompt glyph, matched literally. Both must be present (plus stabilisation) to confirm readiness when no footer marker matches. The `❯` requirement stops a static framed *modal* (e.g. a folder-trust dialog) being mistaken for the idle input box. |
| `ISSUE_READY_STABLE_POLLS` | `3` | Structural path: consecutive **equal** pane captures required before confirming (3 comparisons = 4 identical samples). |
| `ISSUE_READY_ATTEMPTS` / `_READY_DELAY` | `60` / `0.25` | Readiness poll bound (≈15s). The fast path short-circuits success immediately, so the ceiling only bites on genuine failure. |
| `ISSUE_READY_FALLBACK_DELAY` | `3` | Extra settle (seconds) if **neither** tier confirms within the budget — a true last resort. |
| `ISSUE_READY_TAIL_LINES` | `8` | Non-blank pane lines attached as `pane_tail` diagnostic evidence on the **warning** path only. |
| `ISSUE_READY_ACCEPT_PATTERN` | _(working-indicator alternation)_ | Non-gating post-submit acceptance marker: informs the `prompt_accepted` field but never changes `prompt_confirmed` or triggers a resend. |
| `ISSUE_CONFIRM_ATTEMPTS` / `_CONFIRM_DELAY` / `_SEND_RETRIES` | `8` / `0.3` / `2` | Prompt-submission confirm/resend bounds. |
| `ISSUE_DOCTOR_LAUNCH_CMD` | `claude --permission-mode plan` | Launch command for the `doctor` readiness self-test (omits `-w`, so no worktree). |
| `ISSUE_DRY_RUN` | _(unset)_ | Set to `1` to run the read-only checks and print the exact tmux commands it *would* run, without opening a window. |

> **Plan mode is forced by the `--permission-mode plan` launch flag, not keystrokes.** `-w` is
> Claude Code's official `--worktree` switch (creates a named per-issue worktree — here named with
> the same `<repo-prefix>-<n>` formula as the window, e.g. worktree `.claude/worktrees/age-42` on
> branch `worktree-age-42`; only valid from a git-tracked location), and `--permission-mode plan`
> opens the session in plan mode with no
> `Shift+Tab` guesswork. That flag sets the *initial* mode only — you can still `Shift+Tab` out of
> plan mode once you've approved the plan. The prompt intentionally does **not** begin with `/plan`:
> that is a slash command that routes to a registered `/plan` skill (e.g. forge's planner), not
> Claude's built-in plan mode.

See `skills/issue/SKILL.md` for the routing logic and `bin/issue.sh` for the full
dispatch sequence.
