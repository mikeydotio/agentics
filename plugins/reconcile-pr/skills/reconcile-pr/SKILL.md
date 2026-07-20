---
name: reconcile-pr
description: Rebase a GitHub PR's branch onto the latest tip of its base branch, resolve any merge conflicts while preserving BOTH the pre-existing base behavior and the PR's new behavior, verify with exhaustive testing, force-push the reconciled branch under a leased safety guard, then comment on the PR summarizing the conflicts and their resolution. Use when the user says "reconcile PR N", "rebase PR N onto main", "resolve conflicts on PR N", or "bring PR N up to date". Requires an authenticated gh CLI and a git repo.
argument-hint: "<pr-number>"
---

# Reconcile PR

Rebase a GitHub PR onto the latest tip of its base branch, resolve conflicts
**preserving both sides**, test exhaustively, force-push the reconciled branch,
and comment the resolution on the PR.

You are a **thin router + judgment loop**. Every git/gh mechanic, every guard,
and the JSON contract live in `bin/reconcile-pr.sh` — you never call `git`, `gh`,
or touch the worktree layout yourself. Your job is to: run subcommands, render
their `display`, and perform the three steps only a model can do — **resolve
each conflict, verify behavior is preserved, and author the summary comment.**

Invoke the helper with:

```
bash ${CLAUDE_PLUGIN_ROOT}/bin/reconcile-pr.sh <subcommand> <pr-number> [args]
```

Every run emits ONE JSON object with `ok` + `display`. **If `ok` is `false`, show
the `display` (and any `reason`) to the user and stop** — do not improvise around
a guard rejection.

> **NEVER force-push `main`** (or any base/default/protected branch). Only ever
> force-push a PR's *own head branch*, and only as part of reconciling it *with*
> its base. The script enforces this in the `push` gate; do not attempt a push by
> any other means.

## Argument

Parse `ARGUMENTS`: it must be a **single positive integer** (the PR number). If
it is missing or malformed, say one line — `Usage: /reconcile-pr <pr-number>` —
and stop.

## Flow

### 1. Preflight
Run `preflight <pr>`. Render the plan. On `ok:false`, stop (common reasons: PR
not OPEN, a fork/cross-repo PR — unsupported in v1, a protected head branch, gh
unauthenticated).

### 2. Start the rebase
Run `start <pr>`. Branch on `status`:
- `already_current` → the PR already contains the latest base. Report it; there
  is nothing to reconcile. **Stop** (no push).
- `clean` → the rebase replayed with no conflicts. Go to **step 4**.
- `conflicts` → go to **step 3**.

### 3. Resolution loop (only a model can do this)
The response carries `conflicted_files[]` and `labels`. **Read the methodology
in `${CLAUDE_PLUGIN_ROOT}/references/reconciliation.md` before resolving.** Key
rules:
- The conflict sides are relabeled to avoid the rebase "ours/theirs" inversion:
  - `base_side` = the latest **base branch** — pre-existing behavior to preserve
    (the `<<<<<<<` block).
  - `pr_side` = **this PR's** new work, anchored to the replayed commit (the
    `>>>>>>>` block).
  - The `|||||||` block (zdiff3) is the common ancestor — use it to see what each
    side *changed* independently.
- **Resolve to keep BOTH intents.** Never blanket `--ours`/`--theirs`. Honor each
  file's `conflict_type` (`both_modified`, `deleted_by_base`, `deleted_by_pr`,
  `added_by_both`, …) — a delete/modify conflict is a keep-or-remove decision, not
  a marker edit.
- Edit the files **in the worktree** (the absolute `path` fields point there),
  then stage them with `git -C <worktree> add <file>` (or `git add -A` from inside
  the worktree). Do not commit — the rebase owns the commit.

Then run `continue <pr>`. Branch on the new `status`:
- `conflicts` → resolve the next commit's conflicts; loop.
- `empty_after_resolution` → your resolution made the replayed commit empty
  (the base already contains these changes). If that is genuinely correct, run
  `continue <pr> --skip` to drop the commit; otherwise re-resolve to preserve the
  PR's intent, stage, and `continue` again.
- `clean` → the rebase is complete. Go to **step 4**.

If you cannot safely reconcile a conflict, run `abort <pr>` and report — never
guess.

### 4. Verify — exhaustive testing is paramount
Run `test <pr>`. Branch on `status`:
- `pass` → proceed.
- `fail` → the resolution most likely broke behavior. Investigate the `tail`,
  fix the resolution (edit + `git add` in the worktree — you may need to
  `continue`/re-run through the loop, or amend the top commit), and re-`test`. Do
  **not** proceed to push on a failing suite. If you cannot make it pass, `abort`.
- `no_test_command` → no suite was detected. Note this to the user; if the
  reconciled area is testable, add a focused test (in the worktree) pinning both
  the pre-existing and the new behavior, then re-`test`. `push` will warn-but-allow
  without a suite (the user's chosen policy), but a verified push is the goal.

### 5. Author the summary
Write the PR comment body to a file (e.g. under the scratchpad). Read the
worktree's `.claude/worktrees/reconcile-pr/<pr>/conflicts.log` for the factual
skeleton (which commits, which files, which conflict types). For **each** conflict
summarize its **nature** (files; what the base changed vs. what the PR changed)
and its **resolution** (how both were preserved), then note the rebase outcome and
the test result. If the rebase was clean, a brief "rebased onto latest `<base>`,
no conflicts" note is enough.

### 6. Push (the safety gate)
Run `push <pr>`. On `ok:true`, report the pushed branch + `new_oid` (surface any
`warning`). On `ok:false`, show the `reason` and stop:
- `protected` / `cross_repo` / `head_changed` → refuse to work around it.
- `untested` / `tests_failing` → return to **step 4**.
- `stale` → someone pushed to the PR branch since you started; the lease
  correctly refused. Do **not** force past it — `abort <pr>` and start over.

### 7. Comment, then clean up
Only after a successful push: run `comment <pr> <body-file>` and report the URL.
Then run `cleanup <pr>` to remove the worktree and state. Give the user a final
one-line summary (branch reconciled, N conflicts resolved, tests, PR URL).

## Recovering mid-flow
If you lose context, run `status <pr>` to re-orient (it reports `idle`,
`mid_rebase` with the unresolved files, or `clean`) and resume from the matching
step. Every subcommand resolves its state from the repository, not your shell's
current directory, so this works whether you run it from the main checkout or
from inside the reconcile worktree itself — which is exactly where you'll
naturally be after staging a resolution.

## Notes
- **Requires** an authenticated `gh` CLI and a git repo with a GitHub `origin`.
- All behavior is env-overridable (`RECONCILE_PR_*`) — see the README's
  configuration table and `references/reconciliation.md`. Notably
  `RECONCILE_PR_TEST_CMD` sets the exact verify command (the reconcile worktree
  shares `.git` but **not** untracked/ignored files, so deps like `node_modules`
  may need `RECONCILE_PR_TEST_CMD="npm ci && npm test"`).
- The helper owns the launch details, the guards, and the force-push — don't
  reimplement them here.
