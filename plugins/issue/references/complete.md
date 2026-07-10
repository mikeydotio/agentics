# `/issue complete` — close an issue and safely clean up its artifacts

This is the protocol for the `complete` verb. The router loads it **only** when
the user runs `/issue complete <n>`. All git/gh mechanics and every guard rail
live in `bin/issue.sh` — your job is to run the two-phase flow and get **one**
confirmation before anything destructive happens. **Never run `git` or `gh`
yourself.**

## Flow

1. **Plan (read-only).** Run:
   ```
   bash ${CLAUDE_PLUGIN_ROOT}/bin/issue.sh complete plan <n>
   ```
   - `ok:false` → show `display`, stop (e.g. not a git repo, gh unauth, issue not
     found).
   - `ok:true` → the `display` is a ready-made preview: whether it will close the
     issue, exactly which worktrees/branches it will remove, and what it will
     **preserve** (unmerged/dirty/locked/current/protected — skipped with a
     reason). `actions_count` is the number of destructive actions.

2. **If `actions_count == 0` and the issue is already closed**, there's nothing to
   do — show the `display` and stop without asking.

3. **Confirm — exactly one `AskUserQuestion`.** Present the plan's `display`
   (fenced, so the user sees the exact targets) and ask, with `header:
   "Complete #<n>"`:
   - **Proceed** — close + remove everything listed.
   - **Close only** — close the issue but delete nothing.
   - **Cancel** — do nothing.

4. **Execute** according to the choice:
   - **Proceed** → `bash ${CLAUDE_PLUGIN_ROOT}/bin/issue.sh complete execute <n>`
     (closes the issue **and** removes the safe target set).
   - **Close only** → `bash ${CLAUDE_PLUGIN_ROOT}/bin/issue.sh complete execute <n> --no-clean`
     (closes the issue, deletes nothing).
   - **Cancel** → stop; run nothing.

   > The inverse flag `--no-close` cleans up but leaves the issue open — use it if
   > the user asks to tidy artifacts without closing.

5. **Render the result.** Show the execute result's `display`. It reports what was
   closed, what was removed (worktree / branch counts), anything it `Could not`
   do, and everything `Preserved`. If a `failed` array is present, surface it.

## Guard rails (enforced by the script, not you)

- Only **fully-merged** branches are deleted (`git branch -d` refuses unmerged as
  a backstop); the default/protected branches are never touched.
- Only **clean, unlocked, non-current** worktrees are removed (`git worktree
  remove` without `--force` refuses dirty/current as a backstop).
- Remote branch deletion happens **only** for the head branches of MERGED PRs that
  closed the issue, and pushes over the HTTPS credential-helper override.
- You never call `git`/`gh` — the helper owns every mutation and the confirmation
  gate is the single point where the user authorizes it.
