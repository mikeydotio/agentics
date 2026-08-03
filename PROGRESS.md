# PROGRESS.md — autonomous backlog loop

**If you are a fresh session that was just handed "continue the autonomous backlog loop": this
file is your only memory. Read it start to finish before doing anything.**

You are one link in a chain of sessions working `mikeydotio/agentics`' storyhook backlog to
completion, one story per session, unattended. Each session takes exactly one story from the
queue, carries it all the way to a merged PR, updates this file, hands off to the next session
via freshen, and stops.

---

## Current position

| | |
|---|---|
| **Loop status** | NOT STARTED — scaffolding session complete, first story not yet begun |
| **Story in flight** | none |
| **Next story** | **AGE-14** |
| **Completed this loop** | none |
| **Last updated by** | scaffolding session, 2026-08-03 |

> Update this table **twice** per story: once when you claim it (status → IN FLIGHT), once when
> it merges (move it to Completed, set the next story). It is the first thing the next session
> reads.

---

## Known state at loop start (2026-08-03, main @ `03c0591`, `VERSION` = v2.38.0)

Read this before you conclude something you did broke the build.

- **`make test` is already red**, in two independent ways:
  - **6 forge failures** — `289/290/313` in `forge-state.test.bats` and `384/385/386` in
    `forge-storyhook-setup-contract.bats`, all `error: state ` + "`blocked` already exists".
    This is exactly AGE-14, story #1 in the queue. They go green when it lands.
  - **`test_shipped_content_matches_tagged_release`** — PRs #124 and #125 merged shipped
    `plugins/**` content without a bump, so the tree is ahead of tag `v2.38.0`. The **first
    bump any session performs clears this**, because it covers all accumulated drift, not just
    that session's own. AGE-14's bump will do it.
- Consequence: **until AGE-14 merges, the pre-push hook cannot pass.** For any push before then
  (this scaffolding commit included), `SKIP_PREPUSH_TESTS=1` is the sanctioned bypass for a
  change that ships no runtime code. After AGE-14, the gate is live again — do not bypass it.
- No worktrees are in use by this loop. One unrelated worktree
  (`.claude/worktrees/dual-host-plugin-compatibility`) and one leftover
  (`.claude/worktrees/age-AGE-2`, merged, reclaimable) exist — ignore both.

---

## The queue

Ordered by priority first, then constrained by the storyhook dependency graph. Do not reorder
without recording why in this file.

| # | Story | Pri | Why here |
|---|---|---|---|
| 1 | **AGE-14** | high | Only `high`. `make test` is red until it lands, so the pre-push gate is dead for every session after this one. Must go first. |
| 2 | **AGE-11** | med | First of the three stories that edit `execution-loop.md` / `step-handoff.md`. Smallest of the trio — land it before the two that restructure those files. |
| 3 | **AGE-4** | med | Splits `execution-loop.md`. After AGE-11. |
| 4 | **AGE-5** | med | Rewrites around `step-handoff.md`. After AGE-11. |
| 5 | **AGE-6** | med | WS-C, rca realign. Independent. |
| 6 | **AGE-12** | med | storywork claim diagnostic. Independent. |
| 7 | **AGE-10** | low | **Pulled ahead of its priority** — AGE-7 is `blocked-by` it, and storyhook will refuse to dispatch AGE-7 until it closes. |
| 8 | **AGE-7** | med | WS-D + the prompt-hygiene lint. Needs AGE-10 done. **On merge, also close AGE-8** (below). |
| — | **AGE-8** | low | **Do not work this story.** It is `obviated-by` AGE-7 and storyhook already excludes it from `ready`. When AGE-7 merges, close it: `story move AGE-8 done` with a comment pointing at AGE-7's PR. |
| 9 | **AGE-9** | low | Council-decision story, independent. |
| 10 | **AGE-13** | low | Council-decision story, independent. |

**AGE-2 and AGE-3 are already `done`** — do not touch them.

---

## Per-story protocol

Run these in order. Do not skip the bump (step 7) or the loop breaks for everyone after you.

### 1. Orient
```bash
story list                     # anything stuck in `in-progress` = a crashed session, see Recovery
story show <id> --json         # read the description AND every comment — they carry corrections
git -C . status --porcelain    # must be clean before you start
```

### 2. Claim
```bash
story move <id> in-progress
```

### 3. Mark this file IN FLIGHT
Set **Loop status** = `IN FLIGHT`, **Story in flight** = `<id>`. Commit it with your first commit.

### 4. Branch
```bash
git fetch origin main && git switch -c <type>/<id>-<short-slug> origin/main
```
`<type>` is `fix` for bugs, `chore`/`refactor`/`docs`/`test` otherwise — match the story's type.
**Work in this main checkout on a feature branch. Do not create a git worktree** — worktrees
hard-block the version bump you need in step 7.

### 5. Implement, TDD
Red test first, then the minimum correct code. Two hats: never mix a behaviour fix and a
refactor in one commit. Follow CLAUDE.md's programming and defect-handling standards — they
apply in full here.

### 6. Decisions → council, not the user
Several stories in this queue explicitly need a design or product decision (AGE-11, AGE-12,
AGE-9, AGE-13 all say so in their text). **Do not stop and ask the user.** Convene
`/council-vote`, let it rule, then post the verdict as a story comment
(`story comment <id> "..."`) so the reasoning is durable.

The **only** exception: if a story or one of its comments *explicitly* says a human must decide,
stop and `story block <id> "<what you need>"`, update this file, and hand off (step 12) noting
the block. Nothing currently in the queue does this.

### 7. Version bump — REQUIRED when you touched shipped `plugins/**`
`tests/plugin-content-drift.sh` fails whenever shipped `plugins/**` differs from tag
`v<VERSION>`, and the pre-push hook runs `make test`. So your own change makes the suite red
until you bump. Bump on your feature branch so the fix and the bump land in one PR:

```bash
make -k test    # confirm plugin-content-drift is the ONLY red suite before bumping
python3 plugins/semver/bin/semver-cli bump execute <patch|minor|major> \
        --source manual --plugin-root "$(pwd)/plugins/semver"
make test       # must now be FULLY green
```

Interactive `/semver bump` stalls on an unbypassable `wrong_branch` prompt from a feature
branch — use the `semver-cli` invocation above. Pick the level by CLAUDE.md's rules (bug fix =
patch; new capability = minor; breaking = major).

If your story touched **no** shipped `plugins/**` content (e.g. root `tests/` only), no bump is
needed and `make test` should already be green.

### 8. Verifying
```bash
story move <id> verifying
```

### 9. Update this file (the "after" pass)
Move the story into **Completed this loop**, set **Next story** to the next queue row, clear
**Story in flight**, add a one-line note of anything the next session must know (a surprise, a
new story you filed, a convention you had to establish). Commit it.

### 10. Push, PR, merge
```bash
git -c url."https://github.com/".insteadOf="git@github.com:" push origin <branch>
gh pr create --title "<conventional commit title>" --body "<what/why; references <id>>"
gh pr merge <n> --merge        # merge commit ONLY — squash and rebase are disabled org-wide
```
**Push the branch only — never the tag.** After the merge lands:
```bash
git switch main && git pull --ff-only
git push origin v<X.Y.Z>       # clean first push, no force needed
git push origin --delete <branch>
/semver validate               # expect all-PASS
```
Auto-merge without asking — that is standing policy for this repo (see
`/Volumes/Code/mikeyward/CLAUDE.md`) and was explicitly reconfirmed for this loop.

### 11. Close the story
```bash
story comment <id> "Merged as PR #<n> (<merge-sha>). <one-line summary>"
story move <id> done
```

### 12. Hand off and STOP
```bash
bash plugins/freshen/bin/freshen.sh queue \
  "Read PROGRESS.md in /Volumes/Code/mikeyward/agentics and continue the autonomous backlog loop: take the next story in the queue, carry it to a merged PR, auto-merge it, update PROGRESS.md, then hand off to the next session. Convene /council-vote for any decision rather than asking the user." \
  --source backlog-loop \
  --summary "<id> done — next: <next-id>"
```
Then **stop your turn immediately**. The freshen Stop hook sends `/clear`; the
SessionStart(clear) hook re-sends the prompt above into a fresh session. Do not do any more work
after queueing.

**When the queue is empty**, do not queue a freshen. Set **Loop status** = `COMPLETE`, write a
closing summary in this file, and stop so the user comes back to a finished backlog.

---

## Conventions and gotchas

- **Never force-push.** If you think you need to, stop and leave it for the user.
- **Never bump or deploy from a linked worktree** — that is why this loop works on feature
  branches in the main checkout instead. The semver/deployit CLIs hard-refuse in a worktree.
- **Push over HTTPS** with the `-c url.…insteadOf` form above; SSH needs 1Password's agent,
  which an unattended session cannot approve.
- **No tests in GitHub Actions** — run `make test` locally, always, before pushing.
- **Defects you discover become stories immediately.** File them (`story new … --type bug
  --priority …`) in the repo's house format (What / Where / Root cause / Repro / Extent / Last
  known good / Fix direction) the moment you find them. Do not wait to be asked, and do not
  merely mention them in a summary — that is a standing instruction from the user. Note any new
  story in this file so the next session can slot it into the queue.
- **A story's comments outrank its description.** Several here carry audit corrections that
  supersede the original text — AGE-7, AGE-8 and AGE-11 each have a "Audit correction
  (2026-08-03)" comment that changes their scope.
- `.freshen/` is gitignored and ephemeral; never commit it.

## Recovery — if the loop stalls

A session that crashes mid-story leaves the story at `in-progress` with no freshen signal, and
the chain simply stops. To restart:

1. `story list` — a story sitting at `in-progress` or `verifying` is the abandoned one.
2. `git status` / `git branch --list` — decide whether its branch is salvageable or should be
   deleted and restarted from `origin/main`.
3. Fix this file's **Current position** table to match reality.
4. Resume that story from step 1 of the protocol.

`bash plugins/freshen/bin/freshen.sh status` shows whether a signal is still pending; `… cancel
--all` clears a wedged one. Never run `freshen enable`/`disable` — those are the user's alone.
