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
| **Next story** | **AGE-12** — storywork's in-progress claim diagnostic. Nothing is blocked any more (`blocked: 0`), so the dependency-graph rule no longer overrides `story next`; it and this table now agree. Confirm with `story list --ready`. |
| **Completed this loop** | AGE-14, AGE-15 (one PR), AGE-16, AGE-18, AGE-17, AGE-11, AGE-27, AGE-33, AGE-28, AGE-32, AGE-24, AGE-31, AGE-29 (+ AGE-41, closed for free), AGE-30 |
| **Repo version** | **v3.5.0** — minor, NOT the `patch` AGE-30 predicted. See the level note below. |
| **Last updated by** | AGE-30 session, 2026-08-04 |

> Update this table **twice** per story: once when you claim it (status → IN FLIGHT), once when
> it merges (move it to Completed, set the next story). It is the first thing the next session
> reads.

---

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
- **⚠ `git switch main` FAILS in this checkout** — `main` is held by the `age-118` worktree
  (`fatal: 'main' is already used by worktree at .claude/worktrees/age-118`). The protocol's
  step 10 tells you to `git switch main && git pull --ff-only`; you cannot. Branch from
  `origin/main` directly (`git fetch origin main && git switch -c <branch> origin/main`) and push
  the tag without ever checking main out. Verify the tag landed with
  `git merge-base --is-ancestor v<X.Y.Z> origin/main` instead. **GitHub auto-deletes the branch on
  merge**, so step 10's `push origin --delete` errors with *"remote ref does not exist"* — that is
  success, not a failure.
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
| 1 | **AGE-12** | med | storywork claim diagnostic. Independent. **Now genuinely first** — nothing is blocked any more, so `story next` and this table agree for the first time in six sessions. |
| 7 | **AGE-21** | med | deployit's `test-cli-rm.sh` needs a live local daemon — the last known source of pre-push gate noise now that AGE-16 is closed. |
| 8 | **AGE-19** | med | No storyhook major-version pin. |
| 9 | **AGE-22** | med | Preventative guard for AGE-16's defect class — see below. |
| — | **AGE-8** | low | **Do not work this story.** It is `obviated-by` AGE-7; PR #137 carries its remaining scope too. Close both AGE-7 and AGE-8 once #137 merges. |
| 12 | **AGE-9** | low | Council-decision story, independent. |
| 13 | **AGE-13** | low | Council-decision story, independent. |
| 14 | **AGE-23** | low | Skill `references/*.md` are cited skill-relative but ship at plugin root — see below. **Confirmed live again this session:** the council skill's own `references/council-protocol.md` failed to resolve skill-relative and cost a wasted tool call. |
| 15 | **AGE-25** | low | AGE-17's own safety mechanisms are unproven — see below. |
| 16 | **AGE-26** | med | **New, filed by the AGE-11 session.** greenlight auto-approves the whole `story` CLI on a premise storyhook 2.0 falsified. Its *comment* is already corrected (AGE-11, v2.40.1); what remains is the trust-boundary judgement — see below. |
| 17 | **AGE-20** | low | Deliberately deferred — land it alone, never beside a behaviour fix whose proof depends on those fixtures. |

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

### Stories filed by the AGE-24 session

| Story | Pri | What |
|---|---|---|
| **AGE-37** | low | `forge-contract-check.sh`'s `classify_stale_markers` reports kind `form_is_valid` for a marker on a line the extractor read but which yielded **no invocation at all** — claiming "storyhook made the form real, so the doc's denial is now FALSE", which sends a fixer to rewrite a **correct** sentence. Cause: `SCANNED_LINES` is appended *before* the marker strip and the `START_RE`/`MID_RE` match, so it conflates "handed to the checker" with "an invocation was found". The verdict is right (it still fails the gate); only the `kind` — the field whose whole job is picking which of four corrections to make — lies. Pre-dates this change (AGE-32, v3.1.0); AGE-24 enlarged its reachable surface from fenced lines to unfenced ones. |
