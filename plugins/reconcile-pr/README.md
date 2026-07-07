# reconcile-pr

Bring a GitHub pull request up to date with its base branch — safely. `/reconcile-pr`
rebases the PR's branch onto the latest tip of its base (normally `origin/main`),
walks the model through resolving any merge conflicts **while preserving both the
pre-existing base behavior and the PR's new behavior**, verifies with the project's
test suite, force-pushes the reconciled branch under a leased safety guard, and
comments on the PR summarizing what conflicted and how it was resolved.

The deterministic work — validation, fetch, an isolated worktree, driving the
rebase, enumerating conflicts, the test gate, and the force-push — lives in
`bin/reconcile-pr.sh`. The skill is a thin router plus the three steps only a model
can do: resolve conflicts, verify behavior is preserved, and write the summary.

## When to use

Reach for it when a PR has fallen behind `main` and needs a rebase — with or
without conflicts — and you want the reconciliation done carefully and verified,
not just fast-forwarded. Say "reconcile PR 42", "rebase PR 42 onto main", or
"resolve the conflicts on PR 42".

It is **not** a merge-and-forget button: it rebases (rewrites the PR branch's
history) and force-pushes the result, and it will refuse to proceed when tests
fail or a guard trips.

## Requirements

- **`gh`** (GitHub CLI), authenticated (`gh auth status`).
- A **git repository** with a GitHub `origin` remote.
- The PR must be **OPEN** and **not from a fork** (cross-repository PRs are not
  supported in v1).

## Usage

```
/reconcile-pr <pr-number>
```

```
/reconcile-pr 42      # reconcile PR #42 onto its base branch
```

## How it works

All rebase work happens in a dedicated git **worktree** under
`.claude/worktrees/reconcile-pr/<pr>/` — your own checkout is never touched. The
flow is a small state machine; the skill runs one subcommand per step and renders
its JSON `display`:

1. **preflight** — validate (OPEN, not a fork, base/head branches, gh auth) and
   show the plan. Read-only.
2. **start** — fetch, create the worktree, and begin the rebase. Reports
   `already_current`, `clean`, or `conflicts`.
3. **resolve → continue** (looped) — for each conflicted commit the model resolves
   every file preserving *both* sides (labeled `base_side` / `pr_side` to avoid the
   rebase ours/theirs inversion, with a `zdiff3` common-ancestor block), stages
   them, and runs `continue` until the rebase is `clean`.
4. **test** — run the suite in the worktree. A failure blocks the push.
5. **push** — force-push the PR's head branch with an explicit-OID
   `--force-with-lease`. **Never** touches a protected branch and **never** falls
   back to a bare `--force`; refuses on a stale lease.
6. **comment** — post the model-authored resolution summary on the PR.
7. **cleanup** — remove the worktree and state.

`status <pr>` re-orients after a context clear; `abort <pr>` bails out of an
in-progress rebase (leaving the PR branch on GitHub untouched).

## Safety

- **Never force-pushes `main`** (or the base/default/any protected branch). The
  `push` gate guards the *destination ref* and only ever force-pushes the PR's own
  head branch, as the final step of reconciling it with its base.
- **Leased pushes only.** `--force-with-lease=refs/heads/<dest>:<oid>` with the OID
  recorded at `start`; if the branch moved since, the push is refused as `stale`,
  never forced.
- **Test-gated.** By default `push` refuses a failing or unverified tree (override
  with `RECONCILE_PR_ALLOW_UNTESTED=1`); when no suite is detected it warns but
  allows.

## Configuration (environment variables)

| Variable | Default | Purpose |
| --- | --- | --- |
| `RECONCILE_PR_GH_BIN` | `gh` | Path to the `gh` binary. |
| `RECONCILE_PR_TEST_CMD` | _(auto-detect: Makefile `test` / `npm test`)_ | Exact verify command, run in the worktree. Include dep install if needed (`npm ci && npm test`). |
| `RECONCILE_PR_ALLOW_UNTESTED` | _(unset)_ | Override the `untested` / `tests_failing` push refusal. |
| `RECONCILE_PR_PROTECTED_GLOBS` | `main master develop staging prod production release/* gh-pages` | Head-branch globs that block a force-push. |
| `RECONCILE_PR_DEFAULT_BRANCH` | _(origin/HEAD → main)_ | Fallback default-branch name for the guard. |
| `RECONCILE_PR_SKIP_PUSH` | _(unset)_ | `push` emits the planned command without pushing (used by tests). |
| `RECONCILE_PR_DRY_RUN` | _(unset)_ | `preflight`/`start`/`push`/`comment` plan only, no side effects. |

> The reconcile worktree shares `.git` but **not** untracked/ignored files, so a
> suite that needs `node_modules`/`.venv`/build caches must install them as part of
> `RECONCILE_PR_TEST_CMD`.

See `skills/reconcile-pr/SKILL.md` for the orchestration and
`references/reconciliation.md` for the conflict-resolution methodology and the
full force-push safety rules.
