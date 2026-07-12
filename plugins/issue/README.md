# issue

A **GitHub-issue lifecycle toolkit** for Claude Code. One `issue` skill routes a small verb grammar;
each verb pushes its deterministic work into `bin/issue.sh` (bash + `jq` + `gh` + `git`), which emits
one JSON object with `ok` + `display`. The skill only routes, renders, and asks at most one question
per verb — so token cost stays low and the guard rails live in code, not prose.

## Commands

| Command | What it does |
|---------|--------------|
| `/issue do <n>` | Spin up a fresh **plan-mode** Claude session for issue `<n>` in a **new tmux window** + per-issue git **worktree** (`claude -w <repo-prefix>-<n>`), mark the issue `in-progress`, and hand off a prompt asking it to plan a fix and report its plan/PRs back to the issue. |
| `/issue new <desc>` | Interrogate you for the nature, scope, and context of the need, draft a title + body, confirm, then **file** the issue via `gh` and return its number + link. |
| `/issue view <n>` | Print issue `<n>`'s full content (native `gh` rendering incl. comments) and **stop**. |
| `/issue complete <n>` | Close `<n>` as *completed* and **safely** clean up its artifacts — merged branches (local + remote) and clean worktrees — after showing exactly what it will remove and asking once. |
| `/issue <n>` | Run `view <n>`, then **offer** to work on it: decline → stop; accept → `do <n>`. |
| `/issue` | List the repo's open issues, let you pick one, then run the `/issue <n>` flow on it. |
| `/issue doctor` | Readiness self-test for `do`'s TUI handoff (run after a Claude Code upgrade). |

## When to use

- `do` — kick off work on an issue in an **isolated context** without the manual dance (open a
  window, make a worktree, launch Claude, switch to plan mode, paste a prompt). It is **not** a
  background agent: it hands off to a fresh interactive plan-mode Claude that you review and drive.
- `new` — turn a rough idea into a well-formed, filed issue without leaving the session.
- `view` — read an issue inline.
- `complete` — wrap up a finished issue and tidy the branches/worktrees it left behind, with a
  confirmation gate and guard rails that never touch unmerged, dirty, locked, current, or protected
  refs.

## Requirements

- **GitHub CLI** — `gh` installed and authenticated (`gh auth login`, or a `GH_TOKEN`) — for every
  verb.
- A git checkout with a GitHub **origin** remote (used to resolve `owner/repo`).
- **tmux** — required by `do` only (it opens a sibling window). The other verbs don't need it.

## `do` — how it works

When invoked without a number (bare `/issue`), the skill first runs `bin/issue.sh list` — it derives
`owner/repo` from the origin remote, calls `gh issue list --state open`, and returns each issue with
a pre-built pick option that the skill presents via one `AskUserQuestion`. With a number in hand
(from `do <n>`, or after the picker + "work on it"), it dispatches:

- **Dispatch** — `bin/issue.sh dispatch <n>` runs a strict, ordered sequence:
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
     The default prompt briefs the child session to read the issue and **all** its comments for the
     full history, weigh a reopen as a signal a previous fix fell short, comment its finalized plan
     on the issue, word PRs to close it (`Closes #<n>`), and comment each PR link — those steps
     happen later, inside that session, so the prompt is the only place they can be requested. It
     also tells the child **not to bump the version or deploy** from its worktree (no `/semver
     bump`, no `/deployit deploy`) — versioning and deployment happen later from `main`, and the
     semver/deployit CLIs now hard-refuse inside a worktree anyway.
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

## `view`, `new`, and `complete`

- **`view <n>`** — `bin/issue.sh view <n>` runs `gh issue view <n> --comments` and returns its
  native plaintext in `display` (plus structured `{issue,title,state,url}`). Read-only; the skill
  just prints it and stops.
- **`new <desc>`** — the skill follows `references/new.md`: a short interrogation (type, scope,
  acceptance) via one `AskUserQuestion` at a time, a drafted title + markdown body, one confirmation,
  then `bin/issue.sh create --title … --body-file …` (the body travels by file, never through shell
  quoting). `create` files via `gh issue create`, recovers the number from the printed URL, and
  returns `{number, url}`. Nothing is filed without an explicit confirmation.
- **`complete <n>`** — a two-phase, guard-railed cleanup (see `references/complete.md`):
  - `complete plan <n>` (read-only) enumerates the issue's worktrees (`<repo-prefix>-<n>` or legacy
    `<n>`) and branches (the `worktree-*` branches plus the head branches of MERGED PRs that closed
    the issue, via `closedByPullRequestsReferences`), classifies each, and previews exactly what it
    would close/remove and what it would **preserve**.
  - After one confirmation, `complete execute <n>` closes the issue as *completed* and removes **only
    the safe set**: clean, unlocked, non-current worktrees (`git worktree remove`, no `--force`) and
    **fully-merged** branches (`git branch -d` locally; merged PR heads deleted on the remote over
    the HTTPS credential-helper override). It never touches unmerged, dirty, locked, current, or
    protected/default refs — with git-native backstops so a scan bug can't cause data loss.
    `--no-clean` closes without deleting (the picker's "Close only"); `--no-close` cleans without
    closing.

## Configuration (environment variables)

All optional; sensible defaults. Useful for customizing the launch/prompt or for testing.

| Variable | Default | Purpose |
|----------|---------|---------|
| `ISSUE_LAUNCH_CMD` | `claude -w <name> --permission-mode plan` | Command typed into the new window. `<name>` → the resolved window/worktree name (`<repo-prefix>-<n>`, so the worktree matches the window); `<n>` → issue number (still available). `--permission-mode plan` is what forces plan mode. |
| `ISSUE_PROMPT` | _(GitHub-reporting prompt)_ | Prompt typed + submitted once Claude is ready. Default asks the child to read the issue and all its comments, weigh a reopen as a failed prior fix, plan the fix, comment the finalized plan on the issue, word PRs to close it (`Closes #<n>`), comment each PR link, and **never bump the version or deploy from the worktree** (that happens later from `main`). `<n>` → issue number. Deliberately has no `/plan` prefix. |
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

See `skills/issue/SKILL.md` for the verb routing, `bin/issue.sh` for every subcommand's
deterministic sequence, and `references/new.md` / `references/complete.md` for the `new` and
`complete` protocols.
