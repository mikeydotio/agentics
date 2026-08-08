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
| **Next story** | **AGE-79** — *this session's child.* AGE-43's remainder bound is over-applied to non-backtick openers, so a dead relation goes silent. ⚠ **It is the half AGE-70's council deliberately DEFERRED 3-0, and the story carries five pre-registered counter-examples any candidate must clear FIRST** — three of them killed the candidate AGE-70's chair had already measured clean. It also carries a measured ladder of three candidates (one rejected, one partial, one leading-but-UNFALSIFIED), so do not re-derive it. Its characterization pin `AGE-79 pin` reds by design on a correct fix. **Deliberate skips, re-confirmed four times now:** AGE-39 is logged deliberate debt whose redesign trigger is unmet. ⚠ **AGE-62/63/64/65 need edits to `~/.claude/`, outside any repo — the loop CANNOT do them** (and a user session `age-62-18` was seen working AGE-62 directly). **AGE-66 needs Mikey.** ⚠ **AGE-72 is Mikey's** — every remedy changes what a live tailnet service runs. **AGE-74, AGE-75, AGE-77, AGE-79 and AGE-80 are takeable.** Confirm STATE with `story list --ready`. |
| **Completed this loop** | AGE-14, AGE-15 (one PR), AGE-16, AGE-18, AGE-17, AGE-11, AGE-27, AGE-33, AGE-28, AGE-32, AGE-24, AGE-31, AGE-29 (+ AGE-41, closed for free), AGE-30, AGE-12, AGE-21 (+ AGE-47), AGE-19, AGE-22, AGE-26, AGE-34, AGE-35, AGE-36 (+ AGE-62/63/64/65 filed), AGE-61 (+ **AGE-67 closed in the same PR**; AGE-66 and AGE-68 filed), AGE-43 (+ **AGE-69 and AGE-70 filed**), AGE-48 (+ **AGE-71 filed**), AGE-69 (+ **AGE-74 and AGE-75 filed**), AGE-70 (+ **AGE-79 and AGE-80 filed**; AGE-77 filed by its first, panicked sitting) |
| **Repo version** | **v3.7.4** — AGE-70 **bumped**, because it changed shipped `plugins/forge/bin/forge-contract-check.sh`. Four of the last five stories bumped, so **inherit nothing** — run the pathspec check yourself; the command is in the Known-state block below. |
| **Last updated by** | AGE-70 session, 2026-08-07 (restarted after a host kernel panic killed its first sitting) |
| **Carried debt** | **None owed to you, and the broken protocol step is FIXED.** `git switch main` works again, local `main` is current (20c31d2 → 3cdbfcd), and **step 10 no longer asks you to run it** — the release path is now decoupled from any local `main` ref. ⚠ **One worktree is deliberately still there**: `.claude/worktrees/dual-host-plugin-compatibility` holds **135 uncommitted files** of dual-host (Codex) plugin work that exists **nowhere else** — unpushed, uncommitted, idle since 2026-07-20. **Do not remove it.** It is filed as **AGE-66** for Mikey's decision. If you ever need it out of the way, the remedy is `git switch --detach <path>`, **never** `git worktree remove` — measured, detach preserves modified *and* untracked files. |

> Update this table **twice** per story: once when you claim it (status → IN FLIGHT), once when
> it merges (move it to Completed, set the next story). It is the first thing the next session
> reads.

### ⚠ Gate cost — every scalar below this line is superseded

**This file contains at least thirteen mutually contradictory statements of what `make test`
costs** — ~15 min, ~45 min, 478s, ~10.5 min, ~2h and ~4h all appear, several phrased as
directives ("budget for 2h", "a push costs ~2h"). They are the honest observations of the
sessions that wrote them, so they are left in place as history, **but none of them is guidance
any more.** AGE-36 measured the real distribution; it lives in **CLAUDE.md § "Gate cost"** and
that is the only place to quote.

The short version, measured 2026-08-05 from 107 recorded gate runs plus a direct probe:
**median ~630s post-AGE-35**, tail **censored at the hook's 900s timeout**, and the tail is
**load-driven** (all 12 breaches fall in one 28-hour window of this loop's own concurrency;
the 45 runs before it never exceeded 609s).

Two facts that change how you work:

- **A cancelled hook ALLOWS the push** — measured 12/12, including tag pushes `v3.0.0` and
  `v2.39.1` and a PR. If your push is slow, it may be going out **ungated**.
- **You cannot see the gate from inside your session.** A PreToolUse hook that exits 0 has its
  stderr discarded. AGE-32 inferred from a missing `pre-push-tests: running …` line that the
  hook was not firing; it was firing. **Do not repeat that inference.** `make -k test` yourself
  and read your own result — which is what this loop has always actually done.

`tests/gate-deadline.sh` now makes the suite refuse before the cancellation point. If it stops
you, it prints **"BUDGET, NOT CORRECTNESS"** and exits **3** (never 1 or 2). That is not a test
failure: re-run once on a quiet box, and if it fires again add the timing to **AGE-64** rather
than working around it. The budget cannot be raised — it is derived from a value this repo does
not own.

⚠ **The hook also over-fires on inert text (AGE-63), and it will happen to you.** It greps the
whole command string, so a commit message, story description or heredoc body that quotes a push
invocation costs a full suite run before your `git commit` or `story new` executes. It fired
three times on this session that way. `SKIP_PREPUSH_TESTS=1` is legitimate for a command that
demonstrably pushes nothing — say so when you use it.

---

## Known state (updated 2026-08-07 by the AGE-70 session)

- **AGE-70 is DONE and shipped as v3.7.4. AGE-79 — its own child — leads the queue.** It changed
  shipped `plugins/forge/bin/forge-contract-check.sh`, so the bump was owed.
- **⚠ THIS SESSION WAS A RESTART. A HOST KERNEL PANIC KILLED THE FIRST SITTING MID-COUNCIL, AND
  THE RECOVERY RULE IS WORTH KEEPING.** The crash landed between "measured the problem" and
  "decided what to do": one commit (a PROGRESS.md claim), a clean tree, and a council with
  `QUESTION.md` + measurements but **no proposals, no votes, no DECISION**. Nothing needed
  reverting. What the second chair did instead — and would do again — was **re-measure every
  claim from scratch before reusing any of it**. All 12 fixture rows reproduced exactly, which
  earned the prior evidence its place; but the prior ladder table was **wrong in one cell**
  (82/1 recorded for variants that actually score 81/2). **Inherit a crashed session's
  conclusions only after re-deriving them.**
- **⚠⚠ THE BIGGEST LESSON, AND IT IS ABOUT WHERE A RULE LIVES, NOT WHETHER IT IS RIGHT.** The
  chair built a candidate that passed the real corpus, the whole 83-test suite, 21 hand-built
  rows and a cost probe. A seat tasked with attacking it killed it in one round with **five
  counter-examples**, three of them **outright regressions against shipped**, one leaving the
  defect *itself* unfixed, and one needing only two ordinary English apostrophes
  (`it's` … `'AGE 1'`). The rule that survived:

  > **The same span grammar is SAFE in the splitter and UNSAFE in the bound.**

  Inside a fence the unit is the whole LINE (AGE-24), so the input is **prose with shell embedded
  in it**, and every grammar strong enough to parse the shell also misparses the English —
  `don't` is not an open quote. What differs is the *consequence*: in the splitter a misparse
  **merges two tokens** and the guard still reports (loud, local); in the bound it **truncates**
  before the slot, `is_placeholder("")` returns 0, and the guard reports **GREEN**. That is four
  derived rules refuted by construction in this repo now (AGE-69's enumerated class, AGE-43's
  bound, backtick parity, and this one). **Not carelessness — each was a sound statement about
  shell, evaluated over text that is not shell.**
- **⚠ A CHARACTERIZATION PIN THAT ASSERTS EQUALITY TO A WRONG VALUE IS A MUTANT'S ALIBI.** This is
  the single most transferable test finding here, and it indicts a convention this file has been
  recommending. AGE-70's own pin asserted `relation == "next"` — *the value the bug produces*. So
  reverting the fix scored **82 ok / 1 not ok, byte-identical to a correct fix**: the pin did not
  merely fail to detect the regression, it **certified** it. A characterization pin must assert
  the wrong behaviour in a way a *correct* fix reds — prefer pinning **absence/presence** or
  naming the story so the red is self-explaining, and re-check any pin whose value equals a
  defect's output.
- **⚠ "STRUCTURALLY UNVERIFIABLE" DESERVES ONE MORE MEASUREMENT.** The council's own mutation
  battery ruled the subcommand call site unpinnable (index 0, `is_placeholder` leading-only) and
  measured a revert at byte-identical 82/1. That was right about *displacement* and wrong about
  the reported **token**: `story project ne"w x"` reports `ne"w` shipped and `ne"w x` fixed,
  because a span opening **mid-word** is not leading. The arm now kills that mutant.
- **The mutation battery that shipped** (isolated repo copy, filtered runs, **baseline arm first**
  — 9/9, without which every verdict is vacuous): remove the closes-later guard → CAUGHT by 3
  arms incl. AGE-69's own; revert the relation slot → CAUGHT by 3; revert the subcommand slot →
  CAUGHT by 1; off-by-one index → CAUGHT by 6; delete the fast path → **MISSED, and correctly so**
  (it is behaviour-neutral by design); one-character error in the fast-path class → CAUGHT by 2.
- **⚠ A PER-CHARACTER BASH SCAN IS QUADRATIC, AND THE FIX IS FREE.** `${s:i:1}` is O(i). Measured
  on a 21 KB unit: 3.10s shipped → **21.30s** unbounded, and **34.60s** through a prefix walk. The
  council's first remedy was a *length budget with a degradation path*; the chair measured that
  **unnecessary** — passing the wanted index down and stopping there restores it to at-or-below
  shipped (3.49s). A budget that silently degrades to a different bound is a second code path with
  **no arm pinning which one ran**. Longest real corpus unit: **488 chars**, so this is latent.
- **⚠ COUNCIL SEATS NEED THE RIGHT TOOLS, NOT JUST THE RIGHT ROLE.** The first sitting seated
  `skeptic` (Read/Grep/Glob only) as the challenger. The second swapped in
  `hypothesis-challenger`, which carries **Bash** — and that seat's counter-examples are the whole
  reason this story shipped the scope it did. **If a seat's job is to falsify, it must be able to
  execute.**
- **A 10-MINUTE TOOL TIMEOUT WILL KILL A MUTATION BATTERY MID-RUN.** It happened here (again).
  Because the battery ran against an isolated **copy**, the working tree was never at risk — that
  is the whole reason for the rule. Use `bats --filter` to run only the discriminating arms; a
  full-suite run per mutant does not fit.

## Known state (updated 2026-08-06 by the AGE-69 session)

- **AGE-69 is DONE and shipped as v3.7.3. AGE-70 leads the queue.** It changed shipped
  `plugins/forge/bin/forge-contract-check.sh`, so the bump was owed. Run the check yourself:
  `git diff --stat origin/main HEAD -- plugins/ ':(exclude,glob)plugins/*/tests/**'
  ':(exclude,glob)plugins/**/*.bats' ':(exclude,glob)plugins/*/README.md'` — **non-empty means bump.**
  ⚠ You do not have to run it blind: `make -k test` names the drifted file outright.
- **⚠⚠ AGENT NAMES ARE SESSION-GLOBAL AND LATEST-WINS. TWO OF THREE COUNCIL SEATS WERE SILENTLY
  RENAMED AT SPAWN, AND MY FIRST PINGS WOKE STALE AGENTS FROM PREVIOUS COUNCILS.** This is the most
  transferable thing in this session and it nearly corrupted the record. `Agent(name: "seat1-architect")`
  returned `name: seat1-architect-2` because an earlier session had claimed the bare name; the same
  for `seat3-skeptic`. `SendMessage` to the **bare** name then routes to the **old** agent. Both
  replied with **well-formed, high-confidence JSON about entirely different questions** — one about
  `.storyhook/` path bans, one about AGE-35's deployit capture flake — and **both volunteered
  fabricated claims about votes they had "already cast in this council"**, including a specific
  ballot letter. Nothing in the payload flags the substitution. **Always address a seat by the
  `name` the spawn result returned, and read every delivery for QUESTION IDENTITY before tallying
  it.** Cheapest fix: give seats story-scoped names (`age70-seat1`) so the collision cannot arise.
- **⚠ THE STORY WAS RIGHT IN SHAPE AND TOO NARROW IN CONTENT — and the widening was the whole
  value.** AGE-69 listed three glue characters. Measured on the shipped script, the class is:

  | Slot | Members | In the story? |
  |---|---|---|
  | subcommand | `)` `;` `` ` `` **`.` `:` `"` `'`**, and **`);` (two at once)** | only `)` `;` `` ` `` |
  | relation | `)` `;` `.` | **no — the story never mentions the relation slot** |
  | verb | `.` `-` `_`, via the capture group's OWN class, not the harvest | **no — different mechanism, filed AGE-74** |

- **⚠ THE COUNCIL KILLED AN ENUMERATED DELIMITER SET TWICE, AND THE REASON GENERALISES: A
  HAND-PICKED CHARACTER LIST IS UNPROVABLE, A DERIVED RULE IS SOUND.** What shipped is
  `[!A-Za-z0-9]` — *"a token that could equal a member must END IN AN ALPHANUMERIC, so trim until
  it does"*. Three independent measurements killed enumeration:
  - **CRLF.** A wholly correct CRLF document reports `new)^M` under **every** enumerated set ever
    proposed here — byte-identical to no fix at all, because CR is not a character anyone
    enumerates. Worse: it mangles the **positive controls** too (`init` → `init^M`), so on a CRLF
    file every reported token is unsatisfiable by any `expect-dead` marker and **the whole
    suppression mechanism silently dies**.
  - **Soundness.** All **97** derived vocabulary members end alphanumeric (48 verbs, 8 relations,
    41 subcommand members; charset exactly `[a-z-]`, hyphen never trailing). So no trailing strip
    can turn a non-member INTO a member — a false negative is **not constructible**. A seat's
    search for a counter-example failed and was honestly reported as failed.
  - **Bash.** A `]` moved out of first position inside a **variable-expanded** class does not
    narrow the class, it **VOIDS it entirely** — silently, exit 0, gate green. Every enumerated set
    is one character-reorder from a no-op strip. (Literal `]`-first in `[[ ]]` is a *loud* syntax
    error; the variable form is the silent one, and it is the form both enumerated proposals
    needed.)
- **⚠ THE ARM THAT NO PROPOSAL ORIGINALLY CARRIED IS THE ONE THAT MATTERS, AND IT IS THE
  TRANSFERABLE TEST LESSON.** AGE-43's over-fix arm is **blind** to a one-character error in the
  new rule. `[!A-Za-z]` (also stripping digits) is byte-identical on `baz)qux,foo;bar`, on every
  per-array pin, on the AGE-70 pin, **and on the real 29-file corpus, which stays green** — while
  `new2` and `blocks2` **VANISH from the violation set**, because their stems are live vocabulary.
  That is a **false negative**. So the arm asserts those rows are **PRESENT**, making it a
  false-negative detector rather than a token-value pin. **Mutation M9 is caught by that arm and
  by nothing else in an 83-test suite.**
  - **The framing worth stealing: pins should BRACKET a rule, not describe it.** **CEILING** =
    AGE-43's mid-token arm (reds on a strip not confined to the trailing edge); **FLOOR** = the
    CRLF arm (reds on any narrowing back to an enumerated set); **BOUNDARY** = the digit-terminal
    arm (reds on a one-character class error). Describing the rule would have passed all three
    mutants.
- **Mutation battery: 11 arms, 10 mutants, ALL CAUGHT; baseline 83 ok / 0 not ok; restore
  `cmp`-verified byte-identical.** Run in an **isolated repo mirror** rather than the real tree —
  worth copying, because a first attempt against the real tree hit the 10-minute tool timeout and
  was killed mid-run (the trap did restore correctly, but that was luck you should not need).
  ⚠ **Two council predictions were measured DOWN by the battery**: seat 1 predicted the quoted-`!`
  mutant would be caught by the digit arm *alone* (measured: **26** tests), and seat 2 predicted
  verb-slot creep would be caught by the verb pin *alone* (measured: **12**, because the corpus arm
  had been hardened). **Only M9 is genuinely alone.** A prediction of uniqueness is worth checking.
- **⚠ THE HARDENED CORPUS ARM IS A REAL FIX, NOT DECORATION.** The pre-existing real-corpus test
  asserted only "no token carries a backtick" and `files_scanned >= 25`. Both are **blind** to the
  one over-reach this fix makes reachable: extending the strip to the verb slot yields
  `contract_ok:false` with violation `<id` **and destroys the live `<id>` suppression** (dropping
  `suppressions` to `["HP-N"]`). It now asserts `contract_ok == true` and the exact suppression set.
- **Filed: AGE-74** (med) — the verb capture group absorbs trailing `. - _`. ⚠ **The obvious fix
  reds the real corpus**, per above, because `verb_slot_is_wildcard` tests a **balanced** `<...>`
  while `is_placeholder` is **leading-only**. It also **migrates tokens between violation arrays**
  (`relate.`→`blockz` moves verb→relation). **AGE-75** (med) — a doc copying storyhook's **own
  `--help`** verbatim is reported as a violation (`story hooks install|uninstall|list|test`):
  `harvest_usage_rows` splits position 2 on `|` when *deriving*, the checker never does. Unaffected
  by any trailing strip, and neither AGE-69 nor AGE-70.
  **AGE-76** (low) — **this loop leaks immortal waiter processes, and 13 were alive on the box.**
  `until ! pgrep -f "make -k test"` can never exit, because the loop's own argv contains the
  pattern. PROGRESS.md already recorded the *stall*; what nobody noticed is that the stalled
  waiters **outlive the session** — three inspected still reference `/private/tmp/age36-gate.log`.
  Wait on a captured PID or a sentinel file, never a command-name pattern.
- **Gate: green with no bypass, fifteen sessions running.** Pre-bump run isolated the drift guard as
  the ONLY red (669 bats ok / 0 not ok; 328 shell PASS / 1 FAIL); post-bump `MAKE_EXIT=0` with
  **669 bats ok / 0 not ok and 329 shell PASS / 0 FAIL**.
- **⚠ `gate-deadline` FIRED ON THE PUSH, AND THE CAUSE WAS ENTIRELY FOREIGN LOAD — the documented
  "re-run once" worked.** First push attempt refused at **721s of a 720s budget** with
  *"BUDGET, NOT CORRECTNESS"*, exit 3, **no test failed**. Load average was **57.6**, and none of it
  was this session: an **iOS Simulator was booting** and **204 `diskimages-helper` processes** were
  alive. Waiting for the 1-minute load to fall under 20 and retrying pushed cleanly first time.
  **If this fires on you, measure the load before assuming it is your change** — and note the
  suite had already run fully green twice on the identical tree, which is AGE-64's duplication
  being paid for in wall-clock.
- **GitHub releases had drifted again: v3.7.2 was tagged but never published.** v3.7.3 is published
  with **rolled-up notes covering both**. Nothing was pruned — the drift memo suggests pruning
  skipped tags during a large catch-up, but only one tag was involved here and `v3.7.2` is
  referenced throughout `CLAUDE.md` and this file, so deleting it would be destructive for no gain.
  **Check `gh release list` against `git tag` at the end of your story; the bump does not do it.**
- **AGE-23 confirmed for the NINTH time.** The council plugin's `references/` resolve at plugin
  root, not skill-relative.

## Known state (updated 2026-08-05 by the AGE-48 session)

- **AGE-48 is DONE and shipped as v3.7.2. AGE-69 leads the queue.** It changed shipped
  `plugins/deployit/bin/deployit-cli`, so the bump was owed. Run it yourself:
  `git diff --stat origin/main HEAD -- plugins/ ':(exclude,glob)plugins/*/tests/**'
  ':(exclude,glob)plugins/**/*.bats' ':(exclude,glob)plugins/*/README.md'` — **non-empty means bump.**
  ⚠ You do not have to run it blind first: `make -k test` tells you outright.
  `test-plugin-content-drift` names the drifted file and says "VERSION is still X".
- **⚠ THE STORY'S EXTENT WAS REFUTED, AND THE REAL HARM WAS WORSE THAN THE ONE IT NAMED.** AGE-48
  said a leaked `DEPLOYIT_SKIP_GC_PUSH` makes push-asserting tests "wholly vacuous — every
  assertion goes green while nothing is pushed". Measured:

  | Claim | Verdict |
  |---|---|
  | Push-asserting tests go vacuous under a leak | **False** — `test-cli-rm.sh` fails `rm not pushed to origin`; `test-cli-rm-pr-fallback.sh` (which has **no** precondition guard) fails `expected index_pending` |
  | `published:True` on a path that touches no remote | **Confirmed** |
  | Consequence | **Worse than filed** — a real removal and a hatch removal produced **BYTE-IDENTICAL stdout**, serve dir irreversibly deleted in both |

  AGE-21 had already closed the vacuity hole downstream. **Take the 10 minutes to reproduce before
  believing an Extent section** — that is now five stories running where the story was partly wrong.
- **⚠ THE BACKEND FORWARDS THE WHOLE ENVIRONMENT, so this was never test-only.**
  `deployit-backend:_run_cli_rm` spawns the CLI with `env={**os.environ, ...}` and forwards the
  payload verbatim to the HTTP client. The web UI's swipe-to-delete is a live production reader of
  the field that was lying.
- **⚠ A GREEN GATE CANNOT PROVE THIS ONE FIXED, AND IT IS STRUCTURAL — SAY SO RATHER THAN CLAIMING
  THE PATH.** `deployit-backend:466-467` runs `<state>/_plugin_root/bin/deployit-cli`, never repo
  code, while `test-backend-delete.sh:20` **symlinks** `_plugin_root` at the repo — so the suite
  always exercises current code and can **never** detect a stale daemon.
- **⚠ THE COUNCIL SAID "COPY". I MEASURED IT AFTER THE MERGE AND IT IS A SYMLINK INTO A
  VERSION-GATED CACHE — WHICH MAKES THE GAP BIGGER, NOT SMALLER.** Filed as **AGE-72**:

  | | |
  |---|---|
  | `_plugin_root` | symlink → `~/.claude/plugins/cache/agentics/deployit/**2.36.0**` |
  | Repo | **v3.7.2** |
  | Deployed CLI carries AGE-48's fix | **no** — 0 matches; and 1 match for the old lie |
  | `~/.deployit` | **does not exist** — probing it says "never bootstrapped" while a daemon is loaded from `~/Library/Application Support/deployit` |

  So **AGE-48's fix is merged and the production path it was about is still running the defect.**
  `/deployit redeploy --source <repo>/…` would repoint that symlink and deliver **1.5 majors** of
  accumulated deployit change to a live tailnet service at once — materially more than "apply this
  fix", so **the loop did not run it**; AGE-72 carries the options for Mikey. **`readlink` the
  `_plugin_root` and grep the resolved CLI before claiming any deployit fix is live.**
- **⚠ TWO NAMES WERE ARGUED FOR, ADOPTED, AND THEN MEASURED DOWN — AND ONE WAS REFUTED BY ITS OWN
  AUTHOR AFTER TWO SEATS HAD ALREADY CONCEDED TO IT.** Seat 1 proposed `_index_change_is_durable()`
  on a measured argument the chair confirmed; Seats 2 and 3 **both conceded**; then Seat 1 refuted
  itself: `_reset_index_to_origin_main` is a **`git reset --hard origin/main`** and the hatch never
  `git commit`s, so the hatch's write is an **uncommitted** working-tree change that the next
  non-hatch call destroys — durable only while the var stays set. **A concession is not a
  measurement.** Had the chair taken the two concessions at face value this would have shipped a
  misleading name inside a fix about a misleading name. `_index_change_is_effective()` shipped.
- **⚠ THE PREDICATE MUST BE TOTAL OVER `dict | None`, AND NO SINGLE PROPOSAL HAD BOTH HALVES.** B
  pinned `unrecognised → False`, C pinned `None → False`; the chair carried both. `None` is
  **reachable, not theoretical** — `cmd_gc`'s `mutate` returns it on a no-op and `test-gc.sh:67`
  drives exactly that path.
- **⚠ ADDING A DEPLOYIT TEST REDS `test-deployit-capture-diagnostics`, AND THAT IS THE GUARD
  WORKING.** AGE-35's guard derives-then-pins its membership precisely so a new file cannot join the
  run set unclassified. It printed the diff and the instruction ("Re-derive"). The new file measures
  **`LLNNNN`**; candidate set 35 → **36**, covered 18 → **19**. **Budget ~150s for the re-derive and
  do not skip it** — a file that lands there unclassified is the vacuity this repo has shipped twice.
- **⚠ AGE-63 FIRED ON A FIXTURE'S LOCAL `git push` INTO A `mktemp -d` BARE REPO** and cost a full
  suite run before a read-only probe executed. `SKIP_PREPUSH_TESTS=1` was legitimate there and is
  recorded as such. It happens to every session that builds a git fixture.
- **Council: proposal B at the FIRST count of the runoff (B=2, C=1, A=0), after a 0-1-2 round 1 in
  which — for the THIRD consecutive council — NO seat voted for its own proposal.** In the runoff
  **A finished last on two of three ballots including its author's**, and Seat 3 ranked its own
  proposal **last** after conceding both points that distinguished it. Every seat revised; none
  stood. Full trail: `.council/age48-published-lies-under-skip-gc-push/DECISION.md`.
  - ⚠ **Chair technique worth copying:** when concessions went **circular** on the token (each seat
    conceded to a different neighbour, so nobody defended the word they wrote), the chair named the
    circularity in the deliberation prompt and forbade a second concession. Both remaining seats
    then *decided* rather than deferred, and reached the same answer by different arguments.
  - ⚠ **The protocol has no amendments.** Seat 3's assertions could only reach the outcome by each
    seat putting them in its **own** proposal. Say so in the deliberation prompt or the best test
    design on the panel dies with a losing proposal.
- **⚠ A NEW `make test` FLAKE, AND IT COST ONE GATE RUN — `hdiutil: create failed - Resource busy`.**
  `test-cli-stage-macos-no-sparkle-tools.sh` red on a branch whose **entire diff was one line of
  PROGRESS.md**, a file it does not read; **3/3 PASS** on immediate retry, with two full green runs
  the same day on far larger changes. Filed as **AGE-73**: `deployit-cli:1367` passes
  `-volname meta_full["project"]`, and **nine** deployit tests share the literal `"Lillist"`, so they
  contend on the machine-global `/Volumes/Lillist` — a per-test `mktemp -d` isolates the image path
  but **not** the volume name, which is why the isolation looks complete and is not. Same family as
  **AGE-56** (fixed ports) and **AGE-57** (fixed path in a variable), and **a third reason not to
  parallelise the runner to shorten the gate.** ⚠ Filed with the mechanism **inferred, not
  reproduced** — a pre-registered discriminating experiment is in the story. **If this reds on you,
  retry the single file before believing it is yours.**
- **Filed: AGE-72** (med) — see the topology block above; **needs Mikey, not the loop.**
- **Filed: AGE-71** (low) — `_wait_for_health:2646` returns bare `True` under `DEPLOYIT_SKIP_VERIFY`,
  the class's only other member. Scoped honestly as low: the value never escapes the process, gates
  a `fail()` rather than an irreversible delete, and its caller re-reads the same var five lines
  later. **Repro not run** — filed on inspection and recorded as unconfirmed.
- **AGE-23 confirmed for the EIGHTH time.** The council plugin's `references/` resolve at plugin
  root, not skill-relative.

## Known state (updated 2026-08-05 by the AGE-43 session)

- **AGE-43 is DONE and shipped as v3.7.1. AGE-48 leads the queue.** It changed shipped
  `plugins/forge/bin/forge-contract-check.sh`, so the bump was owed — the last four stories were
  all test/docs-only, so **do not inherit "no bump" from them**. Run it yourself:
  `git diff --stat origin/main HEAD -- plugins/ ':(exclude,glob)plugins/*/tests/**'
  ':(exclude,glob)plugins/**/*.bats' ':(exclude,glob)plugins/*/README.md'` — **non-empty means bump.**
- **The story was RIGHT — its diagnosis, its one-token fix, and its two recorded cautions all
  held.** That is unusual in this loop and worth saying plainly. What the story got *wrong* was
  only its **Extent**, and the omission was the most useful finding of the session (below).
- **⚠ THE DEFECT ALSO INVERTED THE GUARD'S ONLY ESCAPE HATCH, AND THE STORY NEVER MENTIONED IT.**
  A mangled token defeats the token-bound `expect-dead` marker. Measured, both directions:

  | `expect-dead` marker names | SHIPPED | FIXED |
  |---|---|---|
  | `init` — the correct, typeable token | `stale: token_mismatch`, **violation stands** | suppressed correctly |
  | ``init` `` — the mangled token | **suppressed** | `stale: token_mismatch`, fails loud |

  So an author who named the right token got a **false diagnosis of substitution drift**, and the
  only marker that worked named a token carrying a stray backtick nobody would guess. Two council
  seats found this independently; the chair confirmed it. Both directions are now pinned, because
  the mechanism was **inverted rather than merely broken** and a one-directional arm would miss a
  regression that flipped the other half. The 2 live corpus suppressions name `HP-N` and `<id>`,
  neither backtick-bearing, so **nothing existing migrates**.
- **⚠ BOUNDING `START_RE` THE SAME WAY IS WRONG, AND ITS OWN PROPOSER PROVED IT.** A seat proposed
  it, then rebuilt the variants and refuted its own premise ("bounding START_RE cannot lose a true
  positive"). Measured, fixture = plain column-0 fence:

  | case (dead relation `precedes`) | SHIPPED | scope A (shipped fix) | scope C (bound both) |
  |---|---|---|---|
  | ``story relate `AGE-1` precedes AGE-2`` | red | **red** | **GREEN** |
  | ``(story relate `AGE-1` precedes AGE-2)`` | red | GREEN | GREEN |
  | same lines without backticks (control) | red | red | red |

  A backticked entity in slot 0 pushes the relation to slot 1, and the bound truncates before it.
  The `is_placeholder` "leading backtick is a wildcard" argument covers the **subcommand** slot
  (token 0), **not** the relation slot (token 1). **No seat voted for scope C in either round**,
  and **M5 of the mutation battery reds the suite if you re-introduce it** — the scope ruling is
  executable, not merely documented.
- **⚠ AN ALL-GREEN FIXTURE ASSERTS NOTHING, AND THE PER-ARRAY PIN IS WHY.** "No reported token
  contains a backtick" is **trivially true of an empty array**, and under the fix every
  false-positive fixture goes green — so the invariant fixture must also carry **dead grammar as
  positive controls**. Stronger, measured by the winning seat: blanketing `is_placeholder` to
  return 0 empties `subcommand_violations` and `relation_violations` **while leaving
  `verb_violations` intact**, because the verb slot routes through `verb_slot_is_wildcard`, a
  *different function*. So a **combined length floor is satisfiable with a whole slot dead**
  (1 verb + 2 subcommand + 0 relation clears a floor of 3), and a **flat token set cannot see a
  token migrating BETWEEN arrays** — which is exactly what AGE-70's fix will produce. Pin **per
  array** or the guard is blind in the one direction this backlog will actually move.
- **⚠ THE WINNING PROPOSAL DISCLOSED A HOLE IN ITSELF AND THE CHAIR CLOSED IT.** No proposal's
  assertion detected an **over-fix**: widening the bound to ``[^`);|&]*`` leaves every pinned
  array and the backtick count identical. The shipped suite adds the missing arm — a span whose
  content legitimately carries `;` and `)`, pinning the reported *token* (`foo;bar`, `baz)qux`)
  rather than the array shape. Mutation M3 reds it.
- **⚠ MY OWN MUTATION BATTERY MANUFACTURED FIVE FALSE "CAUGHT"s ON ITS FIRST RUN.** It pointed
  bats at `"$SRC.bats"` where `$SRC` already ended in `.sh`, so every arm ran against
  `forge-contract-check.sh.bats` — a file that does not exist — and dutifully reported the
  resulting error as the mutation being caught. **The baseline arm is what disclosed it** (it read
  `0 ok, 1 not ok` when it should have read `7 ok, 0 not ok`). Same family as AGE-35's vacuous
  sweep. **A battery without a baseline arm is not a battery.** Corrected: **5 run, 5 caught**,
  baseline 7/0, tree `cmp`-verified byte-identical after every restore.
- **⚠ THE SCRATCHPAD COLLISION FROM AGE-35 HAPPENED AGAIN, IN A SECOND SESSION.** A council seat
  overwrote the chair's `$SCRATCHPAD/probe.sh` with its own harness mid-session. Nothing was lost
  (the chair's measurements were already banked in the transcript), but the AGE-35 lesson stands
  and is now **twice-observed, not anecdotal**: `mktemp -d` *inside* the scratchpad, never a fixed
  name — your subagents share that directory with you.
- **Council: UNANIMOUS 3-0 at the FIRST count of the runoff, after a 0-1-2 round 1 in which NO
  seat voted for its own proposal's scope winner.** **Two of three seats ranked their OWN proposal
  LAST.** Seat 3, which had named vacuity as the decisive axis, then built a *narrower* mutation
  than the one put to it (disarm the relation check only → 1+2+0 = exactly 3) and showed **its own
  floor was the only mechanism of the three that failed that axis**. It also withdrew both of its
  grounds against the winning pin, concluding they had refuted the *flat join* and the *shared
  fixture*, neither of which the winner still proposed. Full trail:
  `.council/age43-midre-trailing-backtick-scope/DECISION.md`.
  - ⚠ **Chair deviation worth copying:** proposals were labelled **P1/P2/P3**, not A/B/C, because
    the *answer space* was already named scope A/B/C and reusing the letters would have made every
    ballot ambiguous. If a council's options are already lettered, re-label the proposals.
- **Filed: AGE-69** (med) — delimiter-glue: a closing delimiter glued to the harvested token
  reports valid docs as violations; members are the ``)``-glued and ``;``-glued tokens **and the
  START_RE trailing-tick residue**. ⚠ Note `sub="${sub%,}"` already strips exactly ONE such
  character, a trailing comma — the class was known and handled for `,` alone, and that is the
  precedent to generalise. **AGE-70** (med) — slot-displacement: the relation slot is validated by
  a fixed index, so a quoted span displaces it; includes the **false negative this fix knowingly
  bought**. Cut on **MECHANISM, not anchor**, which is what makes them separately fixable — an
  anchor-based cut puts one mechanism in both stories. Both are pinned by characterization tests
  naming their story IDs; **a correct fix REDS those pins by design.**
- **AGE-23 confirmed for the SEVENTH time.** The council plugin's `references/` resolve at plugin
  root, not skill-relative.

## Known state (updated 2026-08-05 by the AGE-61 session)

- **AGE-61 is DONE, and it closed AGE-67 in the same PR. No bump — the repo stays at v3.7.0.** It
  touched only `CLAUDE.md`, `PROGRESS.md`, `.gitignore` and one untracked file. Verify before
  assuming it applies to you: `git diff --stat origin/main HEAD -- plugins/
  ':(exclude,glob)plugins/*/tests/**' ':(exclude,glob)plugins/**/*.bats'
  ':(exclude,glob)plugins/*/README.md'` — **empty means no bump.**
- **⚠ THE WARNING THIS FILE CARRIED ABOUT THE WORKTREES WAS FALSE, AND IT WOULD HAVE MISLED YOU IN
  THE DANGEROUS DIRECTION.** `PROGRESS.md:23` said *"do not blind-delete the four worktrees — two
  hold unmerged feature branches."* Measured with `rev-list --count origin/main..HEAD`:

  | Claim | Verdict |
  |---|---|
  | Two worktrees hold unmerged feature branches | **False** — **all four** branch tips had **0** commits not in `origin/main` |
  | Blind deletion is unsafe | **True — for a completely different reason** |

  The real hazard was never an unmerged branch. It was **135 uncommitted files** in
  `dual-host-plugin-compatibility`, which no branch-merged test can see. A session that had trusted
  the stated reason would have checked merged-ness, found all four clean, and deleted the lot.
  **Check the working tree, not just the branch.**
- **⚠ THE STORY'S OWN FIX DIRECTION NAMED THE WRONG REMEDY.** AGE-61 says *"removing that single
  worktree is likely sufficient and lowest-risk."* Removal is **not** lowest-risk. Measured in a
  fixture, both topologies: `git switch --detach <worktree>` frees the branch while preserving
  modified **and** untracked files, so it is strictly safer and does the same job. Removal is
  irreversible and, applied to `dual-host`, would have destroyed AGE-66's only copy.
- **⚠ THE RESIDUE HAD A STRUCTURAL CAUSE NOBODY HAD LOOKED FOR, AND A COUNCIL SEAT FOUND IT BY
  NATURAL EXPERIMENT.** `.claude/scheduled_tasks.lock` was the **only** tracked file under
  `.claude/`, swept into the index by `8d9f6fe` (v2.14.0). Git materializes a tracked file into every
  new worktree; a scheduler sweep deletes it *there*; and both reclaim tools act only on `removable`
  (`issue.sh:940`, `story.sh:579-580,642`). So the worktree became **permanently unreclaimable by
  the verb that exists to reclaim it**. The discriminating evidence: `age-117` and `age-118` were
  stuck at ` D .claude/scheduled_tasks.lock`, while **`age-AGE-2`, whose copy survived intact, was
  still classified `removable`**. Untracked here; `--cached`, so the live file stays on disk.
  - ⚠ **Scope it as the council forced: 2 of 4, not 4 of 4.** `age-AGE-2` was clean *and* removable
    and lingered anyway, so *"nobody ran the reclaim verb"* is an **independent** cause this does not
    address. Seat 1 made that scoping a condition of its vote.
- **⚠ A GATE GUARD WAS DESIGNED, COSTED, VOTED FOR, AND WITHDRAWN BY ITS OWN AUTHOR — and the reason
  is the transferable result of this session.** `tests/worktree-hygiene.sh` would have red when a
  linked worktree held `refs/heads/main`. What killed it was **not** cost: the QA seat corrected the
  chair's "red for 105 commits and ~23 stories" framing to *red **once**, cleared by one safe
  command*. What killed it is that **this repo's guards exist to convert SILENT failures into loud
  ones** (AGE-18, AGE-21, AGE-27, AGE-33, the fail-open hook, the bounded call that *looks* bounded),
  and this failure is already loud and self-naming — verified in a fixture:
  `fatal: refusing to fetch into branch 'refs/heads/main' checked out at '<path>'`, printing the
  offending worktree path **verbatim**, with the detach remedy following directly from it. A guard
  would convert a fatal that names its own cause into an earlier fatal.
  - **Pre-registered trigger that would make it right after all** (deferred against a signal, not
    declined on taste — the agentics#33 posture): a **second** observed capture of `refs/heads/main`
    by a linked worktree, or any future step reintroducing a local-`main` dependency such as the
    `git fetch origin main:main` form. **That form is the one command the residue still breaks** —
    step 10's `git fetch origin main` is immune, measured.
- **Step 10 is rewritten and no longer touches `main`.** Nothing needs a local `main`: a tag ref is
  repo-global, merge-commit-only preserves the branch SHA, `cmd_validate` (`semver-cli:969`) reads no
  branch, and `git grep -E 'switch main|checkout main|pull --ff-only'` matches **no repo code**. The
  stale `push origin --delete <branch>` line is gone too — `delete_branch_on_merge: true` means
  `gh pr merge` already removed it.
- **Council: C won outright at the FIRST count (C=2, B=1, A=0) — and for the second time in this
  loop, NO seat's own proposal was its own top choice.** Seats 1 and 2 both ranked the QA seat's
  proposal above their own; the QA seat ranked its own **second**. **Proposal A finished last on all
  three ballots including its author's**, after the QA seat produced a measurement refuting A's
  central empirical claim and Seat 1 accepted the refutation rather than defend it. All three seats
  revised during deliberation, and all three converged on the same shape. Full trail:
  `.council/age61-stale-worktrees-durable-half/DECISION.md`.
- **Filed: AGE-66** (med) — the `dual-host` worktree's 135 uncommitted files, which exist nowhere
  else; **needs Mikey's decision, not the loop's**. **AGE-68** (low) — 29 of 31 local branches are
  merged residue; ⚠ the sweep must exclude `fix/AGE-3-semver-post-bump-hooks-skipped`, which is
  ahead=1 and may be the only copy of that commit.
- **AGE-23 confirmed for the SIXTH time.** The council plugin's `references/` resolve at plugin root,
  not skill-relative. It costs a tool call every single session; it is `low` and never gets picked.
- **⚠ `${PIPESTATUS[0]}` DOES NOT WORK IN THE BASH TOOL** — it runs zsh, where the array is
  `$pipestatus` and is 1-indexed. A `cmd | tail; echo EXIT=${PIPESTATUS[0]}` line printed an **empty**
  exit code, which reads as success. Same family as the `for x in $VAR` word-splitting trap already
  recorded here: **if a shell idiom silently produces nothing, suspect zsh before believing the
  result.**

## Known state (updated 2026-08-05 by the AGE-36 session)

- **AGE-36 is DONE. No bump — the repo stays at v3.7.0.** It touched only root `tests/`,
  `Makefile`, `.gitignore` and docs. Verify before assuming it applies to you:
  `git diff --stat origin/main HEAD -- plugins/ ':(exclude,glob)plugins/*/tests/**'
  ':(exclude,glob)plugins/**/*.bats' ':(exclude,glob)plugins/*/README.md'` — **empty means no bump.**
- **⚠ BOTH PRIOR READINGS OF THIS STORY WERE WRONG, IN OPPOSITE DIRECTIONS.** AGE-32 filed it
  ("the hook may not be firing at all"); AGE-35 commented that the premise "does not hold" (478s,
  comfortably inside budget). Measured:

  | Claim | Verdict |
  |---|---|
  | `make test` takes ~2h | **False** — 107 recorded runs: min 311s, median 467s (pre-AGE-35), **630s measured today** |
  | The hook may not be firing | **False** — an inert probe did not execute for **10m31s**; `ps` caught the hook and its `make test` child throughout |
  | Comfortably inside budget | **False** — **12 of 107 runs (11.2%) were cancelled at exactly 900 000 ms** |

- **⚠ THE GATE FAILS OPEN, MEASURED 12/12 — this is the real defect and it is filed as AGE-62.**
  Every cancelled run was followed by `is_error=False` and the command executing: tag pushes
  **`v3.0.0`** and **`v2.39.1`**, a branch push, and **PR #156** all went out with *no test verdict
  at all*. A cancelled PreToolUse hook never returns the exit 2 that blocks.
- **⚠ YOU CANNOT SEE THE GATE FROM INSIDE YOUR SESSION, AND THAT IS WHAT MISLED AGE-32.** A
  PreToolUse hook that exits 0 has its **stderr discarded**. So a missing `pre-push-tests: running …`
  line is *not* evidence the hook did not run. **Do not repeat that inference.** The transcripts are
  the instrument: Claude Code records every hook run as an attachment with `durationMs`, and
  `timedOut: true` + `timeoutMs` when cancelled — 1 966 transcripts, 636 gate runs, mined in one pass.
- **⚠ THE TAIL IS LOAD-DRIVEN, NOT SIZE-DRIVEN, AND THE REGIME SPLIT IS THE WHOLE POINT.** A council
  seat found it and the chair confirmed it: **45 runs before 2026-08-04 → max 609s, ZERO breaches.
  62 runs inside the 08-04→08-05 window → 12 breaches.** Suite content barely changed. The variable
  is **this loop's own concurrency** — sessions hand-running `make -k test` while gates run. That is
  filed as **AGE-64**, and it is AGE-34's bequest (`PROGRESS.md:150-152`) finally taken up.
  ⚠ AGE-34 is closed and **cannot be commented** (`story` refuses), so the cross-reference lives in
  AGE-64's description instead.
- **⚠ THE CHAIR'S OWN REPRICING WAS REFUTED BY THE SEAT THAT SUPPLIED IT.** The chair argued the
  measured 630s median made a deadline too likely to fire. Seat 3 showed the **new-harm window is
  only the 60s band [840s, 900s)**: a run that would have taken 950s is not *newly* blocked — it was
  already being cancelled-and-allowed silently. **A higher median makes the fail-open more routine
  and the deadline more necessary, not less.** Council was **unanimous 3-0 on the first count** for
  C. Full trail: `.council/age36-prepush-gate-scope/DECISION.md`.
- **⚠ THE NEW GUARD ALMOST BLOCKED EVERY PUSH, AND ONLY RUNNING IT CAUGHT THAT.**
  `tests/gate-deadline-guard.sh`'s inert case assumed the ambient process tree had no
  `pre-push-tests.sh` ancestor. Under the real gate that is false, so it armed and refused with
  `elapsed 4s of a -99099s budget`; `make test` went red and the hook blocked the command. **A test
  that pins activation must not depend on ambient activation state** — every case now pins a per-pid
  sentinel marker, verified **19/0 standalone and 19/0 beneath a real hook ancestor**.
- **⚠ `bounded-capture-guard` RED ON THIS WORK, AND THE PIN WAS NOT THE THING TO CHANGE.** It flagged
  three new "bounded call sites": a **Python** local named `timeout` inside a `python3 -c` string
  (×2) and this guard's own regex literal `(timeout|gtimeout)`. All three are AGE-26's rule one level
  deeper — a shell-syntax detector reading embedded Python and a quoted pattern. Fixed by **renaming
  the Python local to `declared` and building the alternation from a variable**, so the census
  returns to exactly three with the pin untouched. If it reds on you, find the token before touching
  the pin.
- **⚠ THE HOOK OVER-FIRES ON INERT TEXT (AGE-63) AND IT WILL HAPPEN TO YOU.** It greps the *whole*
  command string, so a commit message, story description or heredoc body quoting a push invocation
  costs a full suite run before your `git commit` or `story new` runs. **It fired three times on this
  session that way.** 11 of 107 historical runs (10.3%) gated nothing at all.
  `SKIP_PREPUSH_TESTS=1` is legitimate for a command that demonstrably pushes nothing — say so when
  you use it, which is what the new breadcrumb makes auditable.
- **What shipped:** `tests/gate-deadline.sh` + `tests/gate-deadline-guard.sh`
  (`make test-gate-deadline-guard`). The suite refuses **before** the hook is cancelled, so the
  platform's silent allow becomes a loud exit-**3** block. Activation is by **process ancestry** (the
  hook sets no env var, and `[ -t 1 ]` cannot separate the gate from this loop's own redirected
  hand-run); the budget is **derived** from the hook's declared timeout, never copied. ⚠ Two traps
  are pinned as fixtures: `settings.json`'s **first `timeout` is 5, not 900** (a positional resolver
  blocks every push), and `CLAUDE_SETTINGS_OVERRIDE` **replaces** the chain rather than prepending,
  or the guard reads live machine config. **Mutation battery: 7 run, 7 caught.**
- **The deadline has a named removal trigger: AGE-64.** It exists only while the duplicated-gate load
  does. Its second claim — that the budget sits below the platform's cancellation point — is
  **disclosed, not guarded**: lowering the hook's timeout makes it inert and nothing here can detect
  that (same call `bounded-capture-guard.sh` makes in its "Deliberately not covered" header).
- **Filed: AGE-62** (high) fail-open, **AGE-63** (med) over-firing matcher, **AGE-64** (med)
  instructed duplication, **AGE-65** (med) SPEC for the attestation inversion. ⚠ **All four need
  changes to `~/.claude/`, which the loop cannot make** — surfaced to the user instead.
- **⚠ UNVERIFIED SECURITY REPORT, RELAYED NOT CONFIRMED.** A council seat reported a plaintext `ghp_`
  GitHub token in `~/.claude/settings.json`. The chair's attempt to scan that file for
  credential-shaped values was **correctly blocked by the safety classifier**, and the chair did not
  work around it. Flagged to the user; do not treat it as a finding of this session.
- **The gate was green with NO bypass — fourteen sessions running.** `MAKE_EXIT=0`, **654 bats `ok`
  + 685 shell PASS, zero `not ok`, zero shell FAIL, zero make errors, 5 bats plans**; the new
  `gate-deadline-guard` reports 19/0 inside the full run. (Two `FAIL` grep hits are `ok` lines whose
  *test names* contain the word.)
- **⚠ THAT RUN TOOK 2 229s (37m09s), AND IT IS THE BEST EVIDENCE IN THE WHOLE STORY.** Same commit,
  same machine, same day as the 630s solo probe — but **two foreign suites were running
  concurrently** (`storyhook/.claude/worktrees/SH-50`, `scad-caliper`, confirmed by `lsof` on their
  cwds). **A 3.5x multiplier from load alone, and 2.5x over the entire 900s budget.** Had that been
  a gate run it would have been cancelled and the push allowed silently. Neither foreign run was in
  *this* checkout, so AGE-56/AGE-57 were not implicated. **If you time this suite, record what else
  was running or your number means nothing** — that is precisely how AGE-32 and AGE-35 reached
  opposite wrong conclusions.
- **⚠ `pgrep -f 'make -k test'` MATCHES ITS OWN WAITER — it cost this session three ten-minute
  stalls.** A `until ! pgrep -f 'make -k test'; do sleep; done` loop has that string in its own
  argv, so it always finds itself and never exits, while `ps -o etime=` on the first match reports
  the *waiter's* age and looks plausible. **Wait on a captured PID** (`while kill -0 "$pid"`), not on
  a command-name pattern. Same family as the zsh word-splitting trap already recorded here.
- **AGE-23 confirmed for the FIFTH time.** The council plugin's `references/` resolve at plugin root,
  not skill-relative.

## Known state (updated 2026-08-05 by the AGE-35 session)

- **AGE-35 is DONE. No bump — the repo stays at v3.7.0.** It touched only
  `plugins/deployit/tests/`, root `tests/`, `Makefile` and docs. Verify before assuming it applies
  to you: `git diff --stat origin/main HEAD -- plugins/ ':(exclude,glob)plugins/*/tests/**'
  ':(exclude,glob)plugins/**/*.bats' ':(exclude,glob)plugins/*/README.md'` — **empty means no bump.**
- **⚠ THE FLAKE WAS NOT REPRODUCED, AND THIS PR DID NOT FIX IT. It shipped OBSERVABILITY.** Say this
  plainly if anyone asks: nothing here changes the probability of recurrence, so **a future red is
  not a regression from this work**. Filed as **AGE-59** *before* closure, per the council. 0/30 solo
  runs, `make test-deployit` 50/50, a full `make -k test` green, and 29 twin probes across that gate
  (max 0.14s at peak load 11.79) bound the per-run rate only to **~10% by the rule of three**. The
  load/timeout theory is **UNREPRODUCED — not "unsupported", not refuted** — and remains the
  *leading* candidate, because every `fail()`-reachable path in this test lies in `_derive_base_url`.
  The chair wrote "refuted" in its brief; all three seats corrected it. **AGE-59 pre-registers the
  discriminator**: if the recovered `display` names the 5s tailscale timeout the theory is CONFIRMED
  for that event, anything else REFUTES it. Its closing condition is a captured diagnostic from a
  real recurrence or an explicit accept-the-risk — *never* "it hasn't fired in N runs", which is what
  has left AGE-49 open and rotting.
- **⚠ THE STORY'S OWN EXPLANATION WAS WRONG, AND THE REAL DEFECT WAS DETERMINISTIC.** AGE-35 blamed
  the pre-push hook's `tail -40`. Measured: `test-bootstrap-dirs.sh:16` captured the CLI under
  `set -e`, and `deployit-cli`'s `fail()` prints its diagnosis to **stdout** — so the shell died at
  the capture with the diagnosis sealed in `$out`: **0 bytes on stdout AND stderr**. A full log is
  equally empty. Line 17's guard, written for exactly that case, was **unreachable**. But do not
  over-claim as the chair first did: a traceback or an assertion failure at lines 19-37 *would* have
  printed and then been dropped by the window, so **both losses are real and undiscriminated** —
  neither may be recorded as the cause of 2026-08-04.
- **⚠ THE FIX SET CANNOT BE FOUND BY READING SOURCE: 9 files by census, 12 by measurement.** The
  defect has four invocation shapes and only the first is visible to a regex — plain
  `out=$(python3 …/deployit-cli …)`; **array-bound** (`test-cli-rm.sh:87`); **function-bound**
  (`test-cli-preflight.sh:50` `out=$(run_preflight)`); **output-discarded**
  (`test-release-tag-exists-omits-target.sh:28` `… >/dev/null` in a bare-called function). Every miss
  is AGE-34/AGE-57's variable-binding blind spot. `tests/deployit-capture-diagnostics.sh` is
  therefore **behavioural**: inject a `fail()`-shaped failure at the k-th CLI call, k=1..6, and pin a
  per-file verdict string (`L` explained / `H` expected-and-handled / `N` fewer than k calls / `S`
  silent). **`S` is never acceptable; `L`→`H` is a swallow-fix and reds by design.** ~140-170s,
  `make test-deployit-capture-diagnostics`.
- **⚠ MEMBERSHIP MUST BE DISCOVERED, NOT ASSUMED — the chair's own first draft was vacuous and a
  mutation caught it.** Iterating the pinned list and comparing the result to that same list is
  self-consistent, so deleting a row deletes it from both sides and passes. **Mutation M2 walked
  straight through it.** The k=1 sweep now runs over **all 35 candidates** independently. This is
  Seat 3's self-exclusion objection — the insight that decided the council — reappearing inside the
  implementation of the fix for it.
- **⚠ `for x in $VAR` DOES NOT WORD-SPLIT IN zsh, AND IT MANUFACTURED A FALSE GREEN.** The Bash tool
  runs zsh, where unquoted *parameter* expansion is not split (unlike `$(…)`, which is). A
  verification loop written `for n in $COVERED` ran **once**, with `$n` bound to the whole list and a
  nonsense path — reporting "18 files, 0 silent, **0s**" when nothing had run. A council seat hit the
  identical fault the same session and honestly reported a failed measurement rather than a number.
  **If a sweep reports an implausibly fast clean result, suspect this before believing it.** Use
  `$(cat file)` or an array. The chair's retracted "<1s for 18 files" was this; the honest cost is
  ~140-170s.
- **⚠ A FIXED PATH IN THE SESSION SCRATCHPAD IS SHARED WITH YOUR OWN SUBAGENTS.** A council member
  overwrote the chair's `$SCRATCHPAD/shim3/python3` with its own copy, silently invalidating a whole
  sweep (its shim expected a different env var, so every file reported NO-FIRE). Same class as
  AGE-34, one level up. **`mktemp -d` inside the scratchpad**, don't name a fixed subdir.
- **⚠ DO NOT RUN TWO MUTATION BATTERIES AT ONCE.** A duplicate battery launched against the same
  tracked files and the kill left `test-bootstrap-dirs.sh` carrying mutation M3 and the guard
  carrying M5. Both were restored from backups and verified, but a battery that mutates *tracked*
  files must be the only one running — `git status` after every battery, and keep the per-mutation
  backup until the restore is `cmp`-verified.
- **Mutation battery: 5 run, 5 caught**, each asserted APPLIED before its run and `cmp`-verified
  byte-identical after restore. M1 revert-a-guard, M2 drop-a-manifest-row (the one that found the
  vacuity), M3 swallow-fix, M4 candidate-set-grows, M5 shim-stops-matching. ⚠ M5 also makes the guard
  **very slow** — an unmatched shim means all 35 candidates run to completion instead of dying at
  their first CLI call; it is caught by the oracle arm, but budget for it.
- **⚠ A NEW `make test` TARGET MUST GO THROUGH `tests/with-isolated-store.sh`.** The first draft's
  recipe did not, and `tests/store-isolation.sh` greps `^\t.*\bbash (tests/|plugins/)` with only two
  exemptions — it would have red the gate. Caught before the gate ran, but only by reading that
  guard.
- **The gate is ~10.5 min, and `make test` alone measured 478s (8 min) — not the ~2h AGE-36
  asserts.** Recorded as a comment on AGE-36 as a *data point, not a refutation* (one green run on an
  idle box). It does remove "the pre-push hook SIGTERM'd the run mid-suite" from AGE-59's candidates.
- **Council: UNANIMOUS 3-0 for P1 in the runoff, after a 2-1-0 round 1 in which every seat again
  voted against its own proposal.** Seat 2 withdrew its own helper refactor on a **circularity it
  found in its own argument**; Seat 3 withdrew scope A once the gate cost turned out to be 8 minutes;
  Seat 1 rebuilt its proposal around the two things that beat it. Seat 3's first preference was
  **conditional** on the bounded `run-tests.sh` re-echo being re-attached — it was, at 12 lines per
  failing test, because the inline diagnostic sits ~40 lines from the end and whether a red gate
  explains itself was otherwise **order-dependent on the failing file's alphabetical position**. Full
  trail: `.council/age35-deployit-bootstrap-flake-diagnostics/DECISION.md`.
- **Filed: AGE-59** (med) — the unexplained flake, with the pre-registered discriminator and closing
  condition above. **AGE-60** (low) — the guard classifies only paths a run *executes*, so untaken
  branches, the 17 candidates that never fire, and sites past k=6 are uncovered; redesign trigger
  stated in advance. Also **do not "improve" the guard by running all 50 deployit tests** — the 15
  excluded files spawn 14 more fixed-port backend servers against still-open **AGE-56**, so narrowing
  is a *safety* property.

## Known state (updated 2026-08-05 by the AGE-34 session)

- **AGE-34 is DONE. No bump — the repo stays at v3.7.0.** It touched only `plugins/**/*.bats`
  (excluded from the shipped pathspec), root `tests/`, `Makefile` and docs. Verify before assuming
  it applies to you: `git diff --stat origin/main HEAD -- plugins/ ':(exclude,glob)plugins/*/tests/**'
  ':(exclude,glob)plugins/**/*.bats' ':(exclude,glob)plugins/*/README.md'` — **empty means no bump.**
- **⚠ THE STORY'S ROOT CAUSE WAS REFUTED, AND ITS SYMPTOM WAS EXACTLY RIGHT.** AGE-34 says the suite
  "takes snapshots of the **real repository working tree**". It never touches it — `run_in_repo`
  (`:29-31`) and the one other invocation (`:60`) both `cd` into a per-test `mktemp -d`, and that is
  the complete enumeration of the file's `run bash -c` sites.

  | Story said | Measured |
  |---|---|
  | Snapshots the real working tree | **False** — 2 invocation sites, both `mktemp -d` fixtures |
  | Concurrent runs fail spuriously | **True** — 37 failures over 4 concurrent runs x 3 rounds |
  | Cause is concurrent working-tree churn | **False** |
  | Cause is `forge-integrity.bats:26`'s `rm -rf "/tmp/forge-integrity"` | **Confirmed** |

- **⚠ THE CONTROLLED EXPERIMENT IS THE WHOLE STORY, AND IT IS CHEAP — DO THIS INSTEAD OF ARGUING.**
  One bats run whose **only** concurrent actor was a loop doing `rm -rf /tmp/forge-integrity` — no
  second suite, no second fixture tree, no working-tree churn at all — failed **14/19** and
  reproduced the story's reported symptom *verbatim* (`jq: parse error: Invalid numeric literal at
  line 1, column 70`). Solo baseline 19/19. That single run refuted the filed cause and proved the
  real one in about a minute, where two full `make test` runs would have cost ~4h and proved less.
- **⚠ THE TOGGLE-BACK IS A MERGE GATE NOW, and it was the council's demand, not the chair's idea.**
  Proving a cause *sufficient* does not prove it *sole*. Post-fix, the exact configuration that had
  produced 37 spurious failures produced **0** (12 runs, 20/20 each). Without that second
  measurement the fix ships looking green while a second hazard survives. **Run the toggle-back
  whenever you fix a flake.**
- **⚠ THE BLAST RADIUS IS MACHINE-GLOBAL, WHICH IS WHAT DISQUALIFIED THE STORY'S OWN PREFERRED FIX.**
  `/tmp/forge-integrity` holds the live baselines of *every* project on the box, keyed by a digest of
  each project's absolute path. So `make test` here deleted the baseline of a real forge session in
  **another repository**. A repo-level `make test` lock (the story's option 1) cannot reach that.
  - **Correction the council forced on the chair, and it matters:** that does **not** make the lock
    "wrong". It remains valid as **AGE-36's** duplicated-gate fix. It is *not the fix for this
    defect*. Do not cite AGE-34 as having killed it.
- **⚠ `ok:false` HAS NO CONSUMER ARM — filed as AGE-55, and it is a live production disarm.** With
  its snapshot gone, `check` emits `{ok:false, error:"no_snapshot_for_phase_X"}` with **no
  `tampered` key** (`forge-integrity.sh:227`). `execution-loop.md` Steps 3a and 5a enumerate arms
  only for `tampered` true/false, so a null matches none and the natural reading is "proceed".
  Deliberately **not** fixed here (two hats, and the council mandated narrow closure).
- **⚠ NO SOURCE-LEVEL GUARD — proposed, and declined unanimously, on a decidability argument.** An
  `rm`-shaped predicate fires on `greenlight.bats:295`, which hands `'echo $(rm -rf /tmp/foo)'` to a
  jq encoder as **data** that never executes, while `forge-integrity.bats:30` is a quoted string that
  **is** executed. Same shell syntax, opposite kind — **AGE-26's rule, not AGE-22's.** It would also
  miss the class's other live members, which are a fixed *port* (AGE-56) and a fixed path bound to a
  **variable** (AGE-57). What replaces it: `tests/forge-integrity-isolation.sh`, **bidirectional on
  purpose** — deleting the teardown line altogether satisfies "the foreign sentinel survived" while
  trading a clobber for an unbounded leak, so a second arm pins that the suite still removes its own
  subtree.
- **⚠ SWEEP WITH `git ls-files`, NEVER AN EXTENSION GLOB — the chair's sweep missed AGE-57 TWICE.**
  First by filtering on `\.(bats|sh)$` when `plugins/*/tests/fakes/*` are tracked and
  **extensionless** (the exact blind spot `bounded-capture-guard.sh`'s header already documents);
  then, on a re-run without that filter, because the literal is bound to a **variable**
  (`STATE="${FAKE_TMUX_STATE:-/tmp/issue-faketmux}"`) rather than written at a call site. Miss (2) is
  itself the evidence that killed the guard proposal.
- **Mutation battery: 5 run, 5 caught**, every mutation asserted APPLIED and every restore asserted
  tracked-and-clean. M1 (blanket rm — the original defect) reds the over-delete arm; **M2 (no-op
  teardown) reds the under-delete arm, which is the whole justification for making the guard
  bidirectional**; M3 (key derivation drift) and M5 (wrong root) red the under-delete arm *and* the
  new bats pin. ⚠ A first attempt at M4 died on `perl` quoting and the battery **refused to report a
  result** — assert the mutation applied, or its red proves nothing.
  - **M4 corrected a council claim.** A seat called the `rmdir` reclaim "polish rather than safety";
    replacing it with `rm -rf` reds the over-delete arm. The non-recursive form is load-bearing.
- **⚠ THIS PR CLOSES AGE-34 NARROWLY — concurrent `make test` in one checkout is STILL NOT SAFE.**
  The council was explicit: claiming full closure would make this PR the same "gate that does not
  mean what it reports" failure the repo has already filed three times. **AGE-56** (deployit binds
  **14** hardcoded ports, two of them the same 18733, plus a fixed `/tmp/deployit-500.body`) and
  **AGE-57** are independent causes of the identical headline symptom and remain open.
- **⚠ STORYHOOK STORE OUTAGE — RESOLVED before this session ended; nothing is owed to you.** The
  store recovered on its own (the concurrent storyhook session presumably finished), and every
  pending operation was then completed: **AGE-34 is `done`** with its merge SHA, **AGE-36's false
  premise is corrected by comment**, and **AGE-58 is filed**. The record below is kept because the
  *failure mode* is worth knowing, not because anything is outstanding. Mid-session the shared store
  went to **schema 9** while `~/.local/bin/story` is **2.0.0** and reads only to schema 8, so for
  roughly an hour every `story` command failed with `daemon could not start … status 5`. Cause was
  not this repo: a concurrent session working `/Volumes/Code/mikeyward/storyhook` (an `SH-63`
  worktree, running its own `make test`) migrated the real global store.
  - **The reusable lesson: `make test` here was unaffected, and that is not luck.** Every suite runs
    under `tests/with-isolated-store.sh`, which builds a fresh schema-8 store of its own — verified
    by running `test-storyhook-contract-root` green *during* the outage. If a future session sees
    `story` fail, **check whether the gate is actually affected before treating it as a blocker**; it
    almost certainly is not.
  - **Do not "repair" this.** `story update` replaces its own running binary and is the user's
    machine-global tool. The chair declined and surfaced it to the user instead. Waiting was the
    correct move and it worked.
  - Flagged to the user as an incident worth a storyhook-side story: a session working that repo
    migrated the developer's **real** store rather than an isolated one, which is the same class as
    the 2026-07-30 event `with-isolated-store.sh` exists to prevent.
- **Council: UNANIMOUS 3-0 for C at round 1, and the seat that wrote C voted AGAINST it first.**
  Seat 3 cast A on the grounds that A alone had *measured* the key-derivation equality rather than
  asserting it, then reversed to C unprompted, "on the merits, not for consensus", once the chair had
  banked A's measurements across the record. Both ballots are preserved. The council also falsified
  two chair claims and corrected a miscount (13 → **14** deployit ports). Full trail:
  `.council/age34-forge-integrity-shared-snapshot-root/DECISION.md`.
- **Filed: AGE-55** (med) — the `ok:false` disarm above. **AGE-56** (med) — deployit's 14 fixed ports
  + fixed `/tmp/deployit-500.body`; latent today because the runner is strictly serial, and a trap
  for anyone parallelising it to shorten the ~2h gate. **AGE-57** (med) — `issue` and `storywork`
  fake tmux shims both default to one shared `/tmp/issue-faketmux`, and storywork's copy carries the
  *issue* plugin's name; filed on inspection, **repro not run**, recorded honestly as unconfirmed.
  **AGE-58** (low) — `forge-integrity.bats` asserts `[ ! -d "/tmp/etc" ]`, a machine-global *read*:
  any unrelated process creating that directory reds it permanently while naming the wrong cause,
  and it would also pass if the snapshot were never written. Same class as AGE-34, opposite
  direction — a false **red** from reading shared state where AGE-34 was a false green from writing
  it. Fix is a positive containment assertion using the `snapshot_dir_for_test` helper AGE-34 added.
- **AGE-23 is confirmed for the FOURTH time and still costs a tool call.** The council plugin's
  `references/council-protocol.md` did not resolve skill-relative; it lives at the plugin root.

## Known state (updated 2026-08-04 by the AGE-26 session)

- **AGE-26 is DONE and shipped as v3.7.0. AGE-34 leads the queue.** It changed shipped
  `plugins/greenlight/**`, so the bump was owed — run the pathspec check yourself rather than
  assuming which case you are in:
  `git diff --stat origin/main HEAD -- plugins/ ':(exclude,glob)plugins/*/tests/**'
  ':(exclude,glob)plugins/**/*.bats' ':(exclude,glob)plugins/*/README.md'` — **non-empty means bump.**
- **⚠ THE CHAIR'S OWN VERB ENUMERATION WAS WRONG, AND IT WAS THE MOST USEFUL ERROR OF THE SESSION.**
  The brief listed "44 top-level verbs" harvested from `story help --all`. That is the help-**topic**
  index, not the command surface. All three council seats caught it independently. Measured:

  | Source | Count | Wrong how |
  |---|---|---|
  | `help --all` headings | **45** (not 44) | 4 are **not commands** (`states`, `storage`, `json-format`, `relink`) |
  | `story help` Usage block | **48** | omits `context`, `sync-git` |
  | Reality | **≥50** | `context` and `sync-git` execute and are in **neither** |

  The two verbs missing from the chair's list were **`plugin`** (`story plugin install <target>`
  installs third-party code) and **`store`** (`story store new <path>` writes a store file at an
  arbitrary path) — the two most dangerous on the surface. **A table built from that list with a
  fail-OPEN default would have auto-approved arbitrary code installation, inside the very PR whose
  purpose was to stop auto-approving dangerous verbs.** That is why the default is fail-closed, and
  why **no completeness guard exists**: a guard is impossible when the CLI cannot enumerate itself.
- **⚠ THE STORY REFUTED TWO CLAUSES OF THE STALE PREMISE AND MISSED THE THIRD.** AGE-26 says the
  store is global and un-revertible (true). The premise's third clause — *"never touches system
  state"* — is falsified verbatim by `story update`: *"atomically replaces the running executable."*
  Also unlisted by the story: `story project new` writes `.storyhook.toml` **and `AGENTS.md`** into
  the cwd (measured in a fresh `git init`), `story web start` binds the machine's **Tailscale IP**,
  `story github-sync` pushes to GitHub Issues, and `story tui` would hang an unattended session.
  Counter-measured: **`story scaffold` writes NO file** — all three variants emit to stdout and the
  directory listing is byte-identical before and after. Three seats verified that independently;
  the natural assumption is false. Same for `report --html`, `context`, `export`, `load-context`.
- **⚠ THE DECIDING FACT WAS IN THE PLAN EXPLORER, AND THE BRIEF NEVER LOOKED THERE.** Measured 7/7
  under `GREENLIGHT_PLAN_EXPLORER=1` **before** the fix: `story purge --force`,
  `story project delete --force`, `story update --force` and `story plugin install evil` all
  returned **allow**, with the reason string *"plan exploration: readonly/safe command"* — while
  `git push origin main`, `rm -rf /tmp/x` **and `bash -c 'story purge …'`** were all **denied** in
  the same sandbox. Wrapping the command made it MORE restricted than typing it bare. The sandbox
  had exactly one hole and it was this.
- **The shipped rule, and it is mechanical — apply it to a verb you have never seen.** ALLOW iff the
  worst case is a wrong story RECORD in the current project, repairable by another `story` command.
  **Return 2 ONLY if `is_known_destructive` already ranks an equivalent operation at 2 by command
  name**, with the peer named in a comment at the arm. Everything else, including every unrecognised
  verb, returns 1. Bucket 2 is exactly five: `purge`, `project delete` (peer `rm|rmdir|unlink|shred`),
  `update`, `plugin install|uninstall` (peer `apt|brew|yum|dnf|pacman`).
  - The peer rule is **self-limiting** — bucket 2 cannot grow without someone first editing
    `is_known_destructive`, a far louder act — and it is why **no rename of `any_destructive` was
    needed**: if every `story` verb at 2 mirrors an existing 2, "destructive" is already the right
    word and no calibration ambiguity forms. That property is what won the vote.
- **⚠ `delete` IS ALLOWED AND `purge` IS NOT — that is storyhook's design, not a judgement.**
  `delete` is a soft tombstone `reopen` undoes; `purge` **refuses a story that was not soft-deleted
  first**. So gating `purge` alone gates the entire irreversible path at zero cost to the reversible
  one. Do not "tidy" this into a single rule.
- **⚠ THE EXTRACTOR MUST FOLLOW `is_safe_git`, NEVER `is_safe_gh` — and the story's own fix
  direction pointed at the wrong one.** storyhook accepts global flags **before** the verb and two
  of them **take a value** (`--store-path <file>`, `--project <slug>`). `is_safe_gh`'s `$(i+1)` form
  reads `--json` as the verb; a flag-skipper that does not consume values reads the **path** as the
  verb. Both misreads are silent. Verified `story --json purge ABC-1` returned **allow** pre-fix.
- **⚠ A NARROWING GUARD WAS PROPOSED, VOTED FOR, AND WITHDRAWN BY ALL THREE SEATS — do not rebuild
  it.** It would grep shipped docs for "verbs an agent is told to type". Measured: the **only**
  occurrences of `story purge` and `story project delete` in shipped `plugins/**` were
  `greenlight.sh:484-485`, **inside greenlight's own comment describing this defect** — so the guard
  would have read the sentence documenting the bug as a **mandate to keep `story purge` allowed**,
  while reporting green. The AGE-11 rule inverted.
  - **The transferable rule, and it is the sharpest result of the session:**
    `bounded-capture-guard.sh` is sound because a `timeout` call is **shell syntax in a shell file**
    — a decidable predicate over a formal grammar. `story purge` in a markdown skill is **prose**.
    They look like the same shape and are not; the difference is whether the corpus is a **language
    or a document**. A guard over a document needs a corpus test, which needs its own corpus test.
  - What replaces it: the allowlist pin asserts **SET EQUALITY**, which is bidirectional — deleting
    `move` reds it exactly as adding `purge` does. **A second test was never needed, only a second
    corpus, and the corpus was the unsound part.**
- **⚠ `decompose` IS ALLOWED, AND THAT IS WHAT KEPT THE BUMP AT MINOR.** It is the only otherwise-
  denied verb with real fenced agent-typed call sites in shipped content
  (`forge/references/storyhook-contract.md:271-278`, `story-decomposition.md:76-82`). Deny it and a
  shipped forge instruction changes verdict, which makes the honest level **major**. If you ever
  narrow the allowlist, check the removed verb against those files first.
- **Mutation battery: 10 run, 10 caught**, every mutation asserted APPLIED and every restore
  asserted tracked-and-clean. M9 (removing `decompose`) reds the pin — **proving the set-equality
  pin catches narrowing**, which is the mechanism that replaced the withdrawn guard. M6 (restoring
  the blanket allow inside `is_always_safe`) reds **17** tests including the source-level guard.
  ⚠ A first attempt at M6 used an unanchored `sed` that hit every `*) return 1 ;;` in the file and
  corrupted sibling helpers — it still "caught" the mutation, for the wrong reason. **Scope a
  mutation to the function you mean, or its red proves nothing.**
- **The gate was green with NO bypass — thirteen sessions running.** `MAKE_EXIT=0`, **653 bats
  assertions + 307 shell checks, zero `not ok`, zero shell FAIL, zero make errors, 5 bats plans**.
  653 = AGE-22's 628 + 25 new. `test_shipped_content_matches_tagged_release` PASS on the bump. The
  AGE-24 ordering (targeted suites → bump → **one** full `make -k test`) held for the sixth time.
- **⚠ CLAUDE.md is in `forge-contract-check`'s root scan set, where each inline backtick span is
  parsed as an invocation.** This session's CLAUDE.md entry therefore writes the verbs as **prose**
  (`the purge and project-delete verbs`) rather than as `` `story purge` `` spans. Verified green
  via `make test-storyhook-contract-root`. If you document a `story` verb in a root file, either
  write it as prose or be ready to justify it to that guard.
- **Filed: AGE-52** (med) — greenlight's config auto-init only copies when the file is **absent**,
  so no existing install ever receives a corrected default; the live config still carries
  `ai_enabled: true` + `ai_model: claude-sonnet-4-6`, the exact values F077/F078/F082 fixed, inert
  only because `ANTHROPIC_API_KEY` happens to be unset. **AGE-53** (low) — `open`/`xdg-open`/
  `xdg-mime` sit in `is_always_safe` under the same false header (`open -a <App>` launches
  applications, `open <url>` hits the network); same shape as AGE-26, smaller blast radius.
  **AGE-54** (med) — `plan_explorer_uncertain: allow` also auto-approves `npx` (*"execute arbitrary
  code, always uncertain"*), so the explorer sandbox permits arbitrary code execution; the council
  accepted "fix at the origin, not the encounter point" **on condition the origin got a ticket**,
  and this is that ticket.
- **Council: C won 2-1 in a ranked-choice runoff; every seat voted against its own round-1 proposal
  (A→C, B→C, C→B), and in the runoff A ranked its own proposal LAST.** C defected from its own
  design, then returned to it after **checking** a calibration claim it had asserted rather than
  measured. Nobody defended the blanket allow at any point. Full trail:
  `.council/age26-greenlight-story-verb-surface/DECISION.md`.

## Known state (updated 2026-08-04 by the AGE-22 session)

- **AGE-22 is DONE. No bump — the repo stays at v3.6.0.** It touched only `tests/`, `Makefile` and
  `CLAUDE.md`; the shipped-plugin pathspec diff is **empty**. Verify before assuming it applies to
  you: `git diff --stat origin/main HEAD -- plugins/ ':(exclude,glob)plugins/*/tests/**'
  ':(exclude,glob)plugins/**/*.bats' ':(exclude,glob)plugins/*/README.md'` — **empty means no bump.**
- **⚠ THE NEW GUARD WILL RED ON YOU BY DESIGN, and that is the feature.** `tests/bounded-capture-guard.sh`
  (`make test-bounded-capture-guard`) positively pins **four censuses**. Writing a new
  `timeout`/`gtimeout` call site, **or a new call of `run_with_timeout`/`run_explorer`/`run_bounded`**,
  reds the gate. That is the guard asking you to decide whether the new output can ever reach a
  caller's substitution pipe — **not a nuisance to silence by bumping the pin.** If it can, add the
  wrapper's name to `REGISTRY` in that file. Layers: L1 no bounded command at a COMMAND POSITION
  inside `$()`/backticks; L2 the bounded sites are exactly `{session-stop.sh:2, greenlight-explore.sh:1}`,
  total 3; L3 no capture of a registry name + each name's definition found by a pattern matching
  **both** `() {` and `() (`; L4 registry-name occurrences are exactly 9.
- **⚠ THE STORY WAS RIGHT AND ITS WORDING WAS TOO BROAD — implementing it literally reds a correct
  line.** AGE-22 says *"a bounded command must never have its output captured"*. The real invariant
  is narrower: **the hazard is the bounded command's stdout BEING the substitution's pipe.** A
  wrapper that redirects its child internally severs the chain. So `plugins/rca/tests/test-repro.sh:35`
  — `out=$(bash "$REPRO" run … --timeout 1 || true)`, a `$()` capture whose text contains `timeout`
  — is **CORRECT**, and any substring guard reds it on day one. It ships in the BENIGN corpus so
  the calibration is executable rather than a claim in a header.
- **⚠ TWO FALSE GREENS WERE FOUND IN THE WINNING DESIGN ITSELF, after it won the vote.** Both
  measured, both now pinned by their own arms:
  - The command-position anchor as first written matched `$(timeout 5 x)` but **missed 5 of 6
    probes** — the backtick-opened form and all four of `env`/`command`/`nohup`/`xargs`. So
    `$(env timeout 5 story handoff)`, a **one-token** rewrite of AGE-16's own defect, passed green.
    ⚠ But the exec prefix must **not** admit flags: `(-[^ ]+ )*` makes `command -v timeout` — a
    probe, present 3× here — read as an invocation. Mutation M2 pins both directions at once.
  - **`grep -c` counts LINES.** Appending `; timeout 9 evil` to an already-pinned line left the
    census sitting at 3. Measured `grep -c`=1 vs `grep -o`=2. **If you pin a count anywhere, count
    matches.**
- **⚠ A DERIVED CLOSURE OVER FUNCTION BODIES IS DISQUALIFIED HERE — three seats found it
  independently.** `run_explorer() (` at `greenlight-explore.sh:135` is **paren-bodied and is the
  ONLY such definition in the repo**, while the house body-extractor idiom
  (`sigpipe-shape-guard.sh:115`, `:272`) keys on `/^name() {/`. A closure built on it silently loses
  one of the only two propagating wrappers, and **an empty derived set is indistinguishable from a
  correct one**. Worse, `rca-bisect.sh`'s `run_bounded` is text inside a `<<'WRAP'` heredoc, not a
  definition in that file at all. If you ever extract shell function bodies in this repo, handle
  both body forms and heredocs, or don't.
- **⚠ A REDIRECT HEURISTIC IS ALSO DISQUALIFIED — proposed, voted for, then withdrawn by its own
  author.** Five shapes break it, all in the UNSAFE direction: `2>/dev/null` alone leaves stdout on
  the pipe; `2>&1 >file` sends stderr to the ORIGINAL stdout while *reading* as redirected;
  `| tee f` launders rather than severs; `exec >"$f"` earlier in a body is not on the invocation
  line; and **`session-stop.sh:196`'s redirect sits on `:197` behind a backslash continuation**, so
  a per-line test misreads the blessed live call site as unredirected.
- **⚠ THE GUARD'S OWN CALIBRATION FOUND A FALSE POSITIVE ON THE DOCUMENTATION DESCRIBING AGE-16.**
  `session-stop.bats:83` reads *"…escapes the process group `timeout` signals…"* — English inside a
  **Python docstring inside a heredoc**, so it is NOT a `#` line and `strip_comments` cannot reach
  it. Fixed **mechanically, not by exemption**: the token's trailing class excludes a backtick, so
  an inline-code span (`` `timeout` ``) does not match while a real backtick substitution
  (`` `timeout 5 x` ``) does. **The registry detector deliberately uses a WIDER tail that does
  admit the backtick** — the prose hazard is specific to `timeout`, an ordinary English word.
- **⚠ `set -o pipefail` + `grep`'s no-match exit 1 SILENTLY ATE EVERY DIAGNOSTIC.** The first draft's
  L1/L3 arms assigned `hits=$(…grep…)`; on a clean tree grep exits 1, `pipefail` propagates it, and
  the runner's `set -e` killed the arm **before it printed anything** — so a clean tree and a broken
  regex both surfaced as a bare `FAIL` with no output. This is AGE-21's class one door down (there
  it was SIGPIPE; here it is a legitimate no-match). `scan_lines`'s `|| true` is load-bearing and
  mutation M9 pins it, as does `test_scan_lines_plumbing_can_report_a_hit` — **an arm whose PASS is
  an empty result is vacuous unless something proves the plumbing can emit at all.**
- **The scan set is INDEX-BASED (`git ls-files`), not the working tree.** A brand-new script is
  invisible until `git add`. Correct for a pre-push gate; surprising while iterating. It is derived
  from git rather than a filesystem glob deliberately — that reaches the **9 tracked extensionless
  shell scripts** (`plugins/*/tests/fakes/{gh,story,tmux,tailscale}`) an extension glob misses,
  correctly excludes the extensionless **Python** `deployit-posttest` (whose docstring says
  "timeout"), and avoids pinning stale `.claude/worktrees/` copies.
- **Mutation battery: 9 run, 9 caught**, every mutation asserted APPLIED (anchor-miss aborts) and
  every restore asserted tracked-and-clean. M2 (exec prefix admitting flags) reds the **L2 census**,
  because `command -v timeout` becomes a fourth site — the census catches detector widening, not
  just new code. M8 (broken pathspec) reds 5 arms, proving the censuses are not vacuity-passing.
- **The gate was green with NO bypass — twelve sessions running.** `MAKE_EXIT=0`, **628 bats
  assertions + 307 shell checks, zero `not ok`, zero shell FAIL, zero make errors, 5 bats plans**.
  The new guard reports **25 passed, 0 failed** inside the full run. Wall clock ~13 min.
- **Filed: AGE-51** (low) — five shipped `$( … story … )` captures (`forge-state.sh:275`,
  `forge-status.sh:70`, `forge-crash-recover.sh:37`, `forge-mapping-scaffold.sh:66`,
  `storywork/tests/test-real-story-cas.sh:156`) are unbounded and storyhook auto-spawns a daemon
  that outlives the client. **Measured NOT exposed**: on storyhook **2.0.0** the capture returns in
  0.03s and every daemon holds fd 0 on `/dev/null` with **no fd 1 or fd 2 at all**. But that is an
  upstream implementation detail, not a contract — SH-94 recorded the daemon holding a pipe at
  **fd 7** — and nothing here pins it. All three council seats said independently: do **not** widen
  the guard to red five working sites on an unmeasured theory; measure it and file it.

## Known state (updated 2026-08-04 by the AGE-19 session)

- **AGE-19 is DONE. No bump — the repo stays at v3.6.0.** It touched only root `tests/`,
  `Makefile` and `CLAUDE.md`; the shipped-plugin pathspec diff is **empty**. Verify before
  assuming it applies to you:
  `git diff --stat origin/main HEAD -- plugins/ ':(exclude,glob)plugins/*/tests/**'
  ':(exclude,glob)plugins/**/*.bats' ':(exclude,glob)plugins/*/README.md'` — **empty means no bump.**
- **⚠ THE STORY WAS RIGHT — and its numbers were wrong in BOTH directions.** Reproduced with the
  real upstream **v1.0.0 binary**, not a simulation
  (`gh release download v1.0.0 --repo mikeydotio/storyhook`):

  | Story said | Measured |
  |---|---|
  | "~60 failures" | **87** failing assertions |
  | "across 7 suites" | **3** (forge 72, storywork 14, contract-root 1) |
  | Extent: forge, storywork, forge contract check | **exactly right** |

  greenlight and root-bats **passed** under 1.0.0. Zero of the 2 693 log lines contain "version",
  "incompat" or "upgrade".
- **⚠ THE SYMPTOM BLAMES THE CALLER, which is worse than merely unattributable.** 59 of the
  failures are ``error: unknown command `project` ``. A reader lands on
  `forge-close-project-story.bats:14`, sees *this repo* invoking a command storyhook says does not
  exist, and the natural next move is to "fix" this repo. It points at the **wrong repository**.
  Note storyhook 1.0.0 has no `story project` verb **at all** — the 2.0 break is bigger than the
  `init`→`new` rename AGE-19 describes.
- **⚠ "CANNOT OBTAIN A VERSION" IS NOT AN EDGE CASE — IT IS WHAT THE OLDEST REAL MAJOR DOES.**
  Measured on real binaries, and this one fact decided the whole design:
  - **v0.2.0 cannot report a version under ANY condition.** `--help` lists no version flag. Two
    different outputs, **both exit 3**: outside a project ``error: story project not initialized in
    this directory; run `story init` ``; inside one ``error: story `--version` not found``.
  - **v1.0.0 exits 5 outside an isolated store**, refusing *every* invocation including
    `--version` (schema 8 vs "understands up to version 2"). Under the wrapper it exits 0.
  So a guard treating cannot-verify as *pass* would go **vacuously green against the most broken
  binary in the wild**. Absent / non-zero-exit / unparseable are one boolean with four sentences.
  Consequence: **the pin must run inside `with-isolated-store.sh`**, or a readable 1.x binary is
  misreported as unreadable.
- **⚠ THE UNANCHORED VERSION REGEX IS A SILENT FALSE GREEN — measured, and it overrode a 2-1
  council majority.** Given `warning: 2.0.0 config format is deprecated` followed by `story 3.0.0`,
  a first-triple-anywhere scan reads **2.0.0 and PASSES a major-3 binary**. `grep -E` is per-line,
  so the strict `^story[[:space:]]+v?<triple>` anchor skips the banner. A cosmetic rebrand
  (`storyhook 2.1.0`) is rejected too, but lands in the *unparseable* branch which fails **naming
  the observed output** — bounded and loud, not silent. **The transferable rule, from the seat that
  found it: a false red is bounded, loud and self-announcing; a false green on the exact scenario
  being guarded is silent.**
- **⚠ MAKE PREREQUISITE EDGES WOULD BE BETTER UNDER `-k` AND WERE STILL DECLINED — know why before
  you "improve" this.** Measured: a failing phony prereq makes `make -k` **skip** dependents
  entirely (87 failures suppressed, unrelated targets still run, rc=2), where ordering only
  *attributes* them. Declined because `gate-integrity.sh` sub-makes `make -C . test-forge` asserting
  **exit 0** while building its PATH by dropping **every directory containing a `bats`** — so on any
  machine where `bats` and `story` share a directory, an edge reds the **meta-gate** for a storyhook
  reason. Safe here only by luck (`/opt/homebrew/bin` vs `~/.local/bin`). **Revisit trigger,
  recorded rather than hypothetical:** if a future major bump shows the attributing line was lost in
  `-k` noise, reopen it *together with* a fix preserving `story` in gate-integrity's filtered PATH —
  that file already does exactly this for `make` (`MAKE_BIN` resolved before filtering).
- **⚠ `test-greenlight` and `tests/storyhook-path-guard.sh` DO NOT DRIVE THE `story` CLI.** The
  chair's own brief said they did and was wrong; two seats inherited the error. `path-guard` is pure
  git-grep (`command -v git` only, `:398`); `greenlight.bats` never execs `story`. **The
  reproduction proved it independently — greenlight exited 0 under storyhook 1.0.0.** The real
  storyhook-driving set is exactly **forge, storywork, storyhook-contract-root**. Do not re-add the
  other two to an ordering pin.
- **Council: ALL THREE SEATS VOTED AGAINST THEIR OWN PROPOSAL** (B won 2-1; B's own author defected
  to C). The architect withdrew its differentiator mid-council on evidence and was right about two
  facts the chair's brief got wrong. **The chair overrode the 2-1 majority on the regex** because
  the losing seat produced a falsifying measurement the majority never saw — *a measurement beats a
  majority formed without it.* Full trail: `.council/age19-storyhook-version-pin/DECISION.md`.
- **⚠ A COUNCIL SEAT REPORTED A FABRICATED "RECORDED" FIXTURE, and it nearly shipped.** The QA seat
  proposed committing `error: story --version not found` as a corpus string labelled *recorded from
  a real binary*. That string is **never emitted** — the chair downloaded v0.2.0 and found two
  different real outputs. It owned the error immediately when challenged. **Re-run a seat's
  "measured" strings before committing them; a fixture labelled recorded that is not is exactly the
  defect class this repo's guards exist to stop.**
- **Mutation battery: 7 run, 7 caught.** M1 comparator neutered → 4 reds; M2 rc check dropped → 3;
  M3 regex un-anchored → 2 (incl. the false-green test); M4 unparseable→ok → 2; M5 absence branch
  deleted → 1; M6 pin→3 → **10** (proves the guard reads the live CLI *and* that the doc pin fires);
  M7 `head -1`→`tail -1` → 1. **One honest finding: the "mutation-critical" rc test turned out
  SUBSUMED** — designed as uniquely load-bearing, but the recorded cases assert the exact verdict
  *token*, so they red too. Kept with the reason written into the source (AGE-12's precedent),
  because it pins that rc outranks a *parseable* stdout.
- **⚠ COMMIT A NEW GUARD BEFORE YOU MUTATE IT.** AGE-21's warning, followed here and it worked: the
  battery restores with `git checkout --` and asserts **tracked-and-clean**, impossible for an
  untracked file. One mutation's `sed` silently changed nothing (delimiter clashed with a `|` in the
  pattern) and the battery caught that too, because it aborts unless the file actually changed.
  **Assert the mutation APPLIED, not merely that the tests ran.**
- **The gate was green with NO bypass — eleven sessions running.** `MAKE_EXIT=0`, **628 bats
  assertions + 282 shell checks, zero `not ok`, zero make errors, 5 bats plans**. AGE-21's old
  `test-cli-rm.sh` flake **passed**. Wall clock ~12 min.
- **Filed: AGE-50** (low) — `plugins/storywork/tests/test-real-story-cas.sh:22` exits 0 with `SKIP`
  when `story` is absent and its runner counts that as **PASS**, so the one file proving story.sh
  works against the REAL binary reports PASS having verified nothing. Two seats flagged it
  independently and **both said not to fold it in** — different defect, and mixing it would blur the
  attribution AGE-19 exists to create. Largely shadowed by the new pin (the gate now halts first);
  live only on the direct-runner path.

## Known state (updated 2026-08-04 by the AGE-21 session)

- **AGE-21 is DONE. No bump — the repo stays at v3.6.0.** Everything it touched is under
  `plugins/*/tests/**` (excluded from the shipped pathspec), root `tests/`, or the `Makefile`.
  Verify the rule yourself before assuming it applies to you:
  `git diff --stat origin/main HEAD -- plugins/ ':(exclude,glob)plugins/*/tests/**'
  ':(exclude,glob)plugins/**/*.bats' ':(exclude,glob)plugins/*/README.md'` — **empty means no bump.**
- **⚠ THREE CAUSAL STORIES FOR ONE FAILURE, ALL THREE REFUTED. This is the sharpest result yet of
  the "the story can be wrong" rule, because the *correction* was wrong too, twice.** Filed as
  **AGE-49**; do not close it by asserting any of them.
  1. **AGE-21 as filed** — *"depends on a live local backend daemon (:8729)"*. False three ways:
     the refresh runs **after** the push and only inside `if published:` (`deployit-cli:2607` vs
     `:2593`); the test configures **port 8731**, where nothing has ever listened, so :8729 is never
     contacted; and its `warning: local backend refresh failed` line appears on **10 of 10 PASSING
     runs**. A constant cannot explain an intermittent failure.
  2. **The chair's own replacement theory** (the SIGPIPE class below caused it) — **retracted mid-
     council.** P(50 consecutive poll failures) ≈ 1e-17 on this fixture.
  3. **A `DEPLOYIT_SKIP_GC_PUSH` rival** found by the skeptic seat — reproduces the failing line
     **deterministically 4/4**, and was still **refuted by the recorded artifact**: `cmd_rm:2606`
     *skips* the backend refresh when that variable is set, so such a run emits **zero** of the
     `warning:` lines that the recorded output contains. **If a design argument rests on a
     mechanism, check what that mechanism SUPPRESSES as well as what it produces.**
- **⚠ THE REAL DEFECT, AND THE NUMBER THAT EXPLAINS SIX WEEKS OF CONFUSION.**
  `git log --oneline | grep -q X` under `set -o pipefail` returns **141 (SIGPIPE) on a match that
  SUCCEEDED**: `grep -q` exits first, `git log` dies mid-write, `pipefail` propagates the signal
  status. **The rate is a function of OUTPUT SIZE, not environment:**

  | commits | `log --oneline` | failures |
  |---|---|---|
  | 2 | 130 B | 13/60 |
  | 50 | 3.3 KB | **60/60** |
  | 2000 | 134 KB | **60/60** |

  It saturates at 100% once output exceeds the 64 KiB pipe buffer. **Every disputed measurement in
  this council — 0, 9, 11, 21, 22, 37, 46, 65% — was taken on the 2-commit fixture, the only region
  where the outcome is a coin flip.** One seat measured **0/400** and was neither wrong nor
  anomalous. If you are ever handed contradictory flake rates, **look for the size/scale variable
  nobody varied** before blaming the harness.
- **⚠ `git checkout -- <file>` CANNOT RESTORE AN UNTRACKED FILE, AND `git diff --quiet` ON ONE
  RETURNS 0.** This session's mutation loop therefore reported `[restored OK]` while two mutations
  silently **accumulated** in the new guard, and the third mutation's result was read against a
  doubly-mutated file. Caught only by re-reading the counts. **Commit a new guard BEFORE you mutate
  it**, and make the restore assertion prove the file is *tracked and clean*, not merely
  "unchanged". This is the AGE-24 warning ("restore first and assert the restore") with the exact
  hole that warning did not cover.
- **The fix is a SHAPE fix, not a retry.** `remote_has`'s 50-iteration poll (added by `23d1dcd` on a
  *"receive-pack post-receive settle"* theory that is also falsified — it reproduces on a repo
  settled 2 s, and 32/32 non-pipeline reads saw the ref advanced immediately) is **deleted**. The
  replacement `origin_published` consumes git's output whole and asserts the **pushed content**, not
  just the commit subject: a publisher committing the right message with nothing staged
  (`--allow-empty`) **passes** a subject-only check — measured, 0 vs 1. A failed git read now exits
  **2**, because *"I cannot verify this"* is not *"the rm was not pushed"*.
- **⚠ A guard now bans this shape repo-wide: `tests/sigpipe-shape-guard.sh` (`make
  test-sigpipe-shape-guard`).** Two things will bite you:
  - **It excludes comment lines on purpose.** `test-cli-rm.sh` quotes the banned form in a comment
    telling you never to reintroduce it. A guard you can satisfy by deleting a true sentence is the
    wrong guard (the AGE-11 rule).
  - **It enumerates walkers** (`git log|rev-list|shortlog|grep|blame`, `find`, `locate`), so a
    `python3` generator, a streaming `curl`, a `jq --stream` or an `awk` over a large file have the
    property and are **not** matched. That limit is the dissenting seat's objection, recorded in the
    file header rather than papered over. Treat green as *"none of the known walkers"*.
- **The gate was green with NO bypass — ten sessions running.** See the gate bullet at the end of
  this block for the run's numbers. `run-tests.sh` now records each failing test's **exit status**,
  so a future `exit 141` names this class instead of inviting a fourth guess.
- **Filed: AGE-47** (med, **closed by this PR**) — the deployit runner wrote every test's output to
  the fixed path `/tmp/deployit-test.log`, so concurrent runs interleave and *the diagnostic block
  you reason from may belong to a different run*. AGE-21's filed root cause was inferred from
  exactly such a block. **AGE-48** (med, open) — `_commit_and_push_index` returns `published: True`
  after a purely local write under `DEPLOYIT_SKIP_GC_PUSH`, so any test asserting a real push runs
  **wholly vacuous** if that variable leaks in; shipped code, so it costs a bump. **AGE-49** (low,
  open) — the unexplained failure above.
- **Council: all three seats voted against their own proposals, then all three revised to the same
  one.** Round 1 A=2/B=1; after deliberation the ballot was unanimous for A. The class guard shipped
  **2-1 over the skeptic's dissent**, and the dissent is answered in the guard's header rather than
  overruled. Full trail: `.council/age21-sigpipe-assertion/DECISION.md`.

## Known state (updated 2026-08-04 by the AGE-12 session)

- **AGE-12 is DONE and shipped as v3.6.0. AGE-21 leads the queue.** Nothing is blocked
  (`blocked: 0`); confirm with `story list --ready`, not this line.
- **⚠ CORRECTION to this session's own first draft of the line above: `story next` says AGE-19,
  NOT AGE-21, and the table is still right.** An earlier version of this block claimed the two
  "agree" now that nothing is blocked. They do not, and the reason has nothing to do with
  blocking: AGE-19 and AGE-21 are both `todo`/`ready`/`medium`, so `story next` is breaking the
  tie by **ID order alone**. This table breaks it by what unblocks the loop itself — AGE-21 is
  the last known source of pre-push gate noise, and every session here depends on a trustworthy
  gate. That is the AGE-28 rule restated: **trust `story list` for STATE, this table for
  ORDERING RATIONALE, because `story next` cannot see the rationale.** Caveat worth carrying:
  AGE-21's flake has now **not fired in five consecutive full gate runs**, so reproduce it
  before believing the story — if it no longer reproduces, that finding is the deliverable, and
  AGE-19 (which this session's own upstream-coupling work makes newly relevant) is next.
- **⚠ THE STORY'S CENTRAL CLAIM WAS FALSE, AND ONLY REPRODUCTION REVEALED IT.** AGE-12 states the
  failure surfaces *"only a generic `story move ... failed` message"* and that *"nothing in the
  error names the actual cause"*. Reproduced live, the shipped script already emitted ``story move
  TST-1 in-progress failed: state `in-progress` is not defined.`` — the cause **was** named,
  because `story.sh:282` has interpolated the CLI's `.error` since its first commit. The real gap
  was narrower and different: **no remedy, and no machine-readable discriminator.** Implementing
  what was filed would have changed nothing.
- **⚠ THE CONDITION CANNOT BE CREATED THROUGH THE CLI ANY MORE — the repro needed SQLite surgery
  on the store.** storyhook 2.0.0 enforces a four-state invariant (SH-125): `state remove
  in-progress` refuses, `state set in-progress --super CLOSED` refuses, and while `in-progress` is
  missing **every other `state add` refuses too**. It is reachable only via a legacy store (this
  repo's own AGE project until AGE-2), direct surgery, or an upstream regression. Consequence:
  **no committed regression test may build the broken vocabulary.** The fake models it; the
  real-CLI tier (case R3) instead pins the *premise* of the parse against a healthy project, which
  is the part that would silently rot.
- **⚠ THE OBVIOUS IMPLEMENTATION IS A TRAP.** Matching the move's own error text (``state `X` is
  not defined``) looks like the cheap fix. storyhook emits **that same sentence** when the
  undefined state is the `--if-state` value — the story's *current* state — a different fault with
  a different remedy. A regex answers confidently and wrongly. The shipped fix **observes**
  instead: it reads the vocabulary via `story state list` on the already-failed path. Presence of a
  state is a fact; wording is version-coupled guesswork.
- **⚠ THE COUNCIL'S DECIDING FACT KILLED TWO OF ITS OWN SEATS' RATIONALES.** Both losing proposals
  rested on `reason` being a key conductor could branch on. It is not:
  `conductor/conductord/dispatch.py` turns every `ok:false` into `DispatchError(display)` and
  **never reads `reason`**, and it **pre-claims via `storyx.claim_ready` before invoking story.sh
  at all** — so this path is human-operator-only and `display` is the entire payload. The chair
  re-read `dispatch.py` from source rather than trusting the seat; seat 2 recorded in its own vote
  that this *"falsifies my own Proposal B's rationale"*. **If a design argument rests on what a
  downstream consumer does, go read the consumer.**
- **⚠ MUTATION TESTING FOUND A REAL GAP AND A REAL REDUNDANCY — they look identical until you
  check.** Nine mutations: seven red the intended assertion, two red nothing, and the two were
  **not the same thing**:
  - The **empty-message** and **parsed-states** guards were **mutually masking** — deleting either
    alone reds nothing because the other catches the fixture; deleting **both** reds three tests. A
    new case (11e: a non-empty message that parses to zero states) pins the one only the
    parsed-states guard can catch, and that mutation now reds. **A genuine hole.**
  - The empty-message guard's own mutation still reds nothing, and it was **kept anyway**, with the
    reason written into the source so the next reader does not "simplify" it. Subsumed
    defence-in-depth, not a hole. Same symptom, opposite verdict — only the **combined** mutation
    told them apart.
- **The remedy string is `story doctor --fix`, and the alternative was measured, not assumed.**
  `doctor --fix` restores the state in the correct board position but **without** the `active`
  role; `story state add in-progress --super OPEN --role active` — what AGE-12's own fix direction
  prescribes — sets the role but appends the state **after `done`**, leaving the board visibly
  wrong. Neither fully restores the default shape. `doctor --fix` wins because it is what
  storyhook's own invariant error already tells users to run, and a wrapper that contradicts the
  tool it wraps creates two rival instructions for one fault.
- **The gate was green with NO bypass — nine sessions running.** `MAKE_EXIT=0`, **628 bats
  assertions + 595 shell checks, zero `not ok`, zero make errors, 5 bats plans, zero skipped
  suites**. `test_shipped_content_matches_tagged_release` was the ONLY red before the bump and
  named exactly the changed file; it cleared on the bump. **AGE-21's flaky `test-cli-rm.sh` did not
  fire** (deployit 50/50). The AGE-24 ordering (targeted suites → bump → **one** full `make -k
  test`) held for the fifth time; wall clock ~20 min.
- **Bump level: `minor` (v3.6.0), by the AGE-30/AGE-17 precedent.** The script's documented JSON
  output gains a new `reason` value on a path that previously emitted no `reason` key at all — the
  same class as AGE-30's two error codes and AGE-17's two JSON keys. Not major: nothing previously
  accepted is now rejected, and `ok:false`/exit 1 on that path are unchanged.
- **Filed: AGE-45** (low) — `dispatch --dry-run` returns `ok:true` for plans certain to fail.
  Deliberately split out rather than patched here: dry-run returns at `:350`, **before**
  base-commit resolution, the worktree/branch collision pre-check, and every tmux call, so the
  state case is one of at least four. The council ruled a state-specific patch would *"fake a
  validation guarantee dry-run does not make"*. Fix the contract, not one symptom.
- **Filed upstream: storyhook SH-180** (med) — `story move`'s undefined-state error omits the
  ``Run `story doctor --fix` `` guidance storyhook's *own* invariant error already carries. That is
  the origin fix; everything shipped here is a downstream workaround that can be retired once
  SH-180 lands. It also records the `doctor --fix`-loses-the-`active`-role finding above.

## Known state (updated 2026-08-04 by the AGE-30 session)

- **AGE-30 is DONE and shipped as v3.5.0. AGE-12 leads the queue.** Nothing in the backlog is
  blocked any more (`story summary` → `blocked: 0`), so the dependency-graph rule that has
  outranked `story next` for six sessions is now spent — the two agree. Confirm with
  `story list --ready`, not this line.
- **⚠ THE STORY'S OWN REACH TABLE UNDERSTATED ITS VALUE BY A THIRD, and its bump level was wrong.**
  AGE-30 argued for landing last on a predicted ceiling of *"34/53 = 64%"*. Re-measured after
  AGE-24/29/31 landed: `AGENTS.md` is **54/58 = 93%**. The story's figure was computed before its
  own blockers shipped, and every blocked story in this queue carries the same hazard —
  **a precondition measured against a corpus your blockers will change is not a precondition.**
  - It also predicted `patch` ("adds no JSON key"). It added a **CLI flag and two error codes**
    (`missing_file`, `usage`), so **AGE-17's precedent governs**: that story shipped a *minor* for
    adding two keys to *this same script's* documented output. Shipped **minor**. Over-signalling
    costs a digit; AGE-33's lesson is that under-signalling strands every install.
- **⚠ `CLAUDE.md` contributes ZERO detection and is in the scan set anyway — do not "optimise" it
  out.** Its single `story` occurrence is English prose (*"parent story could permanently
  deadlock"*), correctly ignored. It is pinned for **blast radius, not yield**: it is read as
  instruction by every agent unprompted, so it is exactly where a silent coverage drop hides.
  `README.md` is excluded by the opposite reasoning — 0 occurrences **and** 4 fence markers, i.e.
  pure false-positive surface. Both calls are recorded in the suite header; neither is arbitrary.
- **⚠ A COUNT CANNOT SEE A SWAP — this is the sharpest reusable result of the session.** The new
  suite asserts **exact membership** of `files_scanned`, not a count and not a floor. Mutation
  proof: an argv that drifts from `--file AGENTS.md --file CLAUDE.md` to `--file AGENTS.md --file
  README.md` keeps the count at 2, keeps the allowlist pin green, keeps *"root files are clean"*
  green — and **only** the membership assertion reds. A second mutation (argv expands empty) scans
  **29 forge plugin files** and still reports *"clean"*. If you assert on `files_scanned` anywhere,
  name the set.
- **⚠ `files_scanned` COULD NAME A FILE NOBODY READ, and that is now fixed.** `SCANNED_FILES_JSON`
  was built from the *requested* list before the per-file `[[ -f ]]` check, so the field this repo
  uses as its anti-vacuity oracle could itself lie. Latent under shape discovery (`find` yields only
  existing files); `--file` would have made it reachable. Now accumulated **inside** the loop, past
  the existence check. Note honestly: **its mutation reds nothing today**, because the new hard
  error makes the branch unreachable — it is defence-in-depth, correct by construction rather than
  by caller discipline.
- **A mutation that reds nothing is not automatically a gap.** Removing the `.ok=="true"` assertion
  and hiding the `story` CLI was predicted (by the seat that designed the oracle) to make every
  planted-drift test pass vacuously. It **did not** — the oracle also asserts the reported *token*
  and *file*, which are `null` without a CLI. Redundant coverage, not a gap; `.ok` was kept because
  it turns *"expected AGE-1, got null"* into *"checker could not verify"*. **Verify the predicted
  failure actually happens before treating a green mutation as a hole — or as a pass.**
- **⚠ Run a mutated suite IN PLACE, never a copy in the scratchpad.** `REPO_ROOT` is derived from
  `$(dirname "$0")/..`, so a copy executed from the scratchpad resolved `REPO_ROOT` to the
  scratchpad's parent and reported 8 failures that meant nothing. Cost one wasted cycle. Restore
  from a pristine copy and assert `diff -q` after every mutation (that part worked, four times).
- **The gate was green with NO bypass — eight sessions running.** `MAKE_EXIT=0`, **628 bats
  assertions + 247 shell checks, zero failures, 20 suites reached, zero skipped**.
  `test_shipped_content_matches_tagged_release` PASS on the bump. AGE-21's flaky `test-cli-rm.sh`
  did **not** fire. Wall clock ~20 min — the AGE-24 ordering (targeted suites → bump → **one** full
  `make -k test`) held for the fourth time.
- **AGE-23 is confirmed for the THIRD time and still costs a tool call.** The council plugin's
  `references/*.md` resolve at the **plugin root**, not skill-relative. Commented on AGE-23.
- **Filed: AGE-44** (low) — `AGENTS.md` is GENERATED, so no `expect-dead` marker below
  `<!-- BEGIN GENERATED -->` survives regeneration; the file most exposed to a future false positive
  is the one where the escape hatch cannot durably live. Mitigated, not solved: the hatch is the
  **pin, not the marker**, and a fence-latch canary now reds on an unbalanced regenerated fence
  *before* it becomes a mystery violation.

## Known state (updated 2026-08-04 by the AGE-29 session)

- **AGE-29 is DONE and shipped as v3.4.0. AGE-30 is UNBLOCKED and leads the queue** — AGE-29 was its
  last blocker. Confirm with `story list --ready`, not this line.
- **⚠ THE STORY'S PRESCRIBED FIX WAS DISQUALIFIED BY MEASUREMENT.** This file warned AGE-29's "0 new
  violations" figure was stale. It was worse than stale — it measured the wrong axis. Relaxing the
  fence regex to `/^[[:space:]]*```/` (exactly what the story specifies) is wrong **three ways at
  once**: it reds the gate on a true English sentence, it **still misses** the dead invocation it was
  widened to catch, and it is a **coverage REGRESSION** against the shipped detector — SPAN units
  1793 → **1777**, silently dropping `story handoff` at `skills/execute/SKILL.md:191`, because a
  whole-LINE unit is checked once where two spans are checked individually.
  - **The transferable rule: a violation count cannot see a coverage regression.** Count extraction
    UNITS split by KIND (LINE vs SPAN) whenever you touch extraction. Every candidate scored "0 new
    violations" on the corpus; only the unit-kind split told them apart.
- **⚠ No regex can do this job — two mirror fixtures prove it.** The corpus writes list-item fences
  in two spellings (`   ```bash` and `4. ```bash`). A regex covering only the first inverts depth on
  the second; a regex covering **both** inverts depth on a document that *quotes* a list fence
  (`- ```js` inside a ```` ```markdown ```` block). Same false positive, same sentence, opposite
  trigger. Nothing lexical separates a legal opener from quoted content — **only fence depth does**,
  and a naive depth model is the broken one. Hence: *"if I have to write the correct detector in
  order to test the regex, ship the correct detector."*
- **The detector now models fence structure** (CommonMark's asymmetry, and it is load-bearing): an
  **opener** may carry indentation and an optional list marker; a **closer** may carry indentation
  ONLY, must be unmarked, carry no info string, and run at least as long as its opener. A list marker
  is container syntax — legal before an opener, never before a closer.
  - **Extraction is BYTE-IDENTICAL to the regex approach on all 29 corpus files** (LINE=742,
    SPAN=1793, 2535 units, 0 files differing). Nothing that exists today changed. One seat used that
    number to argue the correct detector "buys nothing"; the chair used the same number to conclude
    it **costs nothing**. Byte-identity measures *migration risk*, not *value*.
- **⚠ Three things will bite you if you touch the detector**, each pinned by a test naming its
  mutation: a fence-shaped line that is *not* a valid closer must still be **emitted** as a line unit
  (adding a `next` there drops content silently); whitespace classes must be `[[:space:]]`, not
  `[ \t]`, because a CRLF closer is `` ```\r `` and a stray `\r` latches depth open to EOF; and the
  closer test is `run >= flen` — the off-by-one `>` latches **26 of 29** corpus files.
- **⚠ MUTATION TESTING CAUGHT A GAP IN THIS SESSION'S OWN TESTS.** Ten mutations were run; nine reded
  the right tests and **one reded nothing** — dropping the info-string half of the closer rule,
  because the obvious fixture's `- ```js` is rejected by the *list-marker* half first and masks it. A
  fixture with equal-length unmarked fences was added and it now reds. **Run the mutations: the
  natural fixture for a rule is often not the one that pins it.**
- **AGE-41 was closed for free by this fix and never needed its own PR.** A nested 4-backtick block
  containing an odd number of 3-backtick lines desynchronised the **shipped** detector and reported a
  false positive on ordinary English. Filed, commented, closed; its repro ships as a regression test.
- **⚠ A METHODOLOGY CORRECTION — do not repeat the chair's error.** The AGE-31 note below says a run
  without a root argument "scanned nothing". That is true **only for a copy placed outside the plugin**
  (`DOCS_ROOT` defaults to `$SCRIPT_DIR/..`, which for a scratchpad copy is the scratchpad). For the
  **real** script a bare run scans all 29 files. This session generalised it into "always pass an
  explicit root" and dispatched three council seats with that false premise. The rule that actually
  holds either way: **assert a FLOOR on `files_scanned`**. The real vacuous path is passing the
  **repo root** (`files_scanned: []`, `contract_ok: true`). The suite now pins a floor.
- **⚠ `grep` in your Bash tool is NOT the `grep` your tests run.** It is a shell function wrapping
  **ugrep 7.5.0**, whose `[[:punct:]]` does not match `` ` ``, `>` or `+`; bats and hooks get
  `/usr/bin/grep`. Measured: `^[[:punct:]]` matched **4** lines under one and **1** under the other.
  **When a count is evidence for a decision, use `awk` or `/usr/bin/grep` explicitly.** Filed as
  **AGE-42**. This session's own 214-marker figure was re-verified in awk and survived — by luck.
- **⚠ Beware grepping the gate log for `FAIL` as well as `skip`.** This file already warns that every
  `skip` string in a green log is a *test name*. The same is true of `FAIL`: this run's log contains
  two lines matching `FAIL`, and **both are `ok` lines** whose test names are "…reports FAILED with
  the cycle count…" and "display shows FAIL for failing check". Count `^not ok ` instead.
- **The gate was green with NO bypass — seven sessions running.** `MAKE_EXIT=0`, **619 bats
  assertions + 334 shell checks, zero failures, zero skipped suites**. `plugin-content-drift` cleared
  on the bump. **AGE-21's flaky `test-cli-rm.sh` PASSED.** Wall clock ~25 min — faster than the ~45min
  this file last quoted and far under the old ~2h figure, but budget for 2h; it varies with load.
- **The AGE-24 ordering held for the third time**: targeted suites first (`make test-forge` + the
  three fast guards, ~8 min), then bump, then **one** full `make -k test` post-bump.

## Known state (updated 2026-08-04 by the AGE-31 session)

- **AGE-31 is DONE and shipped as v3.3.0 (PR #146, `d88a416`). AGE-29 leads the queue.** AGE-30's
  blockers were AGE-24 (done), AGE-31 (done) and **AGE-29 — now the last one**. Clearing AGE-29
  returns AGE-30 to `ready`; nothing else in the queue unblocks anything. That is the same
  dependency-graph rule that put AGE-32 ahead of `story next`'s AGE-12, and it still outranks
  `story next`, which is breaking a `medium`/`ready` tie by ID order alone. Confirm with
  `story list --ready`, not this line.
- **⚠ AGE-29's "measured free" figure is STALE — re-measure before you trust it.** Its note says
  the indented-fence relaxation produced *"0 new violations on the real 27-file corpus"*. That
  was measured **before AGE-24 (span extraction) and AGE-31 (placeholder verbs)**, and the corpus
  is now **29 files** with a strictly larger reachable surface. An indented fence's unit is the
  LINE, so relaxing the fence detector hands whole indented lines to a checker that now also
  matches `<...>` in the verb slot. Re-run it; the simulation takes ~2 minutes.
- **⚠ The full gate was green with NO bypass, and the drift guard cleared on the bump.**
  `MAKE_EXIT=0`, **607 bats assertions + 238 shell checks, zero failures, zero skipped suites**
  (607 = AGE-24's 596 + 11 new tests). `test_shipped_content_matches_tagged_release` PASS.
  `/semver validate` 6/6, tag verified an ancestor of `main`. **Six sessions with no
  `SKIP_PREPUSH_TESTS=1`.** Wall clock ~45 min this run, not the ~2h this file has been quoting —
  budget for 2h anyway, it varies with load.
- **The ordering from AGE-24 held up again and is now twice-proven**: targeted suites first
  (`make test-forge` + the three fast guards, ~6 min), then bump, then **one** full `make -k test`
  post-bump. One gate run, and the state that ships is the state the gate verified.
- **⚠ ~~`git switch main` FAILS in this checkout~~ — RESOLVED by AGE-61 on 2026-08-05. Superseded;
  kept only so the next reader does not re-derive it.** `main` was held by the `age-118` worktree
  (`fatal: 'main' is already used by worktree at .claude/worktrees/age-118`). That worktree is gone,
  local `main` was fast-forwarded 20c31d2 → 3cdbfcd, and `git switch main` succeeds again — but
  **step 10 no longer asks you to run it, and you should not.** The release path is now decoupled
  from any local `main` ref; see step 10 for the measurements. Two facts from this block survive and
  are still true: verify the tag landed with `git merge-base --is-ancestor v<X.Y.Z> origin/main`,
  and **GitHub auto-deletes the branch on merge** (`delete_branch_on_merge: true`, re-confirmed by
  AGE-61), which is why step 10 no longer carries a `push origin --delete` line at all.
- **⚠ A placeholder token can now be REPORTED, which it never could before.** `is_placeholder` no
  longer means "skip" everywhere: in the subcommand (`:600`) and relation (`:613`) slots it still
  skips, but the verb slot now treats an angle placeholder as a **violation** unless it names the
  slot itself. If you touch that file, do not "unify" the three placeholder semantics — the
  asymmetry is the design, and it is pinned by tests on both sides.
- **`forge-contract-check.sh` still has ZERO runtime call sites** (re-verified). Only its own
  `.bats` executes it — but note the skeptic seat's correction to how this file has been phrasing
  that: a lint has no runtime call sites *by design*, and this one **is** reached by `make test` →
  `test-forge` → its bats suite, which runs it against the real corpus. Stop treating "zero call
  sites" as evidence the guard does not matter.

## Known state (updated 2026-08-04 by the AGE-24 session)

- **AGE-24 is DONE and shipped as v3.2.0. AGE-31 leads the queue.** AGE-30 is still blocked — it
  needs AGE-29 *and* AGE-31 as well. Confirm with `story list --ready`, not this line.
- **The AGE-32 session's measurement was exactly right, to the violation.** Span extraction on the
  real 29-file corpus yields **1** violation (`references/storyhook-contract.md:8`), where whole-line
  scanning yields 28 false positives and fenced-only yields 0-because-vacuous. **You do not need to
  re-measure this**; it is now pinned by a test that asserts the corpus carries exactly one
  suppression, at that file and token.
- **⚠ The unit handed to the checker now DIFFERS by fence depth, and that is deliberate.** Inside a
  fence the unit is the LINE; outside one it is each inline backtick SPAN. If you touch extraction,
  do not "unify" these — the span boundary is the entire reason the widening is safe. Scanning
  unfenced lines whole reintroduces all 28 false positives, and this guard gates `make test`.
  - Consequence for `START_RE`/`MID_RE` (**relevant to AGE-31, which edits `START_RE`**): outside a
    fence they now run against a span, not a line. A span is short and has no prose around it, so a
    relaxation that would be reckless line-wide is much safer span-wide. Measure anyway.
- **⚠ The full gate was green WITHOUT any bypass, and `plugin-content-drift` cleared on the bump.**
  `MAKE_EXIT=0`, **596 bats assertions + 238 shell checks, zero failures, 18 suites, zero skipped**.
  Every `skip` string in the log is a *test name* (suites that test skip behaviour), not a skipped
  suite — don't misread that grep. Five sessions running with no `SKIP_PREPUSH_TESTS=1`.
- **Ordering that actually works, and costs ONE gate run instead of two.** The protocol's step 7
  reads as "run the full gate → bump → run the full gate again" (~4h). Instead: run the *targeted*
  suites your change touches (`make test-forge` and the fast guards took ~5 min total), bump, then
  run the full `make -k test` **once**, post-bump. The state that ships is the state the full gate
  verifies, which is strictly the better guarantee, and it halves the wall clock.
- **⚠ Do NOT background a mutation loop that restores a file afterwards.** A 2-minute tool timeout
  killed one mid-loop *between* the bats run and the `cp` restore, leaving a mutated script in the
  working tree that looked like a finished run. Caught only by diffing the extractor by hand.
  Restore first and assert the restore, or run mutations one tool call each.
- **`forge-contract-check.sh` still has ZERO runtime call sites** (re-verified again). Only its own
  `.bats` executes it.

## Known state (updated 2026-08-04 by the AGE-32 session)

- **AGE-32 closed the F103 guard's suppression gap — AGE-24 and AGE-31 are UNBLOCKED.** Confirm
  with `story list --ready` rather than trusting this line.
- **⚠ Measure the widening before you write it — AGE-24's job just got much smaller.** A naive
  full inline widening of `forge-contract-check.sh` produces **28 violations on the real 29-file
  corpus, every one a false positive**, in four classes. But **span extraction fixes three of the
  four classes at once**: extract each inline-backtick span and feed *the span* to the checker
  rather than the whole line. Measured residual after span extraction + AGE-32's relation-slot
  placeholder exemption: **exactly ONE violation in the entire corpus** —
  `references/storyhook-contract.md:8`, the negative example. That one is what AGE-32's marker is
  for. Do not re-derive this by hand; the simulation takes ~2 minutes.
  - The three mechanical classes are: English prose (`story data lives in a SQLite store`),
    unstripped trailing backticks on the harvested token, and placeholder signatures in the
    relation slot. Span extraction kills all three, because the span *is* the invocation —
    a backticked `story relate` followed by the prose word "call" yields no token at position 1
    at all, so there is nothing to misread.
- **The suppression marker is now live**, and it is NOT an ordinary ignore-comment. A doc denies a
  dead form by annotating that line: `<!-- contract-check: expect-dead <token> -- <reason> -->`.
  Four things will bite you if you assume otherwise:
  - **It is bound to the reported TOKEN, not the line.** A marker naming the wrong token does not
    suppress *and* is reported as `token_mismatch`. You cannot mute a line.
  - **A marker that suppresses nothing FAILS the gate** (`stale_suppressions`, folded into
    `contract_ok`). Markers are found by a whole-file scan deliberately independent of extraction,
    so one at fence depth 0 today reports `not_scanned` rather than passing silently. **So the
    marker for `storyhook-contract.md:8` must land INSIDE AGE-24's PR — add it in the same commit
    that widens the scan, never before, or the gate reds.**
  - **The reason is mandatory.** No reason → `malformed`, suppresses nothing.
  - **A placeholder token (`<token>`) is a signature, not a suppression** — that is what lets the
    convention be written down inside a scanned file without self-applying.
- **A latent false positive was fixed on the way**: the guard exempted placeholders in the
  *subcommand* slot but had no equivalent for the *relation* slot, so a fenced
  `story relate <a> <relationship> <b>` was reported as an unsupported relationship. Reachable
  today, not only under widening — no committed forge doc merely happens to have one inside a fence.
- **`forge-contract-check.sh` still has ZERO runtime call sites** (re-verified). Only its own
  `.bats` executes it. It is shipped and cache-keyed, so it costs a bump, but nothing in the
  pipeline calls it.
- **Five mutations were run to prove AGE-32's tests are worth having**, each went red: token-blind
  suppression, marker scan narrowed to the extracted region, `stale_suppressions` dropped from
  `contract_ok`, placeholder-token exemption removed, mandatory-reason requirement removed. Note
  the third reds only the two tests whose *sole* signal is staleness — tests that also carry a real
  violation stay red for the right reason, so a naive "all four must go red" expectation is wrong.
  If you extend this mechanism, mutate before you trust the suite.
- **`make -k test` had exactly ONE red across the whole run**, the expected
  `test_shipped_content_matches_tagged_release`, cleared by the bump. **No `SKIP_PREPUSH_TESTS=1`
  was needed** — four sessions running now. 593 bats assertions across 5 plans, all 18 suites
  reached, zero suites skipped. **AGE-21's `test-cli-rm.sh` flake did NOT fire, and AGE-35's
  `test-bootstrap-dirs.sh` PASSED** under the full run.
- **Wall clock for the full gate was ~2h**, matching AGE-11's figure. Start it early and do not
  touch the working tree while it runs — `forge-integrity.bats` snapshots the real tree (AGE-34).

## Known state (updated 2026-08-04 by the AGE-28 session)

- **⚠ `story next` says AGE-12. Take AGE-32 instead — this is deliberate, not drift.** Both are
  `todo`, `ready` and `medium`, so `story next` is breaking the tie by **ID order alone**. This
  table's own rule breaks it by the **dependency graph**: **AGE-32 unblocks three stories**
  (AGE-24, AGE-30, AGE-31 are all `blocked-by` it, directly or transitively, and storyhook keeps
  them out of `ready` until it closes), while AGE-12 unblocks none. Clearing AGE-32 returns three
  stories to the queue; clearing AGE-12 returns zero.
  - This is the one place the standing *"`story list` outranks this file"* rule needs care: trust
    `story list` for **state** (what is open/blocked/claimed — it is authoritative and this file
    goes stale within the hour), but the **ordering rationale** lives here, because `story next`
    cannot see it. Do not "correct" the queue to AGE-12.

- **⚠ THE REPO IS NOW AT v3.0.0 — the first MAJOR bump of this marketplace.** AGE-28 makes
  `deployit deploy` **refuse** an unacknowledged unoptimized archive, so a project that
  deliberately archives Debug (Lillist does) must commit `[build] allow_debug = true` before its
  next deploy works. CLAUDE.md's major criterion — *"behavior changes that require consumers to
  update"* — is met literally, so the chair ruled major over the two seats that guessed minor.
  - **The marketplace shares one `VERSION`, so every plugin moved to 3.0.0**, not just deployit.
    That is the honest aggregate signal (*something here breaks consumers*), but it is
    marketplace-wide and Mikey should know it was a deliberate call, not a slip.
  - Rejected counter-argument, recorded so it is not re-litigated blind: *"the CLI surface is
    purely additive (one optional table), so it is minor."* Strict semver treats **newly rejecting
    previously-accepted input** as breaking regardless of whether a symbol was removed — and
    AGE-33's lesson is asymmetric: under-signalling stranded every install, over-signalling costs
    a digit.
- **⚠ A companion Lillist story is OWED and NOT YET FILED.** Lillist's next deploy will fail until
  it commits `[build] allow_debug = true` (or changes `Apps/Lillist-iOS/project.yml:339-340`).
  This is intentional — the setting was previously invisible — but it is a cross-repo consequence
  landed from agentics. **File it against Lillist, not agentics.**
- **Story premises can be right in diagnosis and wrong in framing — AGE-28 was both.** Its stated
  defect reproduced exactly. But its claim that Option A is *"correct by default"* was falsified:
  Lillist's `archive: config: Debug` is **deliberate**, committed at `project.yml:339-340`, and
  **predates deployit's hardcode by one day** (2026-05-20, in *"feat(deploy): on-demand iOS test
  build deploy"*, vs `c383611` on 2026-05-21). deployit's Debug was never arbitrary — it encoded
  *"these are test builds"*, a premise that broke when deployit grew to publish moshtail releases
  and Developer-ID macOS GitHub releases. **Check the direction of causality before calling a
  downstream config a victim of your bug.**
- **⚠ `python3` on this machine is 3.9.6 and has NO `tomllib`.** So deployit's *regex fallback* in
  `_read_project_config` is the **only** TOML path that ever executes locally — and before AGE-28
  it ended `return {"toolchain": toolchain} if toolchain else {}`, silently discarding every other
  table. Two standing consequences:
  - **Any new `.deployit/config.toml` table must be added to the fallback**, or it is dead on
    arrival on this Mac. It is now `_parse_project_config_text()`, a pure function, so test it
    **directly** — a test that only drives `_read_project_config` passes vacuously on a 3.11+
    interpreter while proving nothing where it matters.
  - **Bools in that parser are *presence* tests** (`enabled\s*=\s*true`), not the quoted-string
    captures used for the `[toolchain]` keys. A quoted regex copied from those lines silently
    never matches an unquoted TOML bool.
- **`_meta.json` is written from an explicit key ALLOWLIST at two sites** (`_stage_ios_or_visionos`
  and `_stage_macos`). A field threaded only through `meta_full` is **silently dropped at both**.
  Worse, adding a key with `meta_full[k]` broke 4 existing tests with `KeyError`, because they call
  the staging functions directly. Advisory provenance fields are now read with `.get()`; the
  required keys stay strict so a genuinely missing one still fails loudly.
- **`do_release` is macOS-only** (`args.platform == "macos" and …`). Any gate keyed on it is
  **False for every iOS/visionOS deploy by construction** — a trap that cost two council seats
  their design. AGE-28 uses it as a *ceiling on an escape hatch*, never as a refusal trigger.
- **The deployit suite passed 50/50**, including AGE-21's flaky `test-cli-rm.sh`, which did **not**
  fire this run.

## Known state (updated 2026-08-04 by the AGE-27 session)

- **⚠ ANOTHER SESSION WORKS THIS BACKLOG CONCURRENTLY — `story list` outranks this file.**
  `AGE-4` and `AGE-5` went `todo` → `in-progress` → `done` *during* the AGE-27 session, and
  **PR #137 merged mid-flight** (`20c31d2`), closing **AGE-4, AGE-5, AGE-6, AGE-7, AGE-8 and
  AGE-10** in one go. AGE-27's own PR hit a merge conflict on this file as a result.
  Two standing consequences:
  - **Re-derive the queue from `story list` at session start.** This table is a snapshot and was
    wrong within the hour, twice. Trust it for *rationale*, not for *state*.
  - **Expect to merge `origin/main` into your branch before your PR will land.** Do not rebase —
    the branch is already pushed and force-pushing is banned. `git merge origin/main`, resolve,
    push again.
  The long-running **`#118` scope collision** this file warned about for eight sessions is now
  **resolved and closed** by #137. Ignore the stale collision note further down.
- **`AGE-28` (high) appeared mid-session from another session** — deployit archives with a
  hardcoded `-configuration Debug`, so every OTA build ever produced shipped unoptimized. It is
  `todo` and unclaimed, and it is the highest-priority open story, so it **leads the queue** on the
  table's own priority-first rule.
- **The repo is at v2.41.0, released and published.** AGE-27 itself needed no bump (it touched no
  shipped `plugins/**`), but PR #137 had landed **48 shipped files with no bump**, leaving `main`
  red and — far worse — leaving every install stranded on 2.40.1 content, because Claude Code
  caches plugins by version string. That is the **issue-#71 class**. Filed as **AGE-33**, fixed by
  a `minor` bump (PR #139), tag pushed clean, GitHub release published. `/semver validate` is
  all-PASS 6/6.
  - **The lesson for you: the bump is owed by whoever merges shipped content, and nothing gates
    it at merge time.** If you touch `plugins/**`, bump in your own PR (step 7). If you inherit a
    red `plugin-content-drift` you did not cause, attribute it before assuming it is yours:
    `git diff --stat origin/main HEAD -- plugins/ ':(exclude,glob)plugins/*/tests/**'
    ':(exclude,glob)plugins/**/*.bats' ':(exclude,glob)plugins/*/README.md'` — **empty means it is
    not from your branch.**
- **⚠ NEVER run two `make test` runs against this checkout at once.** `forge-integrity.bats`
  snapshots the **real working tree**, so a second run's fixture churn reads as tampering and you
  get ~7 spurious failures, some surfacing as confusing `jq: parse error` lines rather than clean
  assertion failures. This session lost a debug cycle to it: a background `make -k test` was still
  running when a `git push` fired the pre-push hook, which starts its **own** `make test`. All 19
  pass in isolation on the identical tree. Filed as **AGE-34**.
  - Practical rule: **run the gate, let it finish, then push** — and do not background a gate you
    are about to push behind. The hook re-runs the whole suite regardless, so a push costs ~2h on
    top of your own run; AGE-34 proposes a lock that would fix both the waste and the hazard.
- **⚠ `tests/storyhook-path-guard.sh` gained a LAYER 3 (AGE-27).** It greps an **allowlist** of
  repo-root agent-instruction files — `AGENTS.md`, `CLAUDE.md`, `README.md`, `.gitignore` — for
  retired storyhook *surfaces*: the per-repo directory **and** `mcp-config`. Two things will bite
  you if you don't know:
  - **The allowlist is pinned** (`test_layer3_allowlist_is_pinned`) and its entries are asserted to
    **exist** (`test_layer3_allowlist_entries_all_exist`). Adding a root instruction file, or
    renaming one, fails the suite until you update the pin deliberately. That is the point — a
    pathspec matching nothing passes vacuously.
  - **`CHANGELOG.md`, `PROGRESS.md` and `.planning/` are deliberately NOT scanned**, and a test
    pins that. They name these surfaces legitimately, to record or deny them. **This file is one of
    them** — which is why the paragraph you are reading can spell `mcp-config` out. Do not "tidy"
    that exclusion away.
- **`AGENTS.md` is now GENERATED.** It is byte-identical to `story scaffold agents-md` output below
  a `<!-- BEGIN GENERATED -->` marker, under a provenance header that survives regeneration. **Do
  not hand-edit it** — regenerate. A hand-edited copy is exactly how it came to teach three false
  things for a year.

## Known state (updated 2026-08-04 by the AGE-11 session)

- **The repo is at v2.40.1** (AGE-11 shipped a `patch` — the flag it deleted was a no-op, so
  nothing about forge's actual behaviour changed).
- **`make -k test` had exactly ONE red across the whole run before the bump**, and it was the
  expected `test_shipped_content_matches_tagged_release`. It cleared on the bump. **No
  `SKIP_PREPUSH_TESTS=1` was needed** — three sessions running now. Treat a bypass as a red flag.
  Wall clock was **~2 hours**, not the ~15 min this file used to claim; budget accordingly and
  start the run early. AGE-21's `test-cli-rm.sh` flake did **not** fire this run.
- **⚠ There is a NEW gate suite: `tests/storyhook-path-guard.sh` (`make test-storyhook-path-guard`).**
  It has two layers and they have deliberately different scopes — read the header before you
  fight it:
  - **Layer 1** bans `--extra-path` naming storyhook's retired per-repo dir, in any spelling,
    **repo-wide, no exceptions**. It matches the *unslashed* form too, because `.storyhook` and
    `.storyhook/` are the same git pathspec.
  - **Layer 2** bans the bare path name in **shipped content only**, reusing
    `plugin-content-drift.sh`'s `SHIPPED_PATHSPEC` verbatim. The `plugins/*/tests/**`, `**/*.bats`
    and `plugins/*/README.md` exclusions are **load-bearing, not laziness**: they preserve
    historical comments that name the retired path in order to *deny* it (e.g.
    `forge-crash-recover.bats:132`). Do not "tidy" them away — a guard you can satisfy by deleting
    true sentences is the wrong guard. If you change `SHIPPED_PATHSPEC` in one file, change it in
    both.
  - The guard **assembles the retired name from string fragments** rather than writing it out, so
    it does not trip its own scan. That is why it needs no self-exemption. Don't "simplify" it.
- **`tests/init.bats` and `tests/helpers.bash` still build a fake per-repo storyhook fixture.**
  Layer 2 does not reach them (they are not under `plugins/`) and that is **AGE-13's** job, not a
  miss.

## Known state (from the AGE-17 session)

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

### ⚠ Scope collision — resolved by PR, not yet merged

**Update (2026-08-04, from the #118 worktree session):** the collision below is resolved by
[PR #137](https://github.com/mikeydotio/agentics/pull/137), open against `main` but **not yet
merged** (worktree policy: stop after opening the PR, never merge from a worktree). It carries
**AGE-4, AGE-5, AGE-6, AGE-7, AGE-10** in full, plus AGE-8's remaining scope (`obviated-by AGE-7`).
All five were claimed `in-progress` in storyhook before that PR's work started, so `story next`
already skips them — **do not restart any of the five**, and do not touch
`plugins/{rca,agents/references/cross-plugin-usage.md}` or the 9 WS-D plugins' `SKILL.md`
frontmatter/descriptions until PR #137 either merges or is closed. If you reach this point in the
queue before it merges, skip past all five rows and continue with the next open story; re-check
`gh pr view 137` rather than trusting this note indefinitely. Once it merges: `story move AGE-4
AGE-5 AGE-6 AGE-7 done`, and `story move AGE-8 done` per its own obviated-by note, then delete
these five rows from the queue table below.

Original collision note, kept for context: the user dispatched **GitHub issue #118 — "Realign
skills, agents, and model selection for the Claude 5 generation"** into its own worktree,
overlapping AGE-6 (WS-C) and AGE-7 (WS-D) — two agents editing the same skill files from
different branches would have conflicted. PR #137 also absorbed AGE-4 and AGE-5 (both `#118`
findings deferred from WS-B) and AGE-10 (the description-budget target AGE-7 was blocked on),
which were not part of the originally-flagged collision but are the same prompt-realignment
surface.

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
| ✅ | ~~**AGE-11**~~ | med | **DONE** — the dead `--extra-path` calls are gone and a two-layer guard stops them returning. Shipped as **v2.40.1** (patch). See "What AGE-11 turned out to be" below. Filed **AGE-26** and **AGE-27** on the way. |
| ✅ | ~~**AGE-27**~~ | high | **DONE** — `AGENTS.md` regenerated, `.gitignore:10` corrected, and a new Layer 3 guards the retired surfaces. **No bump.** See "What AGE-27 turned out to be" below; the council rejected the story's own stated fix. Filed **AGE-30**, **AGE-31**, **AGE-32** and split **AGE-29**. |
| ✅ | ~~**AGE-4**, **AGE-5**, **AGE-6**, **AGE-7**, **AGE-10**, **AGE-8**~~ | med/low | **DONE — PR #137 merged** (`20c31d2`) while AGE-27 was in flight. All six are `done` in storyhook. The `#118` scope collision this file warned about for eight sessions is **resolved and closed**. |
| ✅ | ~~**AGE-33**~~ | crit | **DONE — released as v2.41.0** (PR #139). #137's 48 shipped files had never reached any install. See the version bullet above. |
| ✅ | ~~**AGE-28**~~ | high | **DONE — shipped as v3.0.0**, the marketplace's first major. The hardcode is gone, the scheme decides, and an unacknowledged unoptimized archive is now refused on every platform. See "What AGE-28 turned out to be" below. **Owes a Lillist-side story.** |
| ✅ | ~~**AGE-32**~~ | med | **DONE — shipped as v3.1.0.** Token-bound `expect-dead` marker, ruled unanimously by `/council-vote`. Unblocks AGE-24 and AGE-31. See "What AGE-32 turned out to be" below. |
| ✅ | ~~**AGE-24**~~ | med | **DONE — shipped as v3.2.0.** Inline backtick *spans* are now scanned outside fences; the `storyhook-contract.md:8` marker landed in the same commit. See "What AGE-24 turned out to be" below. Filed **AGE-37**. |
| ✅ | ~~**AGE-31**~~ | med | **DONE — shipped as v3.3.0** (PR #146). Angle placeholders in the verb slot are violations; only a placeholder naming the slot itself is exempt, by equality-per-segment. See "What AGE-31 turned out to be" below. Filed **AGE-38** and **AGE-39**. |
| ✅ | ~~**AGE-29**~~ | med | **DONE — shipped as v3.4.0.** The fence detector now models structure instead of toggling. Its own prescribed fix was **disqualified by measurement** — see the AGE-29 block above. **Closed AGE-41 for free.** Filed **AGE-40**, **AGE-42**, **AGE-43**. |
| ✅ | ~~**AGE-30**~~ | med | **DONE — shipped as v3.5.0.** The shipped script gained a repeatable `--file`; a new repo-local `tests/storyhook-contract-root.sh` supplies the pinned list (`AGENTS.md` + `CLAUDE.md`), so the scan set stays shape-based in the plugin and the filename knowledge stays in the repo. Council ruled the interface by ranked-choice majority after a 1-1-1 round-1 split. See the AGE-30 block above — the story's reach table understated the value by a third and its bump level was wrong. Filed **AGE-44**. |
| ✅ | ~~**AGE-12**~~ | med | **DONE — shipped as v3.6.0.** The failed claim now confirms the vocabulary via `story state list` and refuses with `reason: "claim-state-missing"` + `story doctor --fix`. **The story's central claim was false** — the cause was already named; only the remedy and the discriminator were missing. See the AGE-12 block above. Filed **AGE-45** and upstream **storyhook SH-180**. |
| ✅ | ~~**AGE-21**~~ | med | **DONE — no bump** (test-only). Its stated cause was false, and so were the two theories that replaced it. The real defect was `git log \| grep -q` under `pipefail` returning **141 on a successful match**; the fix is a shape fix, not a longer retry. See the AGE-21 block above. Filed **AGE-47** (closed here), **AGE-48**, **AGE-49**. |
| ✅ | ~~**AGE-19**~~ | med | **DONE — no bump** (root `tests/`, `Makefile`, `CLAUDE.md` only). The story was right and its numbers wrong both ways: **87** failures, not ~60; **3** suites, not 7. `tests/storyhook-version-pin.sh` pins `STORYHOOK_MAJOR=2`. Its regex is **strictly anchored** — an unanchored scan reads a version out of a warning banner and passes a major-3 binary. Make prerequisite edges were measured **better** and still declined (they red the meta-gate). See the AGE-19 block above. Filed **AGE-50**. |
| ✅ | ~~**AGE-22**~~ | med | **DONE — no bump** (root `tests/`, `Makefile`, `CLAUDE.md` only). `tests/bounded-capture-guard.sh` pins four censuses; it reds on any new `timeout` site or wrapper call **by design**. The story's wording was too broad — implementing it literally reds a *correct* line (`test-repro.sh:35`). A derived closure and a redirect heuristic were both proposed and both **withdrawn on measurement**. See the AGE-22 block above. Filed **AGE-51**. |
| — | **AGE-8** | low | **Do not work this story.** It is `obviated-by` AGE-7; PR #137 carries its remaining scope too. Close both AGE-7 and AGE-8 once #137 merges. |
| 12 | **AGE-9** | low | Council-decision story, independent. |
| 13 | **AGE-13** | low | Council-decision story, independent. |
| 14 | **AGE-23** | low | Skill `references/*.md` are cited skill-relative but ship at plugin root — see below. **Confirmed live again this session:** the council skill's own `references/council-protocol.md` failed to resolve skill-relative and cost a wasted tool call. |
| 15 | **AGE-25** | low | AGE-17's own safety mechanisms are unproven — see below. |
| ✅ | ~~**AGE-26**~~ | med | **DONE — shipped as v3.7.0.** `story` left `is_always_safe` for a verb-aware `is_safe_story()`. Return 2 is licensed **only by an existing peer** in `is_known_destructive`, which makes the bucket self-limiting and made a rename unnecessary. The story missed the premise's third clause (`story update` replaces its own binary) and the chair's own verb list missed `plugin` and `store`. A narrowing guard was proposed, voted for and **withdrawn by all three seats** — it would have read the comment describing the defect as a mandate to keep it. See the AGE-26 block above. Filed **AGE-52**, **AGE-53**, **AGE-54**. |
| ✅ | ~~**AGE-61**~~ | med | **DONE — no bump** (`CLAUDE.md`, `PROGRESS.md`, `.gitignore` only). Three of the four worktrees removed, `dual-host` preserved for **AGE-66**, and step 10 decoupled from any local `main` ref. **Closed AGE-67 in the same PR** — a tracked runtime lock made two worktrees permanently unreclaimable. This file's own warning about the worktrees was **false** (all four branches were merged; the hazard was uncommitted files), and the story's prescribed remedy was the **less safe** of the two. A gate guard was designed and withdrawn by its own author. See the AGE-61 block above. Filed **AGE-66**, **AGE-68**. |
| 17 | **AGE-20** | low | Deliberately deferred — land it alone, never beside a behaviour fix whose proof depends on those fixtures. |
| 18 | **AGE-43** | med | **Next up.** A false positive reachable on the shipped script *today*, with a known one-token fix — bound the argument capture so it stops running past an inline span's closing backtick. ⚠ Its own AGE-29-block entry warns: **do not sell that fix as a safety precondition for a detector change**, because it bounds the *argument* capture, not the *verb* capture. Skips AGE-39 deliberately — see the **Next story** cell. |

**AGE-2, AGE-3, AGE-11, AGE-14, AGE-15, AGE-16, AGE-17 and AGE-18 are already `done`** — do not
touch them.

### What AGE-31 turned out to be — the diagnosis was right and the PREMISE was false

AGE-31's stated defect reproduced exactly on the first try. But the premise its fix direction
rested on — *"there is no legitimate `story <verb> ...` prose in these docs"* — is **false**, and
the counterexample is in this repo. Five things worth carrying forward:

1. **The counterexample is in the ADR that states the rule it violates.**
   `docs/decisions/forge-hardening.md:64` writes `` `story <verb> …` `` in an inline span, in a
   true sentence describing this guard — and its next paragraph reads *"A guard you can satisfy by
   deleting true sentences is the wrong guard."* A bare widening reports
   `verb_violations:["<verb>"]` on it. It is **not in the scan set today**, so the story's
   precondition test (*"verify whether any scanned doc legitimately writes `story <verb>`"*) came
   back clean — but it asked the wrong question, because **AGE-30, the story this one exists to
   unblock, is exactly what moves that boundary.** A precondition evaluated against a corpus your
   own dependent will change is not a precondition.
2. **Two failure directions are not interchangeable, and the tiebreaker is not lexicographic.**
   Three candidate wildcard rules on one 14-token table: **segment equality 14/14**; substring
   8/14 with all 6 misses **silent false negatives** (`<transaction>` via "action", `<verbatim>`
   via "verb", `<cmdlet>` via "cmd"); closed-set 11/14 with all 3 misses **false positives on true
   sentences**. Segment equality is not a compromise — it beats both on every differing row. The
   skeptic seat then refined the principle it had been asserting: *"loud-beats-silent is a
   tiebreaker that holds when the two classes are comparably likely"* — substring's misses were
   ordinary English and unbounded; the residual `<command-id>` class is contrived.
3. **A fix for a related bug can leave the blocking defect fully intact.** The seat that wanted
   `classify_stale_markers` narrowed offered a verified one-line AGE-37 origin fix as the unblock.
   Measured: with that fix applied, the false positive **survives** — the kind relabels
   `form_is_valid` → `not_scanned` and the verdict stays `contract_ok:false` on a correct
   document. **Check that a proposed prerequisite actually changes the verdict, not just the
   message.** That measurement is the whole reason AGE-37 stayed out of this PR.
4. **An invariant can be enforced from outside the thing it constrains.** The council deadlocked
   between AGE-32's *"a suppression mechanism must be able to fail"* and a measured false positive.
   Resolution: keep the script permissive and assert
   `markers == suppressions + stale_suppressions` **in the bats suite**, over the real corpus,
   where it cannot manufacture a false positive. Verified to catch the exact case the gap leaves
   open (`markers=1, accounted=0`). The residual is logged as **AGE-39** with a redesign trigger,
   per CLAUDE.md's deliberate-tech-debt rule.
5. **The chair produced a vacuous green mid-council and nearly balloted on it.** Scratchpad script
   variants were run **without a root argument**, so `DOCS_ROOT` defaulted to `SCRIPT_DIR/..` and
   they scanned *nothing* — read as a real 1→0 behaviour change. Fix: **assert `files_scanned` in
   every comparison.** This is the AGE-18/21/27 class, self-inflicted, in the session whose whole
   subject was a guard that must not lie.

**Design ruled by `/council-vote`** — round 1 was a **perfect three-way cycle with every seat
voting against its own proposal**; all three had independently chosen the same regex and all three
ruled fix-in-this-PR, so the questions *as filed* were settled 3-0 before any vote. After
deliberation the panel converged on seat-1-rev, 2 of 3 first preferences, seat 2 formally
withdrawing and merging onto it. Full audit trail including the recorded dissent:
`.council/age31-placeholder-verb/DECISION.md`.

### What AGE-24 turned out to be — the story was right, and the previous session had done the hard part

AGE-24's diagnosis reproduced exactly and its prescribed approach was correct as written. The
session's real work was proving the boundary rather than choosing it, because AGE-32 had already
measured the answer. Four things worth carrying forward:

1. **The unit of extraction, not the scope, is what makes a widening safe.** Three candidate units
   on the same corpus: fenced-line-only → **0** violations (vacuous — the majority of the contract
   unread); whole unfenced line → **28**, all false positives; unfenced **span** → **1**, the
   deliberate negative example. Same files, same checks, three completely different guards. When a
   story says "widen the scan", the load-bearing question is *what you hand the checker*, not *how
   much text you reach*.
2. **A mutation can prove an ordering constraint, not just a code path.** PROGRESS warned that the
   `storyhook-contract.md:8` marker had to land *inside* this PR. Reverting the extractor to
   fenced-only (mutation M1) reds `real committed forge docs are clean` — because the marker then
   sits on an unscanned line and is a `not_scanned` stale suppression. That turned a piece of
   handoff folklore into an executed fact. **Three mutations were run and each went red on exactly
   the right tests**, no more: fenced-only and whole-line each red four suites, first-span-only red
   exactly one.
3. **A test whose *name* survives a behaviour change is a liability.** `forge-contract-check.bats:175`
   ("ignores inline single-backtick template signatures") still *passed* after the widening — but for
   a completely different reason: the span is now scanned and passes because `<relationship>` is a
   placeholder wildcard. A passing test asserting the right value for the wrong reason is exactly
   the vacuous-green shape this repo keeps finding. It is retitled and paired with an effect oracle
   (a signature and a concrete dead relation on **one line**, only the concrete one reported), which
   is the assertion that can tell the two reasons apart.
4. **Two gate runs are not required, and the cheaper order is also the stronger one.** Targeted
   suites first (~5 min), then bump, then **one** full `make -k test` post-bump — see the ordering
   bullet up top. The state that ships is the state the full gate verified.

### What AGE-32 turned out to be — the story was right, and the answer was smaller than feared

AGE-32's diagnosis reproduced exactly: a naive widening yields 28 violations on the real corpus,
all false positives, in the four classes the story named. Two things it did **not** know:

1. **Three of the four classes have ONE fix, not three.** Extracting the inline-backtick *span* and
   checking the span — rather than the line the span sits on — dissolves prose, trailing-backtick
   artifacts and relation-slot signatures simultaneously. Measured residual: **1 violation, corpus-
   wide.** That is a gift to AGE-24, which the story framed as three mechanical fixes plus a design
   decision.
2. **The undecidable class is a population of one** (`storyhook-contract.md:8`). The mechanism was
   designed for a known site count of one — which is an argument for making it *strict*, not loose.

**The council was unanimous 3-0 in round one, with two of three seats voting against their own
proposals** and each naming the precise defect in their own design. Both losing seats then asked
for the same single graft from the runner-up. Full audit trail:
`.council/age32-negative-example-suppression/DECISION.md`.

**Four lessons worth carrying forward:**

1. **A suppression mechanism must be able to fail.** The losing line-scoped ignore "can never itself
   fail" — its own author's words. Binding the marker to the *reported token* turns it into an
   executable assertion that the form is still dead, so the guard gets **stronger** with a marker
   than without one: if storyhook ever made the form real, the doc's denial becomes false and the
   marker reports `form_is_valid`.
2. **Site the staleness check where it can actually fire.** Seat 2's design put it inside the
   per-line loop over *extracted* lines — where it could never fire for a marker on a line the
   extractor never reads, which is the exact case it existed to catch. Moving it to a whole-file
   scan is the difference between a guard and a decoration. This is the AGE-18/AGE-21/AGE-27 class,
   caught in design review instead of six sessions later.
3. **An escape hatch needs an exemption for its own documentation.** A marker whose token is a
   placeholder is a signature, not a suppression — otherwise writing the convention down inside a
   scanned file self-applies. The repo has hit this before: `tests/storyhook-path-guard.sh`
   assembles the retired name from string fragments for the same reason.
4. **Expect a mutation to red the *right* tests, not all of them.** Dropping `stale_suppressions`
   from `contract_ok` reds only the tests whose sole signal is staleness; the ones that also carry a
   real violation stay red legitimately. A "they should all go red" expectation was wrong and would
   have sent a session hunting a non-bug.

### What AGE-28 turned out to be — the council's sharpest round yet

The defect reproduced exactly as filed. What the story got wrong was its **framing**, and both of
its proposed options were rejected — Option A as insufficient, Option B's value key outright.

**Round 1 was split B=2 / C=1 / A=0 with EVERY seat voting against its own proposal.** That has not
happened before in this repo. After one deliberation round all three **independently converged on
the same design**, each abandoning the half of its own proposal the others had holed. Full audit
trail: `.council/age28-archive-configuration/DECISION.md` (14 chair-verified facts).

**What shipped:** delete the hardcode and pass no `-configuration` ever; ask xcodebuild itself
(`-showBuildSettings -json … archive`) what the archive resolves to; refuse an *unacknowledged*
unoptimized archive on **every** platform via a substance-based ladder
(`SWIFT_OPTIMIZATION_LEVEL` → `GCC_OPTIMIZATION_LEVEL` → unresolved); `[build] allow_debug = true`
acknowledges a deliberate one; `do_release` is a **ceiling on that hatch**, never the trigger;
unresolved hard-fails and `allow_debug` does not silence it; and the verdict is **persisted** to
`_meta.json` + the index entry.

**Six lessons worth carrying forward:**

1. **Measure the premise, not just the defect.** The story's "moshtail's scheme already says
   Release, so this is correct by default" was true for 3 of 4 projects and false for the fourth —
   and the chair's own counter-framing ("Lillist would be silently left broken") was *also* false,
   because Lillist's Debug is deliberate and predates the bug. **Both** the story's framing and the
   chair's first correction of it were wrong. Facts measured after dispatch changed the outcome
   twice; that is why they were injected into the ballot rather than held.
2. **A gate's stated predicate and its actual predicate can differ — check.** Two seats designed a
   refusal at "the point of irreversibility" and both actually built one at "macOS", because
   `do_release` is platform-scoped. Seat 1's own words: *"I believed I was drawing the boundary at
   reversibility; I actually drew it at platform… and I shipped it."*
3. **Never gate on a name when the substance is available.** A `Release`-*named* configuration
   built `-Onone` passes every name-based check. The optimization level is persisted alongside the
   name for exactly this reason: *the name is the field that can lie.*
4. **Absence can be the healthy signal.** A real Release archive **omits**
   `SWIFT_ACTIVE_COMPILATION_CONDITIONS` and `GCC_OPTIMIZATION_LEVEL`. A proposal that hard-failed
   on "missing keys" would have refused every correct build, and `None.split()` would have crashed
   the happy path. Measured, not reasoned.
5. **Ask the component whose answer is definitionally correct.** Both the `.xcscheme` XML parser
   and the `project.yml` reader were rejected as *second implementations of Xcode's own
   resolution*. Note `_read_yaml_scalar` is a first-occurrence regex and every Lillist
   `project.yml` orders `run: config: Debug` **before** `archive:` — so reading it returns the
   **run** configuration. A guard built on that would have lied.
6. **Mutate your tests before you trust them.** Three mutations were run and each went red:
   re-adding the hardcode, emptying the acknowledged warning list, and silently gating the refusal
   to macOS. The last is caught by an **invariance assertion** (the unacknowledged verdict must be
   identical across all six platform × publish pairs), which a row-by-row table alone would miss.

### What AGE-27 turned out to be — the story's *diagnosis* was right and its *prescription* was wrong

All three false claims reproduced exactly as filed. But AGE-27's stated durable fix — "extend
`forge-contract-check.sh`'s scan set to repo-root agent-instruction files, **which would have
caught claim #2 automatically**" — was **rejected unanimously by `/council-vote` (3-0)**, and the
premise underneath it was measured false. Two of three seats voted against their own proposals.

**Measure the guard before you trust a story that says the guard would have caught it.** Copying
the current `AGENTS.md` into a fixture's `references/` — so scan scope was *not* the variable —
flagged exactly **1 of 5** bad invocations. The other four were missed for reasons the story did
not know, and each is now its own story:

| Missed | Why |
|---|---|
| `story <id> is done` (:21) | **twice** — an indented fence (**AGE-29**) *and* a `<placeholder>` in the verb slot (**AGE-31**) |
| `story context` (:9) | indented fence (**AGE-29**) |
| `story HP-<n>` ×3 (:34,:36,:37) | inline backticks at fence depth 0 (**AGE-24**) — three id-first claims the story's table never listed |

**The load-bearing correction: the durable fix never had to live in `forge-contract-check.sh`.**
Every option the chair framed inherited that assumption from the story. Three chair-verified facts
killed it:

- `forge-contract-check.sh "$(pwd)"` at repo root → `{ok:true, contract_ok:true, files_scanned:[]}`
  — **PASS having read nothing.**
- `DOCS_ROOT` defaults to the forge *plugin* root, so a `$DOCS_ROOT/AGENTS.md` line is **dead** in
  the default path.
- The script has **zero runtime call sites**. It is shipped and cache-keyed, but only its own
  `.bats` ever executes it.

And its reach is a fraction *by construction*: 28% of the regenerated file today, 34% with AGE-29,
and a **64% ceiling** even with AGE-24 fully implemented — because `forge-contract-check.bats:175`
deliberately requires placeholder signatures stay ignored and 19 of 35 inline spans carry them.
**"Make the guard read what it claims to read" is not reachable in one PR.**

So the guard went into `tests/storyhook-path-guard.sh` instead, as Layer 3: a raw `git grep`, which
reads **100% of every file it scans by construction** — no fence depth, no backtick reachability,
nothing to be wrong about. Repo-local, so no bump and no AGE-24 collision. Seat 1's framing of why
that is a boundary and not a dodge: these are **two different defect classes** — myth eradication
(fixed dead strings) vs grammar conformance (live-binary vocabulary) — and an **exclusion list
fails closed** where the hand-maintained **scan list** the story proposed **fails open**.

**Four transferable lessons:**

1. **A partial guard on a file is worse than none if its green will be read as file coverage.**
   Shipping the story's fix would have manufactured a fourth instance of the AGE-16/AGE-18/AGE-21
   class inside the PR whose whole purpose was deleting false claims.
2. **Deferral is only honest if it re-enters the queue mechanically.** AGE-30 carries `blocked-by`
   edges to AGE-24/29/31, not a note in this file. Verified it does not appear in
   `story list --ready`. *"Prose in PROGRESS.md is not a mechanism. A blocked-by edge is."*
3. **Don't hand-trim a generated artifact.** The council's first instinct was to prune the 131
   generated lines; its author withdrew that, because hand-editing is precisely how the file rotted.
   It is now byte-identical to the generator below a marker, with the header above it.
4. **Verify the severity premise, not just the defect.** AGE-27 was `high` because `AGENTS.md` is
   "auto-discovered by every agent, unprompted". Unverified — and this session's own context loaded
   three `CLAUDE.md` files and **no** `AGENTS.md`. The fix was still right; the priority probably
   was not.

**Correction to this file:** the "Either order works" line below is **falsified** — order is
strictly constrained, because scan scope is a *multiplier* on extraction reach. The collision is
moot anyway: AGE-27 did not touch `forge-contract-check.sh` at all.

Full audit trail: `.council/age27-pr-scope/DECISION.md`.

### ⚠ AGE-27 × AGE-24 both edit `forge-contract-check.sh` — pick an order deliberately

They are orthogonal widenings of the same script: **AGE-24 widens *what text* is scanned** (it only
reads inside fenced blocks today, so inline-backtick prose is invisible), while **AGE-27's durable
half widens *which files* are scanned** (`:290-297` builds the list from `<root>/references/*.md`
plus `<root>/skills/*/SKILL.md`, so repo-root `AGENTS.md` is in neither set). Either order works;
whichever lands second must rebase onto the first.

**AGE-27 splits cleanly if you want it to.** Its text half — regenerate `AGENTS.md`, fix
`.gitignore:10` — touches neither `plugins/**` nor `forge-contract-check.sh`, so it needs **no
version bump** and cannot conflict with AGE-24. A defensible alternative to the queue order above
is: land AGE-27's text half now, fold its guard-scope half into AGE-24, and close AGE-27 against
that PR. Decide with `/council-vote`, don't just drift into it.

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
| **AGE-26** | med | **Filed by the AGE-11 session.** `greenlight.sh` auto-approves the *entire* `story` CLI (`story) return 0 ;;`). Its stated grounds — "only mutates a git-tracked per-repo dir, so a `git checkout` away from reverted, never leaves the project directory" — are false in every clause since storyhook 1.0.0. **AGE-11 already corrected the comment** (comment-only, two hats) and pointed it at this story; what is left is the judgement: `story delete` / `story purge --force` / `story project delete` are auto-approved against un-revertible global state shared by every repo on the machine. Options in the story: (a) keep the blanket allow, since the real justification is the forge hot path (F076/F077) and that survives; (b) split the verb surface — but note AGE-17's lesson, a first-token match cannot tell `story project list` from `story project delete`, so it needs two-token depth. |
| **AGE-27** | **high** | **Filed by the AGE-11 session.** Repo-root `AGENTS.md` (54 lines, a stale storyhook-1.x generated artifact) teaches agents three false things: the retired per-repo dir is "version-controlled project data, do NOT gitignore it"; `story <id> is done` (**verified: `error: unknown command`, exit 2** — and `storyhook-contract.md:7-9` explicitly says no id-first form exists); and an entire "MCP Server" section with `story mcp-config` (**verified: exit 2** — and `storyhook-contract.md:3-4` says flatly "There is no MCP server"). `.gitignore:10` carries the first claim too. **Higher stakes than the forge-internal case AGE-11 fixed**: root `AGENTS.md` is read by convention, unprompted, so it reaches agents that never load a forge skill. Mechanical fix is `story scaffold agents-md`, but that swaps 54 reviewed lines for ~130 unreviewed ones promoting surfaces forge is silent on — needs a read-through, not a ride-along. |

### What AGE-11 turned out to be — the diagnosis was right, the *inventory* was badly short

AGE-11's stated cause was correct and reproduced immediately: `story help storage` says a repo
"carries a single committed file — `.storyhook.toml` — … and no story data at all", and
`forge-step-exit.sh` skips a nonexistent `--extra-path`, so all three calls were dead no-ops. What
the story got wrong was **size**:

1. **9 sites → 26 occurrences across 12 files.** Even the audit-correction comment (which raised 6
   to 9) undercounted by a factor of ~3. Two of the misses mattered:
   `plugins/greenlight/hooks/greenlight.sh:471` (a *different plugin*) and
   `plugins/forge/bin/forge-crash-recover.bats:132` (a mention that is **correct** — it names the
   retired path in order to deny it). **Grep the whole tree before you trust any "Where" list in
   this backlog.** Two of three council seats independently found the same missing site the chair
   had missed.
2. **The myth had escaped `plugins/` entirely** — repo-root `AGENTS.md:45` and `.gitignore:10`
   carry it too. Filed as **AGE-27** (high), because `AGENTS.md` also documents two commands that
   do not exist.

**The guard-shape lesson (the genuinely contested part).** The chair proposed one exceptionless
literal ban. The council rejected that shape unanimously, for a reason worth keeping:

> A guard you can satisfy by **deleting true sentences** is the wrong guard.

Some documentation has to *name the wrong thing in order to correct the reader* — and an
LLM-facing doc especially, because omission leaves a wrong prior intact where only negation
overwrites it. Hence two layers with different scopes: exceptionless for the *invocation form*
(nobody ever legitimately writes it), shipped-content-only for the *bare name* (historical
rationale comments live in `.bats` and belong there). The exclusions are reused from
`plugin-content-drift.sh` rather than invented, so "shipped" has one definition.

Two more things carried forward:

- **AGE-17's mistake was nearly repeated.** The first two guard proposals matched only the spelling
  **with** the trailing slash — but the same flag with the *unslashed* spelling is the identical
  git pathspec and would have sailed through green. Both authors conceded this and switched. When
  you write a guard, enumerate the *equivalent spellings*, not the one you happened to find.
- **The guard's first catch was this file.** An earlier draft of the bullet above wrote the banned
  flag-and-path pair out in full, to explain it — and Layer 1 blocked the push. That is the layer
  working as specified, not a false positive to file down: prose can always describe the pattern
  without typing an executable-looking invocation, and keeping Layer 1 genuinely exceptionless is
  worth more than the two words it cost to reword. **Expect this if you write about the defect.**
- **The effect oracle was worth it.** The "silently skips a nonexistent path" test asserted only
  exit 0, which would still pass if the script died right after the staging loop. It now asserts
  the commit, the state.json patch and the freshen fallback — and a mutation (dropping the
  `[ -e "$p" ]` guard) was run to **prove the new assertions actually go red**. Do this; it is
  cheap and it is the difference between a test and a decoration.

**Design ruled by `/council-vote`** — unanimous 3-0 in round one, with both losing authors voting
against their own proposals after naming the specific defect in each. Full audit trail:
`.council/age11-storyhook-extra-path/DECISION.md`.

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
git fetch origin main          # updates origin/main; needs no local `main` ref
git push origin v<X.Y.Z>       # clean first push, no force needed
/semver validate               # expect all-PASS
```
⚠ **Never `git switch main` here, and never make a release depend on a local `main`.** That line
used to read `git switch main && git pull --ff-only`, and it is what AGE-61 removed: a leftover
linked worktree holding `main` makes it fail outright (a branch can be checked out in only one
worktree), and it failed at the worst possible moment — *after* the PR had already merged, with a
tag still unpushed. Nothing needs it. Measured 2026-08-05:

- **A tag push works from any HEAD.** Tag refs are repo-global, and the org is merge-commit-only,
  which preserves your branch's SHAs into `main` — so the tag `/semver bump` cut on your branch is
  still correct after the merge. No re-pointing, no force.
- **`/semver validate` is branch-agnostic.** `cmd_validate` (`semver-cli:969`) reads no branch;
  only `bump` and `set` check one.
- **No repo code resolves a local `main` at all** — `git grep -E 'switch main|checkout main|pull
  --ff-only'` hits this file and nothing else.

Do **not** re-add a `push origin --delete <branch>` line either: the repo sets
`delete_branch_on_merge: true`, so `gh pr merge` has already removed the remote branch and the
explicit delete just errors.
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

### Stories filed by the AGE-27 session

| Story | Pri | What | Blocked by |
|---|---|---|---|
| **AGE-29** | med | *Retitled + split.* Now the **indented-fence** half only: `forge-contract-check.sh:409`'s fence detector is `/^```/`, anchored at column 0, so a fence indented inside a numbered list is never scanned. **Measured free**: the relaxation produced 0 new violations on the real 27-file corpus with 23/23 bats green — but it is shipped content, so it still costs a bump and a full gate. | — |
| **AGE-30** | med | `forge-contract-check.sh` cannot reach repo-root agent-instruction files. This is AGE-27's residue and covers **claim #2 only**. An **interface** decision (file args vs multiple roots vs a repo-local caller), not a scan-list append — `:284-288` says the scan set is deliberately shape-based, "not a hand-maintained filename list". | AGE-24, AGE-29, AGE-31 |
| **AGE-31** | med | *Split from AGE-29.* The **placeholder-verb** half: `START_RE` demands `[A-Za-z]` after `story `, so `story <id> is done` never matches — the guard cannot see id-first grammar in the spelling docs actually use. | AGE-32 |
| **AGE-32** | med | **The unblocker.** `forge-contract-check.sh` has no way to exempt a doc that names a dead form *in order to deny it*. `plugins/forge/references/storyhook-contract.md:8` quotes `story HP-N is done` inside the sentence saying it does not exist — any inline widening reds the gate on a **correct** document. Measured: a full inline widening produces **27 false positives** across 4 classes, 3 mechanical and 1 **undecidable**. Pick a suppression mechanism. Known freebie to hand the implementer: `:388` exempts placeholders in the *subcommand* slot but `:404` has no equivalent for the *relation* slot. | — |

### Stories filed by the AGE-27 session — second batch (post-merge)

| Story | Pri | What |
|---|---|---|
| ~~**AGE-33**~~ | crit | **DONE.** PR #137 landed 48 shipped `plugins/**` files with no bump, so `main` was red and no install could ever receive that content (issue-#71 class). Fixed by the `minor` bump to **v2.41.0**, tag pushed, release published. **Its preventative half is NOT done** — nothing gates the bump at merge time, so this recurs the next time a PR touches shipped content without bumping. Fold that into AGE-34's work or file it. |
| **AGE-34** | med | `forge-integrity.bats` snapshots the **real working tree**, so two concurrent `make test` runs in one checkout fail each other spuriously. Same class as AGE-21 and AGE-18 — a gate that does not mean what it reports. Its cheapest fix (a repo-level lock on the `test` target, or having the pre-push hook reuse an in-flight run) *also* kills the duplicated ~4h-per-push gate this loop pays on every story. |

### Stories filed by the AGE-32 session

| Story | Pri | What |
|---|---|---|
| **AGE-36** | med | **⚠ The pre-push gate this file tells you to rely on cannot pass here.** `~/.claude/hooks/pre-push-tests.sh` is registered in `~/.claude/settings.json` with `"timeout": 900` (15 min), but `make test` in this repo takes **~2h** — so it cannot complete inside its own budget on any push from agentics. Confirmed: the matcher *does* match this loop's HTTPS-override push form, and `make -n test` exits 0 so detection succeeds (it is **not** the AGE-18 "no test command detected" fall-through), and `git-readonly-allow.py` exits 0 with no output so it does not short-circuit. Observed but not instrumented: the AGE-32 push returned in well under 600s with **no** `pre-push-tests: running …` line, which the hook prints unconditionally before running the suite. **Practical consequence for you: do not assume the hook re-runs the suite. Run `make -k test` yourself and read the result — this loop's green results have all come from sessions doing exactly that.** Same economics as AGE-34; fix them together. |

### Stories filed by the AGE-31 session

| Story | Pri | What |
|---|---|---|
| **AGE-38** | low | **Pre-existing, not caused by AGE-31.** `MID_RE` (`:382`) treats `\|` as a shell separator, so *inside a fence* — where the unit is the whole LINE — a markdown table row is read as an invocation: `\| story HP-1 \| the id column \|` reports `verb_violations:["HP-1"]` on **today's shipped script**. Zero occurrences in the corpus, so the gate is green. `\|` is load-bearing for real pipelines (`jq … \| story …`), so it cannot simply be dropped from the class. |
| **AGE-39** | med | **Logged deliberate debt** (CLAUDE.md's rule: name the flaw, the patch's limits, the redesign trigger). `marker_suppresses` no longer refuses a placeholder token, but `classify_stale_markers` still skips one — so a placeholder marker **can suppress but can never go stale**, and one whose justification expired does nothing silently. Not fixed because narrowing the exemption reds the gate on a correct document, **even with AGE-37's origin fix applied** (measured). Held meanwhile by the corpus-level marker-accounting assertion in the bats suite. Redesign trigger: once `collect_markers` can tell a QUOTED marker from an APPLIED one. |

**AGE-37 also gained a comment** carrying a verified one-line origin fix (move the `SCANNED_LINES`
append after the invocation match, so a line counts as scanned only once an invocation was found —
turns a false `form_is_valid` into a true `not_scanned`, existing tests stay green) plus the ruling
on why it was held out of AGE-31's PR.

### Stories filed by the AGE-29 session

| Story | Pri | What |
|---|---|---|
| **AGE-40** | low | Blockquoted fences are unreachable — **both** the fence and its body. Measured during the council: a `>`-aware detector delivers **ZERO** reach, because `START_RE` (`^[[:space:]]*\$?[[:space:]]*story`) and `MID_RE`'s separator class ``[(;&|`]`` reject the `>` prefix independently of fence tracking. So recognising the fence would add a desync surface for no gain. The real fix is prefix-stripping in the extractor — a different change with a different risk profile, which is why it was deliberately **not** folded into AGE-29. Zero occurrences in the corpus; matters for AGE-30. |
| ~~**AGE-41**~~ | low | **DONE — closed by AGE-29, no separate PR.** A nested 4-backtick block containing an ODD number of 3-backtick lines desynchronised the toggle and false-positived on true prose, identically under the shipped detector and both regex candidates. The run-length rule makes it unrepresentable. Its repro ships as the "a shorter marker cannot close a longer fence" regression test. |
| **AGE-42** | low | **Agent-run `grep` is ugrep 7.5.0, not the `grep` your tests run.** Its `[[:punct:]]` does not match `` ` ``, `>` or `+`; bats/hooks get `/usr/bin/grep`. A hand-run marker count therefore under-counts **in the green direction**, turning a completeness oracle into the vacuous green it exists to prevent. Found when a council seat tested its own proposed test. Shipped code is unaffected (all six POSIX-class users run under bash). Fix is documentation plus optionally a guard. |
| **AGE-43** | **med** | **A false positive REACHABLE ON THE SHIPPED SCRIPT TODAY.** `MID_RE` harvests the remainder with `(.*)$`, which runs past an inline span's closing backtick, so inside a fence `` Then run `story project new` to start. `` reports subcommand `` new` `` — reddening the gate on the *correct* modern spelling. Verified on the unmodified script with a plain column-0 fence; zero corpus occurrences today. One-token fix (`([^`]*)`), but ⚠ **do not sell it as a safety precondition for a detector change** — it was measured NOT to fix the prose-verb false-positive class, because it bounds the *argument* capture, not the *verb* capture. Ships with an invariant test: no reported token may end in a backtick. |

### Stories filed by the AGE-30 session

| Story | Pri | What |
|---|---|---|
| **AGE-44** | low | **Logged tech debt, not a live failure.** `AGENTS.md` is now in the grammar guard's scan set and is GENERATED by `story scaffold agents-md` — only the header above `<!-- BEGIN GENERATED -->` survives regeneration. The `expect-dead` marker is line-bound, so it must sit inside the generated region: **the file most exposed to a future false positive is the one where the escape hatch cannot durably live.** Two triggers: a storyhook release whose generator emits a form its own `--help` rejects (no local remedy), or a regeneration landing an unbalanced fence (already caught early by the fence-latch canary). Workaround is the **pin, not the marker** — removing `AGENTS.md` from `ROOT_GRAMMAR_FILES` reds `test_root_grammar_allowlist_is_pinned` unless the same commit updates the pin and links an upstream story, making the coverage loss attributable rather than silent. Costs 93% of measured reach while in force. |

### Stories filed by the AGE-12 session

| Story | Pri | What |
|---|---|---|
| **AGE-45** | low | `storywork dispatch --dry-run` returns `ok:true` for plans that cannot succeed. Dry-run returns at `bin/story.sh:350` — **before** base-commit resolution (`:378-393`), the worktree/branch collision pre-check (`:396`), every tmux call, and the claim itself. So "the plan looks validated" is false in at least four conditions, and AGE-12's was only one of them. **Deliberately split out, not patched in AGE-12**: the council ruled a state-specific patch would *"fake a validation guarantee dry-run does not make"*. The decision is a product one — narrow the contract (document dry-run as *"what I would run"*) or widen it (hoist the read-only checks ahead of the dry-run return). Do not do it one condition at a time. |
| **AGE-46** | low | **⚠ NEEDS MIKEY'S DECISION — do not just fix it.** Tag `v3.3.0` is reachable from `main` but **no GitHub Release was ever published for it**; every other v3.x tag has one, so the Releases page shows v3.2.0 jumping to v3.4.0. Cosmetic only — tag, CHANGELOG and manifests are all correct and installs are keyed off the manifest, so nothing is stranded. Filed rather than fixed because the obvious backfill (`gh release create v3.3.0`) is **not** Mikey's recorded preference for this scenario (his was: publish only the current tip with rolled-up notes, prune the skipped tags) and pruning a public tag is destructive. Found by the AGE-12 session while doing the protocol's own release step. Closing the CLASS would mean a gate asserting every `v*` tag reachable from `main` has a Release — same shape as AGE-33's un-built preventative half. |
| **SH-180** | med | **Upstream, filed against `mikeydotio/storyhook`, not agentics.** `story move`'s undefined-state error is bare (``state `in-progress` is not defined``) while storyhook's OWN state-invariant error for the same condition already ends *"Run `story doctor --fix` to add it"*. Every downstream caller inherits the poorer message, so one fix upstream fixes all of them — which is why AGE-12's shipped code is explicitly a **workaround** that can be retired once SH-180 lands. Also records that neither repair fully restores the default shape: `doctor --fix` gets board order right but drops the `active` role; `state add ... --role active` sets the role but appends after `done`. |

### Stories filed by the AGE-19 session

| Story | Pri | What |
|---|---|---|
| **AGE-50** | low | **A gate that reports PASS having verified nothing — AGE-18's class, one layer down.** `plugins/storywork/tests/test-real-story-cas.sh:22` exits **0** with `SKIP: real story CLI not on PATH`, and its runner maps exit 0 to **PASS** — so the one file whose entire purpose is proving `story.sh` works against the REAL storyhook binary silently proves nothing when the binary is missing. Its four real-CLI properties (JSON-shape parity, redundant-move suppression, the concurrent-claim race, the state-vocabulary premise) all go unasserted. **Largely shadowed by AGE-19**: the version pin now hard-fails the gate before any suite runs when `story` is absent, so it is unreachable via `make test`; it stays live on the direct-runner path (`bash plugins/storywork/tests/run-tests.sh`), which is how you iterate on that suite. **Needs a decision, not just a patch** — either make the skip a hard failure (consistent with AGE-18) or give the plain-bash runners a real SKIP state distinct from PASS, which would apply repo-wide. ⚠ Do **not** "unify" this with `forge-crash-recover.sh`'s `story_cli_missing` or `forge-contract-check.sh`'s `ok:false`: those are SHIPPED RUNTIME scripts on end users' machines where storyhook is genuinely optional — a different audience with a different correct answer. Both the devops and architect council seats flagged it independently and both said explicitly it must not ride along with AGE-19. |

### Stories filed by the AGE-22 session

| Story | Pri | What |
|---|---|---|
| **AGE-51** | low | **A safety property that holds today for a reason nothing pins.** Five shipped sites capture the `story` CLI through `$( … )` with no bound, and storyhook auto-spawns a daemon that outlives the client (`tests/store-isolation.sh:41`) — the exact precondition for AGE-16's hazard. **Measured NOT exposed on storyhook 2.0.0**: the capture returns in 0.03s and every `story … daemon --serve` holds fd 0 on `/dev/null` with **no fd 1 or fd 2**. But that is an upstream implementation detail, not a contract, and SH-94 records the daemon holding a pipe at **fd 7** — so the class is one storyhook release away from live, with no local signal. Fix direction is an assertion that a spawned daemon holds no fd 1/2 (turning a future silent hang into a named red) **or** an upstream request to make "the daemon closes stdio" contractual — **not** redirecting the five working sites to temp files. Deliberately kept out of AGE-22's guard on all three council seats' advice. |

### Stories filed by the AGE-26 session

| Story | Pri | What |
|---|---|---|
| **AGE-52** | med | **A shipped fix that reached zero installs — the #71 class, one layer down.** `greenlight.sh:34-38` seeds the user config from the bundled default **only when the file does not exist**, so any later correction to `default-config.yaml` never arrives. Live proof: `~/.config/greenlight/config.yaml` dated **Apr 8** still carries `ai_enabled: true`, `ai_model: claude-sonnet-4-6`, `ai_show_rationale: true` — precisely the values the F077/F078/F082 comment in the hook says were changed because sonnet-4-6 is not on the structured-outputs list and *"every call likely 400'd and fell through to defer anyway: pure overhead, zero benefit."* Inert today **only because `ANTHROPIC_API_KEY` is unset** — an accident, not a guard. Note `read_config` already layers correctly for a MISSING key; the defect is that a STALE key beats a corrected default. Fix needs a decision (drop the seed and let `read_config` layer / version-stamp and reconcile / warn on drift). |
| **AGE-53** | low | **AGE-26's shape, different command.** `open`, `xdg-open` and `xdg-mime` sit in `is_always_safe` under `# misc harmless utilities`, beneath a header promising *"no flags or arguments can make them destructive"*. `open -a <App>` launches an arbitrary application; `open <url>` hands a URL to the browser (outbound, and a plausible exfiltration channel); `xdg-mime` edits the handler database that decides what a later `xdg-open` launches. Smaller blast radius than AGE-26 — `open` destroys nothing — but in the plan explorer it is `allow`-ed as *"readonly/safe"*. `mktemp` (creates a file) and `pbcopy`/`xclip`/`xsel` (write the system clipboard) share that line and that header. Flagged by the council's security seat under the sibling-sweep rule. |
| **AGE-54** | med | **The origin AGE-26 deliberately did not fix, filed as the council's explicit condition.** `plan_explorer_uncertain: allow` flips **every** uncertain command to auto-approved in a headless explorer — including `npx\|bunx\|pipx\|uvx`, which the hook's own comment one line above calls *"execute arbitrary code, always uncertain"*. So that config grants arbitrary code execution, which can reach the storyhook store by another route. Compounding it, `default-config.yaml:60-63` sells the option as *"trust the isolation of the worktree"* — a worktree isolates the filesystem, not a process `npx` starts nor a store outside every repository. The architect seat used this to argue AGE-26 must not harden verbs against the knob (symptom-masking at the encounter point); the security seat agreed **on condition the origin got a ticket** — *"B's own fix-at-the-origin argument is only honest if the origin actually gets a ticket."* Latent: the default is `deny`. |

### Stories filed by the AGE-24 session

| Story | Pri | What |
|---|---|---|
| **AGE-37** | low | `forge-contract-check.sh`'s `classify_stale_markers` reports kind `form_is_valid` for a marker on a line the extractor read but which yielded **no invocation at all** — claiming "storyhook made the form real, so the doc's denial is now FALSE", which sends a fixer to rewrite a **correct** sentence. Cause: `SCANNED_LINES` is appended *before* the marker strip and the `START_RE`/`MID_RE` match, so it conflates "handed to the checker" with "an invocation was found". The verdict is right (it still fails the gate); only the `kind` — the field whose whole job is picking which of four corrections to make — lies. Pre-dates this change (AGE-32, v3.1.0); AGE-24 enlarged its reachable surface from fenced lines to unfenced ones. |

### Stories filed by the AGE-70 session

| Story | Pri | What |
|---|---|---|
| **AGE-79** | med | **The half AGE-70 deliberately deferred, 3-0.** AGE-43's remainder bound truncates at the next backtick for EVERY qualifying opener, but only a backtick opener introduces a span — so for `(`, `;`, `&`, `\|` the cut lands before slot 1 and a dead relation goes silent. ⚠ **Do not treat this as a small follow-up.** The story carries **five pre-registered counter-examples any candidate must clear before it ships**, three of which killed a candidate that had already passed the real corpus, the full 83-test suite and 21 hand-built rows. It also carries a measured ladder so nobody re-derives it: a **rejected** span-level derivation (fails all five), a **partial** matching-closer cut (`vY`, clears 3 of 5), and a **leading** opener-keyed form (`vOK` — correct on all five, recovers both false negatives, corpus-identical, measurably free) that is **UNFALSIFIED and was deliberately not promoted**. Zero corpus occurrences; exactly ONE `MID_RE` match exists corpus-wide out of 161. |
| **AGE-80** | med | **A gap AGE-70 itself introduced, found on the FIRST document written after the fix.** The span-aware splitter can report a token containing **whitespace** for the first time (`ne"w x`); the `expect-dead` marker's token capture is `([^[:space:]]+)`, so **no marker can ever name one**. Before AGE-70 `read -ra` made that unrepresentable and the two grammars agreed by accident. The only marker that would work is one no author can type — AGE-43's inversion class, one layer on. Zero corpus occurrences today only because AGE-70's own CLAUDE.md sentence was **reworded rather than marked**, which is a workaround, not a fix. Needs a decision on the marker grammar (quote the token / take the rest of the field / refuse whitespace tokens), and both directions must stay pinned. |
| **AGE-77** | med | Filed by AGE-70's **first, panicked sitting**. The council protocol tells every member it is read-only in four places and **verifies it in none**; a seat silently rewrote a tracked corpus file mid-measurement and voided two measurements. The symptom was a corpus result flipping green→red with a violation the chair could not explain, while `git diff <sha> HEAD` showed **no change** — because the change was in the working tree, not a commit. **Verify `git status --porcelain` is empty immediately before every corpus measurement.** |

### Stories filed by the AGE-61 session

| Story | Pri | What |
|---|---|---|
| **AGE-66** | med | **⚠ NEEDS MIKEY'S DECISION — do not touch it, and do not remove that worktree.** `.claude/worktrees/dual-host-plugin-compatibility` holds **69 modified tracked files and 135 total entries** of uncommitted "dual-host" work teaching every plugin to run under both Claude Code and Codex — per-plugin `.codex-plugin/`, `claude/` and `codex/` dirs, `tests/smoke-codex-tmux.sh`, and two design docs under `docs/plans/`. **It exists nowhere else**: the branch tip is fully merged (so all the value is uncommitted), `git ls-remote --heads origin 'codex/*'` returns nothing, and the newest mtime is 2026-07-20. Preferred resolution is the safe reversible one — commit it onto its branch and publish, *then* remove the worktree — but that is a judgement about whether the idea is live, which is Mikey's. |
| ~~**AGE-67**~~ | low | **DONE — closed by AGE-61, same PR, no separate story cycle.** `.claude/scheduled_tasks.lock` was the only tracked file under `.claude/`, holding a dead 2026-05-25 sessionId/pid. Because it was tracked, git materialized it into every worktree, a scheduler sweep deleted it there, and both reclaim tools then read that worktree as permanently `dirty` and refused it forever. Filed at `low` as cosmetic noise; a council seat's natural experiment (`age-117`/`age-118` stuck dirty vs `age-AGE-2` clean-and-removable) reclassified it as the **structural cause of 2 of the 4** stale worktrees. Untracked with `--cached`, so the live file is untouched on disk; blast radius measured nil (zero references repo-wide). |
| **AGE-68** | low | 29 of 31 local branches have **zero** commits not in `origin/main` — residue accumulating at roughly one per completed story. Harmless, just noise. ⚠ **Two exceptions the sweep must exclude**: the running session's own branch, and `fix/AGE-3-semver-post-bump-hooks-skipped` (ahead=1) — AGE-3 is `done` and CLAUDE.md records its fix as landed, so that commit is *probably* an equivalent that reached `main` by another route, but **confirm before deleting, because if it is not equivalent it is the only copy**. Use the `merge-base --is-ancestor` test against a freshened `origin/main` (what `branch_is_merged` already does), not `git branch --merged`, which judges against the current HEAD. |
