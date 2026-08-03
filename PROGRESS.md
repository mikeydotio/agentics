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
| **Loop status** | RUNNING |
| **Story in flight** | none |
| **Next story** | **AGE-11** |
| **Completed this loop** | AGE-14, AGE-15 (one PR) |
| **Last updated by** | AGE-14 session, 2026-08-03 |

> Update this table **twice** per story: once when you claim it (status → IN FLIGHT), once when
> it merges (move it to Completed, set the next story). It is the first thing the next session
> reads.

---

## Known state (updated 2026-08-03 by the AGE-14 session)

Read this before you conclude something you did broke the build.

- **`make test` is now GREEN** (bar the two caveats below). The pre-push gate is live again —
  **do not bypass it.**
- **`session-stop.bats` "a hanging story handoff is bounded by a timeout" WILL block your push.**
  Filed as **AGE-16**, now `high` + `blocks-ci`. It first looked like load-flakiness (passes 4/4
  unloaded, fails 2-of-3 at load ~13), but measuring it disproved that: isolated runs took
  5.68s / 11.28s / **27.46s**, and 27s against a **5s** internal timeout means F051's bound is not
  holding at all. Treat a red here as the known defect, not as something you broke — but confirm
  your branch does not touch `session-stop.sh`/`.bats` before you accept that.
- **`SKIP_PREPUSH_TESTS=1` was needed twice in the AGE-14 session**, solely because of AGE-16 and
  AGE-21 — never to mask anything from that branch. If you must bypass, run the full suite first,
  record the failing test names and why they are unrelated, and put that evidence in the PR body.
  Bypassing without that record is the thing the rule exists to stop.
- **`test_shipped_content_matches_tagged_release`** is expected-red on any branch that changes
  shipped `plugins/**` until that branch's `/semver bump` lands. Cleared for the #124/#125
  backlog by AGE-14's bump.
- Two `/issue do` worktrees were dispatched by the user mid-loop and are **live, not leftovers**:
  `.claude/worktrees/age-117` and `age-118`. Do not reclaim them. Also present and unrelated:
  `dual-host-plugin-compatibility`, and `age-AGE-2` (merged, reclaimable).

### ⚠ Scope collision the next sessions must resolve

The user dispatched **GitHub issue #118 — "Realign skills, agents, and model selection for the
Claude 5 generation"** into its own worktree. That overlaps **AGE-6** (WS-C, rca realign) and
**AGE-7** (WS-D, remaining plugins + prompt-hygiene lint), queue rows 5 and 8. Two agents editing
the same skill files from different branches will conflict. **Before starting AGE-6, check
whether #118 has merged**; if it has, re-scope or close AGE-6/AGE-7 against it rather than
redoing the work. The user was asked to rule on ownership and had not replied when this session
ended.

### What AGE-14 turned out to be

AGE-14 as filed was **incomplete, not wrong**. Its stated cause (`story state add blocked`
colliding with a template that now ships `blocked`) was real but *unreachable*: the dominant
failure was that **storyhook 2.0.0 renamed `story project init` → `story project new`**, so every
fixture aborted in setup before `story state add` ever ran. 59 tests were red, not 6. The rename
was filed as **AGE-15** and landed in the same PR (council-ruled). Four boundary defects found
along the way were filed rather than fixed — see the new-stories list below.

---

## The queue

Ordered by priority first, then constrained by the storyhook dependency graph. Do not reorder
without recording why in this file.

| # | Story | Pri | Why here |
|---|---|---|---|
| ✅ | ~~**AGE-14** + **AGE-15**~~ | high | **DONE** — merged together as one PR. See "What AGE-14 turned out to be" above. |
| 1 | **AGE-11** | med | First of the three stories that edit `execution-loop.md` / `step-handoff.md`. Smallest of the trio — land it before the two that restructure those files. |
| 3 | **AGE-4** | med | Splits `execution-loop.md`. After AGE-11. |
| 4 | **AGE-5** | med | Rewrites around `step-handoff.md`. After AGE-11. |
| 5 | **AGE-6** | med | WS-C, rca realign. Independent. |
| 6 | **AGE-12** | med | storywork claim diagnostic. Independent. |
| 7 | **AGE-10** | low | **Pulled ahead of its priority** — AGE-7 is `blocked-by` it, and storyhook will refuse to dispatch AGE-7 until it closes. |
| 8 | **AGE-7** | med | WS-D + the prompt-hygiene lint. Needs AGE-10 done. **On merge, also close AGE-8** (below). |
| — | **AGE-8** | low | **Do not work this story.** It is `obviated-by` AGE-7 and storyhook already excludes it from `ready`. When AGE-7 merges, close it: `story move AGE-8 done` with a comment pointing at AGE-7's PR. |
| 9 | **AGE-9** | low | Council-decision story, independent. |
| 10 | **AGE-13** | low | Council-decision story, independent. |

**AGE-2, AGE-3, AGE-14 and AGE-15 are already `done`** — do not touch them.

### New stories filed by the AGE-14 session — slot these in

Found while working AGE-14; filed rather than fixed, per the "defects become stories" rule. None
is scheduled yet. Recommended: take **AGE-18** and **AGE-17** early — they are the reason a
60-test breakage went unseen, and every "the suite is green" claim this loop makes is only as
trustworthy as they are.

| Story | Pri | What |
|---|---|---|
| **AGE-17** | high | `forge-contract-check.sh:87` derives verbs with `awk '{print $2}'` — **first token only**, so `story project init` validated as verb `project` and passed. The F103 drift guard is structurally blind to every subcommand rename. |
| **AGE-18** | high | `make test` **exits 0 when `bats` is absent** (`Makefile` `else echo "skipping"`, ~6 targets), so the pre-push gate is vacuously green on any machine without it. Same class: contract-check `exit 0`s on `story_cli_missing`. |
| **AGE-16** | **high** | **`blocks-ci`.** forge's Stop hook: F051's 5s timeout does **not** bound a hung `story handoff`. Isolated runs measured 5.68s / 11.28s / **27.46s** — 27s against a 5s limit means it is not bounded at all (an orphaned grandchild appears to hold the command-substitution pipe open). A production defect, not a flaky assertion. **It blocked two consecutive full `make test` runs during the AGE-14 session** while all other 427 forge tests passed. **Do not "fix" it by raising the 12s bound** — that hides the defect the number is exposing. |
| **AGE-19** | med | No storyhook **major-version pin** anywhere. An upstream major surfaces as ~60 unattributable failures instead of one assertion. |
| **AGE-21** | med | `plugins/deployit/tests/test-cli-rm.sh` depends on a **live local deployit backend daemon** (`:8729`); when it is unavailable the test fails and blocks unrelated pushes. Passed 3/3 in earlier runs, failed once under contention from the `age-117` session, passed again immediately after. Same class as AGE-18 — a gate that does not mean what it says. |
| **AGE-20** | low | Ten duplicated storyhook fixture-creation sites across two plugins — why one upstream rename cost ten edits. **Deliberately deferred**: the 10th site is in a *different plugin*, so a shared helper is a new cross-plugin module boundary, not a mechanical extraction. Land it alone, never beside a behaviour fix whose proof depends on those fixtures. |

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
- **Reproduce the story's stated cause before you fix it — the story can be wrong.** AGE-14 named
  a specific error and predicted 6 failures; the real breakage was a different upstream change
  and 59 failures. Its diagnosis had been written from *inference*, because the fixtures were
  swallowing the CLI's actual error text. Run the failing tests and read the real output first.
  If the story is wrong, file the true cause as its own story and say so in the PR — do not
  quietly widen the original.
- **Suspect load before you believe a timing failure.** Several suites here assert wall-clock
  bounds with thin margins (AGE-16). Concurrent Claude sessions push load average past 13 and
  flip them red. Check `uptime`, re-run serially, and only then treat it as signal. A subagent
  in this session reported a "deterministic" failure that was pure load.
- **Council decisions are archived, not just acted on.** `/council-vote` writes the full audit
  trail to `.council/<slug>/` (gitignored). AGE-14's scope ruling is at
  `.council/age14-fix-scope/DECISION.md` — read it before reopening that question.
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
