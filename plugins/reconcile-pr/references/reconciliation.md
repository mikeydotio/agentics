# Reconciliation methodology

Deep guidance for the `/reconcile-pr` resolution loop. The SKILL routes; this doc
is the *how* for the three model-judgment steps. Read it before resolving your
first conflict.

## The prime directive: preserve BOTH behaviors

A reconcile rebases the PR's commits onto the latest base. A conflict means the
base and the PR both changed the same region. Your resolution must keep **both**:

- **the pre-existing base behavior** — everything `main` (or the base branch) does
  today must keep working after the rebase; and
- **the PR's new behavior** — the change the PR set out to make must survive.

Picking one side wholesale is almost always wrong. The correct resolution is
usually a *merge of intents*: apply the base's change and the PR's change to the
same code so both hold.

## Reading a conflict without the "ours/theirs" trap

During `git rebase <base>`, git resets to the base and *replays* the PR's commits
on top. At a conflict the labels are **inverted** relative to `git merge`:

| Git marker | git's word | What it actually is |
| --- | --- | --- |
| `<<<<<<< HEAD` … | "ours" | the **base** (pre-existing behavior) |
| `\|\|\|\|\|\|\|` … | (zdiff3) | the **common ancestor** |
| `>>>>>>> <sha>` … | "theirs" | **this PR's** commit being replayed |

Because "HEAD" reads like "my branch's work" but is really the base, the script
**never** speaks in ours/theirs. It relabels the two sides in every `conflicts`
payload:

- `base_side` → the `<<<<<<<` block → latest base → **preserve**.
- `pr_side` → the `>>>>>>>` block → the PR's work (with its commit SHA) → **preserve**.

The rebase runs with `merge.conflictStyle=zdiff3`, so each hunk also shows the
`|||||||` **common-ancestor** block. Use it: diff ancestor→`base_side` to see what
the base changed, and ancestor→`pr_side` to see what the PR changed. When those
two edits are to different concerns, the resolution is "apply both." When they
edit the same value, you must reconcile them deliberately.

## Conflict types

Each entry in `conflicted_files[]` carries a `conflict_type`. Marker-editing only
applies to `both_modified` / `added_by_both`; the delete cases are keep-or-remove
decisions:

- `both_modified` — edit the markers, keeping both changes.
- `added_by_both` — both sides created the file; merge their contents.
- `deleted_by_base` — the base deleted a file the PR modified. Decide: does the
  PR's change still make sense (recreate the file with it) or did the base's
  deletion supersede it (remove it, `git rm`)?
- `deleted_by_pr` — the PR deleted a file the base modified. Usually keep the
  deletion unless the base's change is load-bearing.
- `both_deleted` — both deleted it; usually accept the deletion.

The `base_blob` / `pr_blob` / `ancestor_blob` fields are index refs
(`:2:path` / `:3:path` / `:1:path`) — run `git -C <worktree> show <ref>` to read a
side's full content when the in-file markers aren't enough.

## Workflow discipline

- Edit files **in the worktree** — the `path` fields are absolute paths into
  `.claude/worktrees/reconcile-pr/<pr>/worktree`. Your own checkout is untouched.
- After resolving, **stage** (`git -C <worktree> add …`). Do **not** commit — the
  rebase owns the commit. `continue` refuses while any path is still unmerged.
- Resolve **all** files for the current stopped commit before `continue`. A rebase
  stops per-commit; you may loop through several stops.
- If a resolution yields an empty commit (`empty_after_resolution`), that means the
  base already contains those changes. Dropping the PR commit (`continue --skip`)
  is a *judgment call* — confirm the base truly supersedes it before skipping.

## Testing is paramount

The reconcile is only trustworthy if the reconciled tree is *verified*:

- Always run `test <pr>` after a clean/finished rebase, before `push`.
- A `fail` almost always means a conflict was resolved in a way that dropped the
  base's or the PR's behavior. Read the failure, fix the resolution, re-test.
- If the reconciled region isn't covered by the suite, **add a focused test** that
  pins *both* the pre-existing and the new behavior — that regression net is the
  whole point of "preserve both."
- `RECONCILE_PR_TEST_CMD` sets the exact command. A worktree shares `.git` but not
  untracked/ignored files, so dependency installs must be part of it
  (`RECONCILE_PR_TEST_CMD="npm ci && npm test"`, `"uv sync && pytest"`, …).
- The push test gate is deterministic: `push` refuses `tests_failing`, and refuses
  `untested` unless the recorded *passing* run matches the current HEAD. Only a
  detected suite counts; `no_test_command` warns but allows (project policy).

## Force-push safety

- **NEVER force-push `main`**, the base branch, the repo's default branch, or any
  protected branch (`RECONCILE_PR_PROTECTED_GLOBS`). Only ever force-push the PR's
  own head branch, as the last step of reconciling it with its base. The `push`
  gate enforces this on the *destination ref* and refuses otherwise.
- The push uses an **explicit-OID lease**
  (`--force-with-lease=refs/heads/<dest>:<oid-recorded-at-start>`) — never a bare
  `--force`. If someone pushed to the PR branch after you started, the lease goes
  `stale` and the push is refused. Do not override it; `abort` and restart so you
  reconcile against their commit too.
- Pushes go over HTTPS (`url.https://github.com/.insteadOf git@github.com:`) so the
  SSH agent is never needed in a headless context.

## Environment knobs (all optional)

| Variable | Default | Purpose |
| --- | --- | --- |
| `RECONCILE_PR_GH_BIN` | `gh` | Path to the `gh` binary (tests inject a fake). |
| `RECONCILE_PR_TEST_CMD` | _(auto-detect)_ | Exact verify command run in the worktree. |
| `RECONCILE_PR_ALLOW_UNTESTED` | _(unset)_ | Override the `untested`/`tests_failing` push refusal. |
| `RECONCILE_PR_PROTECTED_GLOBS` | `main master develop staging prod production release/* gh-pages` | Head-branch globs that block a force-push. |
| `RECONCILE_PR_DEFAULT_BRANCH` | _(origin/HEAD → main)_ | Fallback default-branch name for the guard. |
| `RECONCILE_PR_SKIP_PUSH` | _(unset)_ | `push` emits the planned command without pushing. |
| `RECONCILE_PR_DRY_RUN` | _(unset)_ | `preflight`/`start`/`push`/`comment` plan only, no side effects. |
