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
| **Completed this loop** | AGE-14, AGE-15 (one PR), AGE-16, AGE-18, AGE-17 |
| **Last updated by** | AGE-17 session, 2026-08-04 |

> Update this table **twice** per story: once when you claim it (status → IN FLIGHT), once when
> it merges (move it to Completed, set the next story). It is the first thing the next session
> reads.

---

## Known state (updated 2026-08-04 by the AGE-17 session)

- **The repo is at v2.40.0** (AGE-17 shipped a `minor` — it added two keys to
  `forge-contract-check.sh`'s documented JSON output, which CLAUDE.md classes as a non-breaking
  public-API addition, not a patch).
- **`make test` was fully green on a clean tree before AGE-17's change** (`MAKE_EXIT=0`, zero
  failures across every suite) and fully green again after the bump. Two sessions running now.
  **No `SKIP_PREPUSH_TESTS=1` was needed.** Treat a bypass as a red flag.
- **⚠ `plugin-content-drift` is HEAD-sensitive, so a `make test` you started before committing
  reports a STALE result.** The check is `git diff v<VERSION> HEAD`; if your work is still
  uncommitted, it compares the tag against the tagged commit and passes vacuously. This session
  hit it: a 15-minute run reported drift green, and re-running the one suite after committing
  turned it red as it should be. **Commit first, then run the gate** — or at minimum re-run
  `bash tests/with-isolated-store.sh bash tests/plugin-content-drift.sh` after your last commit.

## Known state (from the AGE-18 session)

Read this before you conclude something you did broke the build.

- **⚠ The gate now MEANS something — and it is stricter than it was.** Before AGE-18 the five
  bats targets exited 0 when `bats` was missing, so `make test` could report success having
  verified nothing. That swallow is gone: a missing `bats` now hard-fails the gate. There is
  **deliberately no `ALLOW_MISSING_TOOLS` override** — the only sanctioned bypass remains
  `SKIP_PREPUSH_TESTS=1` / `--no-verify`, which announces itself. If you land on a machine
  without bats, `brew install bats-core`; do not reintroduce a skip.
- **`tests/gate-integrity.sh` (target `test-gate-integrity`) now pins this and will fail you**
  if you: reintroduce a `command -v <tool>` branch or an `echo … skipping` into a Makefile
  *recipe*; make a bats target fail unconditionally (there is an effect-oracle assertion that
  the suite is actually reached, via a recording stub `bats`); or add a `plugins/*/tests/test-*.sh`
  that skips because an in-repo path is missing. `command -v` **platform** skips (the ~10
  non-macOS hdiutil/ditto/PlistBuddy ones) are still legal — that predicate means "not
  applicable", not "cannot verify". Its detector was validated against all four shapes; the
  `exit 0` must fall within 2 lines of the predicate (documented limit).
- **`make test` is green for everything this loop controls.** The one failure you may still hit is
  a pre-existing defect with its own story (**AGE-21**), not something you broke. The gate is
  live: **do not bypass it except under the evidence rule below.**
- **AGE-16 is FIXED — `session-stop.bats` no longer flakes, and that suite is now ~8s instead of
  ~107s.** If you see it red, it is something you broke.
- **⚠ The macOS first-exec trap that AGE-16 turned out to be — read this before you write any
  timed test.** macOS assesses a *freshly written* executable on its first exec (XProtect /
  syspolicyd): measured **12–43s** for a new shim script when `XprotectService` is saturated,
  ~0.05s for every exec after, and **0.004s for a copied binary**. Any bats assertion that times a
  region containing a shim's *first* exec is measuring that, not your code. This is what produced
  AGE-16's 5.68 / 11.28 / 27.46s "evidence" — the hook itself was a flat 5.01s the whole time.
  - Fix pattern (now in `session-stop.bats`): build shims **once per file** at a stable path via
    `setup_file`, read per-test values from the environment at run time, and warm each one with
    `SHIM_WARMUP=1` outside every timed region. Per-test shims cost ~107s a run; this costs ~8s.
  - **Relocating to `/private/tmp` does NOT help** — measured 25–41s, *worse* than `$TMPDIR`. The
    cause is first-exec assessment, not Spotlight, so the CLAUDE.md `$TMPDIR` /
    `.metadata_never_index` guidance does not apply. Warming is the only control that works.
  - Prefer an **effect oracle** over a clock reading wherever you can: assert a marker the command
    could only have written had it not been killed, not that `elapsed < N`.
- **`SKIP_PREPUSH_TESTS=1` was NOT needed by the AGE-16 session** — the gate passed on its own for
  the first time in three sessions (`MAKE_EXIT=0`, 572 bats assertions + 209 shell checks, zero
  failures, zero skipped suites, at v2.39.1). Treat a bypass as a red flag again, not routine. If
  you must bypass, run the full suite first, record the failing test names and why they are
  unrelated, and put that evidence in the PR body.
- **Capture full output when you run `make -k test`.** Piping it through `tail` hides which suite
  failed and costs you a second ~15-minute run — redirect to a log file instead. Expect ~15 min
  wall-clock, longer when another session is running its own suite concurrently.
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

**Still unresolved as of the AGE-18 session (2026-08-04):** issue #118 is still `OPEN` and its
worktree is still live, as is `age-117` (issue #117, also open). Nothing has merged, so the
collision is intact — AGE-6 is now queue row 5, which still buys several stories of runway before
it matters. Re-check `gh issue view 118` when you reach it rather than trusting this line.

### What AGE-14 turned out to be

AGE-14 as filed was **incomplete, not wrong**. Its stated cause (`story state add blocked`
colliding with a template that now ships `blocked`) was real but *unreachable*: the dominant
failure was that **storyhook 2.0.0 renamed `story project init` → `story project new`**, so every
fixture aborted in setup before `story state add` ever ran. 59 tests were red, not 6. The rename
was filed as **AGE-15** and landed in the same PR (council-ruled). Four boundary defects found
along the way were filed rather than fixed — see the new-stories list below.

### What AGE-16 turned out to be — the sharpest "the story can be wrong" case yet

AGE-16's filed root cause was **falsified**, and the evidence it cited was **misattributed** —
yet a real production defect was hiding underneath it. All three parts matter to the next session:

1. **The bound was never broken.** `run_with_timeout 5 story handoff` measured a flat **5.01s** in
   every call form, including the hook's exact one. GNU `timeout` group-kills, so the story's own
   `sleep 30` shim gets reaped and *cannot* reproduce the failure. The prescribed regression test
   would have been **vacuous** — passing identically before and after any fix.
2. **The 5.68 / 11.28 / 27.46s spread was the test harness, not the hook** — macOS first-exec
   assessment of freshly written shims (see the ⚠ block above). Line-level instrumentation put
   9.99s on a `tmux send-keys` shim whose body is one `echo`.
3. **A real, reachable defect was underneath anyway.** Capturing a bounded command through
   `$(...)` is unbounded whenever the command leaves a descendant that escaped the process group:
   the descendant inherits the pipe's write end and the substitution waits for it. Measured
   **30.05s against a 5s bound** — and 30.12s even when the shim itself exits 0 in 0.05s.
   Two council seats independently found the confirming evidence: storyhook auto-spawns
   `story … daemon --serve` with `process_group(0)`, and storyhook's own **SH-94** records a test
   binary blocked in `read(2)` for **four minutes** on a pipe that daemon held at fd 7.
   Fix: redirect to a temp file, read back with `$(<file)`. `--kill-after` does **not** help —
   SIGKILL targets the same group the descendant left. Council ruled it out unanimously after
   both seats that proposed it withdrew it.

**The transferable lesson:** the story's numbers were real but pointed at the wrong thing, and its
prescribed test would have proved nothing. Reproduce, instrument, and *attribute* before fixing —
`.council/age16-fix-scope/DECISION.md` has the full audit trail.

---

## The queue

Ordered by priority first, then constrained by the storyhook dependency graph. Do not reorder
without recording why in this file.

> **Reordered 2026-08-04 by the AGE-16 session, reason recorded as the rule requires.** AGE-11
> (`medium`) had been sitting ahead of AGE-18 and AGE-17 (both `high`), which contradicts this
> table's own priority-first rule; `story next` independently picks from the `high` pair. AGE-18
> led because it was the most foundational: while `make test` could exit 0 with `bats` absent, no
> green result from this loop meant what it claimed — including the one AGE-16 relied on.
>
> **AGE-18 landed 2026-08-04**, so that premise is now discharged: a green `make test` from here
> on is a real claim that every suite ran. AGE-17 inherits the lead as the remaining `high`. Rows
> renumbered; no other reordering.

| # | Story | Pri | Why here |
|---|---|---|---|
| ✅ | ~~**AGE-14** + **AGE-15**~~ | high | **DONE** — merged together as one PR. See "What AGE-14 turned out to be" above. |
| ✅ | ~~**AGE-16**~~ | high | **DONE** — the `blocks-ci` flake is gone. See "What AGE-16 turned out to be" below; its filed diagnosis was wrong in an instructive way. |
| ✅ | ~~**AGE-18**~~ | high | **DONE** — the gate now fails instead of skipping. See "What AGE-18 turned out to be" below; **no version bump was needed** (it touched no shipped `plugins/**`). |
| ✅ | ~~**AGE-17**~~ | high | **DONE** — the guard now validates two-token forms. See "What AGE-17 turned out to be" below. Shipped as **v2.40.0** (minor: additive JSON keys). Filed **AGE-24** and **AGE-25** on the way. |
| 1 | **AGE-11** | med | First of the three stories that edit `execution-loop.md` / `step-handoff.md`. Smallest of the trio — land it before the two that restructure those files. |
| 2 | **AGE-24** | med | **New, filed by this session. Pulled to the front of the medium block** — reason recorded as the rule requires: it is the *other half* of AGE-17, the guard still cannot catch the drift it exists to catch, and the context for it is fresher now than it will ever be again. **Read "What AGE-17 turned out to be" first** — and note its fix collides with a deliberate existing test. |
| 3 | **AGE-4** | med | Splits `execution-loop.md`. After AGE-11. |
| 4 | **AGE-5** | med | Rewrites around `step-handoff.md`. After AGE-11. |
| 5 | **AGE-6** | med | WS-C, rca realign. Independent. **Check `gh issue view 118` before starting** — see the scope collision above. |
| 6 | **AGE-12** | med | storywork claim diagnostic. Independent. |
| 7 | **AGE-21** | med | deployit's `test-cli-rm.sh` needs a live local daemon — the last known source of pre-push gate noise now that AGE-16 is closed. |
| 8 | **AGE-19** | med | No storyhook major-version pin. |
| 9 | **AGE-22** | med | Preventative guard for AGE-16's defect class — see below. |
| 10 | **AGE-10** | low | **Pulled ahead of its priority** — AGE-7 is `blocked-by` it, and storyhook will refuse to dispatch AGE-7 until it closes. |
| 11 | **AGE-7** | med | WS-D + the prompt-hygiene lint. Needs AGE-10 done. **On merge, also close AGE-8** (below). |
| — | **AGE-8** | low | **Do not work this story.** It is `obviated-by` AGE-7 and storyhook already excludes it from `ready`. When AGE-7 merges, close it: `story move AGE-8 done` with a comment pointing at AGE-7's PR. |
| 12 | **AGE-9** | low | Council-decision story, independent. |
| 13 | **AGE-13** | low | Council-decision story, independent. |
| 14 | **AGE-23** | low | Skill `references/*.md` are cited skill-relative but ship at plugin root — see below. **Confirmed live again this session:** the council skill's own `references/council-protocol.md` failed to resolve skill-relative and cost a wasted tool call. |
| 15 | **AGE-25** | low | **New, filed by this session.** AGE-17's own safety mechanisms are unproven — see below. |
| 16 | **AGE-20** | low | Deliberately deferred — land it alone, never beside a behaviour fix whose proof depends on those fixtures. |

**AGE-2, AGE-3, AGE-14, AGE-15, AGE-16 and AGE-18 are already `done`** — do not touch them.

### Unscheduled stories — slot these in

Filed rather than fixed, per the "defects become stories" rule. They are now placed in the queue
above; this table keeps the detail. **AGE-11 is next**; **AGE-24 follows it** and is the other
half of AGE-17.

| Story | Pri | What |
|---|---|---|
| **AGE-22** | med | **Filed by the AGE-16 session.** Preventative guard for AGE-16's defect class: nothing stops the next `$(timeout … cmd)` from being written. The repo is currently clean — `rca-repro.sh:25` and `greenlight-explore.sh:146` both already redirect to a file. Note a council seat reported greenlight as a sibling site; **the sweep disproved that**. Watch for AGE-17's trap when writing the guard: match the whole command, not the first token. |
| **AGE-23** | low | **Filed by the AGE-18 session.** Every plugin ships `references/*.md` at the **plugin root**, but each `SKILL.md` cites them as a bare relative `references/<topic>.md` — and a skill's runtime base directory is `skills/<name>/`, so the literal path does not resolve. Nothing is broken (agents recover by searching); it costs tool calls and context on every reference load, which for forge and rca is most invocations. Measured 3 wasted calls invoking `/council-vote` this session. Fix is a one-line convention decision applied repo-wide — see the story for three options. Relates to AGE-8. |
| **AGE-19** | med | No storyhook **major-version pin** anywhere. An upstream major surfaces as ~60 unattributable failures instead of one assertion. |
| **AGE-21** | med | `plugins/deployit/tests/test-cli-rm.sh` depends on a **live local deployit backend daemon** (`:8729`); when it is unavailable the test fails and blocks unrelated pushes. Passed 3/3 in earlier runs, failed once under contention from the `age-117` session, passed again immediately after. Same class as AGE-18 — a gate that does not mean what it says. |
| **AGE-24** | med | **Filed by the AGE-17 session.** `forge-contract-check.sh` extracts candidates ONLY from inside fenced ```` ``` ```` blocks (`:226`, `d==1`). Every `story ...` written as inline-backtick prose is invisible. **All eight `story project ` occurrences in the scanned docs sit at fence depth 0** — so even with AGE-17 landed, the guard would have caught NONE of the historical `project init` drift. ⚠ Its fix collides with a **deliberate** existing test (`forge-contract-check.bats:175` asserts inline signatures like `` `story relate <a> <relationship> <b>` `` are ignored), so widening must distinguish a concrete invocation from a placeholder signature. Not a one-liner. |
| **AGE-25** | low | **Filed by the AGE-17 session.** AGE-17's own safety mechanisms are unproven: (1) the monotone-safe `real_verbs` filter is unexercised by any input — zero non-verb tokens reach position 1 under synopsis-only harvest, so it catches nothing and no test covers it; (2) the "global help is the enforcement floor" invariant bounds the verb *domain* but not the *vocabulary* — per-verb help is a strict superset for `web` only, so a degraded `story help <verb>` costs `web` its `status` and would flag a doc using `story web status`. One-token false positive, invisible to the `>= 11` cardinality floor. |
| **AGE-20** | low | Ten duplicated storyhook fixture-creation sites across two plugins — why one upstream rename cost ten edits. **Deliberately deferred**: the 10th site is in a *different plugin*, so a shared helper is a new cross-plugin module boundary, not a mechanical extraction. Land it alone, never beside a behaviour fix whose proof depends on those fixtures. |

### What AGE-17 turned out to be — the story was RIGHT, and still not enough

Unusually for this loop, AGE-17's diagnosis was accurate as written and reproduced on the first
try: a fixture with `story project init`, `story project bogus` and `story hooks nonexistent`
yielded `contract_ok: true, verb_violations: []`. The fix landed as specified. But three things
are worth carrying forward:

1. **⚠ The fix does NOT close the hole it was filed for — AGE-24 does.** The guard scans only
   *inside* fenced blocks, and every one of the eight `story project ` occurrences in the scanned
   docs is inline-backtick prose at fence depth 0. So AGE-17 + AGE-24 together are what the F103
   guard needed; AGE-17 alone is half. This was found by a council seat and **verified
   independently before filing** — do not skip AGE-24 believing AGE-17 covered it.
2. **Neither ground-truth source is complete, so the union is forced — this is not a style
   choice.** `story --help`'s usage block is the ONLY source for `type add`, `state add`,
   `member add`, `store new`, `epic *`, `plugin *` (there is no `story help <verb>` topic for
   those five verbs at all). `story help web` is the ONLY source for `web status`. A single-source
   implementation either misses renames or **falsely flags working docs** — forge docs use
   `story type add` three times. The bats effect oracle asserts both halves precisely because
   that pair is unsatisfiable by any single-source implementation.
3. **`story help <verb>` output contains prose that looks like usage.** `story help hooks` line 4
   is the sentence "story events occur (create, state change, close, etc.)" — ordinary prose that
   wrapped onto a line starting with `story `. A naive harvest invents a verb named `events`
   (observed live). Closed by harvesting **synopsis regions only** (truncate at the first blank
   line), anchoring to the queried verb, and filtering candidates through `real_verbs` so any
   surviving prose can only widen a vocabulary, never narrow one.

**Design ruled by `/council-vote`** — unanimous on the decision (two-token depth, lenient
open-node leniency, additive schema), IRV majority on the implementation spec. Full audit trail
including the accepted dissent: `.council/age17-subcommand-guard/DECISION.md`.

### What AGE-18 turned out to be — and the two claims in it that were wrong

The core defect was real and reproduced on the first try (`PATH=/usr/bin:/bin make test-root-bats`
→ exit 0). Two of the story's supporting claims were not:

1. **"The runners need fixing too" — no.** All five runners (`tests/run-tests.sh` + four
   `plugins/*/tests/run-tests.sh`) *already* hard-fail with an actionable message. The Makefile
   wrapper never called them. So the fix was **deletion**, not a new guard: the conditional was a
   second, wrong copy of a policy that already had an owner one layer down. Deleting it also
   covers the direct `bash plugins/forge/tests/run-tests.sh` entry path, which a Make-level
   `require-bats` prerequisite could never reach — that argument is what made the council
   unanimous.
2. **"`forge-contract-check.sh`'s `exit 0` paths are the same class" — falsified.** That script's
   always-exit-0-with-JSON contract is documented and deliberate, and its only caller already
   asserts `.ok == "true"`, so a missing `story` CLI already turns it red. Changing it would break
   a documented contract and a deliberate test to fix nothing. Full disproof is a comment on
   AGE-18. **This matters for AGE-17, which touches the same file.**

**Two traps worth carrying forward:**

- **Never guard the gate at Make *parse* time** (`$(error)`/`$(shell)`). It makes `make -n test`
  non-zero, and the pre-push hook's detection (line 49) then falls through to *"no test command
  detected — skipping the gate"* — upgrading a partial vacuous green into a **total** one. Verify
  `make -n test` still exits 0 after any Makefile change.
- **A new helper script invoked from a recipe trips `tests/store-isolation.sh:24-27`**, whose grep
  demands the literal `with-isolated-store.sh bash` on every suite recipe line. Route anything new
  through the wrapper rather than editing that guard's exemption list.

Also fixed the one genuine sibling (`plugins/deployit/tests/test-cli-bump.sh` skipped when
`semver-cli` was absent — an in-repo path, so absence means a broken checkout; its runner counted
that exit 0 as PASS). And note the shape of the fix: when you write a test that asserts *failure*,
pair it with an **effect oracle** proving the thing still runs on the happy path — otherwise
`target: false` satisfies your test perfectly.

**Harness gotcha that cost this session two debug cycles:** the plain-bash test harness runs each
`test_*` fn under `set -e`. Both `cmd; rc=$?` (unchecked failing command aborts before the status
is read) and `[ cond ] && arr+=(x)` (a false trailing `&&` list is itself non-zero) silently abort
the function, reporting your assertion red against a *working* fix. Use `cmd || rc=$?` and a full
`if`.

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
- **Do not stop at "it was load" — attribute the time.** AGE-16 looked like load, then looked like
  a broken timeout, and was neither: it was macOS first-exec assessment inside the timed region
  (see the ⚠ block up top). Load average was a *correlate*, not the cause — a discriminating run
  showed the warmed hook flat at 5.11–5.13s under load 7–11 while a fresh shim's first exec in the
  same loop ranged 1.1–31.4s. If a timing assertion is red, instrument the script line by line and
  find out which command actually consumed the wall clock before believing anyone's theory,
  including the story's.
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
