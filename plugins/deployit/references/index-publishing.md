# Index Publishing Reference

Every deploy ends by writing one entry to the shared **index repo**
(`mikeydotio/deployit-index` — an append-only `builds.json` that the web listing
renders). `gc` and the web UI's swipe-to-delete write to the same repo. This doc
covers how that write reaches `main` when the repo is protected.

## The problem

Historically deployit **pushed the index commit directly to `main`**. Once an
org-wide branch-protection ruleset (e.g. `protect-main`: "no direct pushes to
`main` on any repo") is active, GitHub rejects the push:

```
remote: error: GH013: Repository rule violations found for refs/heads/main.
remote: - Changes must be made through a pull request.
! [remote rejected] main -> main (push declined due to repository rule violations)
```

Without a fallback, every deploy dead-ends at publish — the app is built, signed,
and served locally, but no index entry lands, so it never shows on the listing.

## How deployit publishes now

The publisher (shared by `deploy`, `gc`, and `rm`) tries a direct push and, when
a ruleset rejects it, falls back to a PR. **The generated commit is never
discarded** — it is always preserved on a `deploy/<id>` branch and/or an open PR,
so publishing is recoverable without git-reflog archaeology.

```
git push origin main
  ├─ accepted                         → published (fast path; unprotected repos)
  ├─ GH013 / GH006 (ruleset/protected) → publish via PR ↓
  ├─ non-fast-forward (concurrent)     → re-pull fresh main, re-apply, retry
  └─ auth failure                      → preserve commit on a branch, fail loudly

publish via PR:
  git push --force-with-lease origin HEAD:refs/heads/deploy/<id>   # commit safe
  gh pr create --base main --head deploy/<id>
  auto_merge? gh pr merge --merge --delete-branch → published
            : leave PR open, print its URL          → pending (installable now,
                                                       listed after you merge)
```

## Configuration (`[index]` in `config.toml`)

| Key | Default | Meaning |
|---|---|---|
| `publish` | `"auto"` | `"auto"`: direct push, PR fallback on a ruleset rejection. `"pr"`: always via PR. `"push"`: direct-push only (fail, retaining the commit, if blocked). |
| `auto_merge` | `true` | Merge the publish PR automatically (`gh pr merge --merge`). Set `false` to leave PRs open and print their URLs. |

`deployit-index` allows **only merge-commits** (`allow_merge_commit=true`,
squash/rebase disabled), so the auto-merge always uses `--merge`.

## Auto-merge and the self-merge caveat

With `auto_merge = true`, the same authenticated `gh` identity both **creates and
merges** the publish PR. That's what makes a deploy fully hands-off. Two things to
know:

- If your ruleset requires an **approving review**, a self-merge can't satisfy it
  — the PR stays open (deployit prints the URL). Use a dedicated deploy
  identity/token (or a GitHub App) that is allowed to merge, or merge manually.
- An agent that self-creates **and** self-merges a PR can trip Claude Code's
  auto-mode review-gate guard. If you deploy through an agent under that guard,
  either set `auto_merge = false` and merge out-of-band, or run the merge under a
  dedicated deploy identity.

## Concurrency

Each publish attempt re-pulls a fresh `origin/main` before re-applying its change,
so a **direct-push** race just retries cleanly. In PR + auto-merge mode a genuine
race (two deploys prepending to `builds.json` at the same instant) can make the
second PR conflict at merge time; deployit then leaves that PR open with its URL
rather than forcing a resolution. Deploys from a single Mac never race.

## Alternative: exempt `deployit-index` from the ruleset (bypass actor)

`deployit-index` is a machine-generated, append-only index — a human review gate
on it has little value. If you'd rather keep the old zero-friction direct push,
make the deploying identity a **bypass actor** on the `protect-main` ruleset (or
exclude `deployit-index` from the ruleset):

```bash
# List rulesets to find protect-main's id:
gh api repos/mikeydotio/deployit-index/rulesets
# Then add your identity as a bypass actor in the ruleset UI/API, or drop
# deployit-index from the ruleset's repository targets.
```

With a bypass actor, `publish = "auto"`'s direct push succeeds again and no PR is
created. This weakens the "uniform org policy" story (one repo is now exempt) but
is the smallest possible change. The PR-publish default above needs **no** GitHub
carve-out, which is why it's the shipped default.

## Recovering a stuck publish

If deployit ever fails to publish AND to push a branch (e.g. broken auth), it
retains the commit on a **local** branch named `deploy/<id>-local` in the index
clone (`~/Library/Application Support/deployit/index`) and says so. Fix the cause,
then push that branch and open a PR by hand — nothing is lost.
