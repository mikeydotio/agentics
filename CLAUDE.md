# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Agentics is a Claude Code plugin marketplace (`mikeydotio/agentics`) providing plugins for idea-to-execution workflows, root cause analysis, and semantic versioning.

## Architecture

**Marketplace manifest**: `.claude-plugin/marketplace.json` registers all plugins with name, description, and source path.

**Plugin pattern**: Each plugin under `plugins/` has:
- `.claude-plugin/plugin.json` — manifest (name, description)
- `skills/<name>/SKILL.md` — main skill with YAML frontmatter (`name`, `description`, optional `argument-hint`) + markdown instructions that act as the orchestrator
- `agents/<name>.md` — specialized subagent prompts with role descriptions, tool restrictions, and mandatory initial-read protocol (most agents now live in the shared `plugins/agents/agents/` library; consuming plugins use `agent-overrides/` for pipeline-specific context)
- `references/<topic>.md` — methodology docs and detailed protocols that skills reference (keeps SKILL.md lean)

**Key design patterns**:
- **Artifact-based resumption**: Plugins use namespaced artifact directories — forge writes to `.forge/`, rca to `.rca/<slug>/` (gitignored). Presence of specific files determines resume point.
- **Multi-agent orchestration**: One orchestrator skill spawns specialized agents at appropriate steps. Each agent has distinct tool access and perspective.
- **One question at a time**: All user interactions use `AskUserQuestion` with exactly one question per call.
- **Step exit protocol**: Every orchestrated step writes artifacts, handoff, commits, and queues freshen for context clearing before the next step.

## Plugins

| Plugin | Skill | Purpose |
|--------|-------|---------|
| agents | `/agents` | Shared agent library — 28 research-backed specialist agent definitions (17 general-purpose, 3 platform-specific UX, 8 pipeline-specific) used by forge, rca, and future plugins. |
| forge | `/forge` | Unified idea-to-deployment pipeline: interrogation → research → design → planning → decompose → execute → review → validate → triage → document → deploy. Uses shared agents from the `agents` plugin. FIX/ESCALATE triage loop. Has SessionStart and Stop hooks. |
| rca | `/rca` | Reproduction-gated RCA for known defects: KT IS/IS-NOT intake → firm repro gate (automated failing test; user/council override only) → git forensics (bisect/blame/pickaxe/hotspots via bin/ scripts) → competing-hypothesis falsification in disposable worktrees → ODC classification + surgical-vs-redesign verdict → caller gate (fix now vs hand off) → two-hats gated fix → committed blameless postmortem (docs/rca/). Orchestrator + 7 step subskills (forge-style direct-Read dispatch); latches GitHub/storyhook issues; uses shared agents (qa-engineer, investigator, evidence-collector, experimenter, hypothesis-challenger, software-architect, software-engineer, technical-writer). |
| reconcile-pr | `/reconcile-pr` | Rebase a GitHub PR onto its base branch as a hybrid state machine (`bin/reconcile-pr.sh`): preflight → start → resolve/continue loop → test → push → comment → cleanup. Deterministic script owns every git/gh mechanic + the force-push safety gate (destination-ref guard, explicit-OID `--force-with-lease`, never bare `--force`, never a protected branch); the SKILL only drives conflict resolution (base_side/pr_side zdiff3 labeling), behavior verification, and the summary. Isolated worktree under `.claude/worktrees/`. Refuses fork PRs in v1. |
| semver | `/semver` | Version lifecycle: tracking, bumping, changelog generation, sync validation. Has SessionStart and PostToolUse hooks. |

## Runtime Dependencies

**tmux** is a hard requirement for the freshen plugin and all hook-based context-clearing flows (forge step transitions). Without tmux, these flows fall back to manual `/clear` instructions.

**storyhook** is a hard test-time requirement, and this repository's suites are written against **storyhook major 2** (>=2.0.0, <3.0.0). The pin is enforced by `tests/storyhook-version-pin.sh` (`make test-storyhook-version-pin`), which fails the gate naming the observed and expected versions — an incompatible or unverifiable CLI is never skipped into a green. Measured on the real v1.0.0 binary: 87 failing assertions across three suites, none naming a version. Raising the pin means porting the suites, then changing `STORYHOOK_MAJOR` in that file *and* this sentence together.

**Bounded commands must never be captured through `$(…)`** — `timeout` signals only the process
group it created, so a descendant that `setsid()`s out of that group survives, keeps the
substitution's pipe open, and holds the caller for its whole lifetime while the bound *looks*
intact (measured **30.08s against a 5s bound**; redirect-to-file is 0.03s; `--kill-after` does not
help). Redirect to a temp file and read it back with `$(<file)` — see
`plugins/forge/hooks/session-stop.sh:194-200`. Enforced by `tests/bounded-capture-guard.sh`
(`make test-bounded-capture-guard`) in four positively-pinned layers, so **writing a new
`timeout`/`gtimeout` call site, or a new call of a bounding wrapper, reds the gate by design** —
that is the layer asking you to decide whether the new output can ever reach a caller's pipe, not
a nuisance to silence. If it can, add the wrapper's name to `REGISTRY` in that file. Deliberately
*not* covered: hand-rolled bounds (background pid + `kill -TERM`, used twice in rca), `perl -e
alarm`, and bounds reached through a variable.

**greenlight classifies the storyhook CLI by verb, and the rule for adding one is mechanical.**
The bare command name is **not** in `is_always_safe` and must never be re-added — that table
promises *"no flags or arguments can make them destructive"*, which is false for a CLI whose purge
and project-delete verbs are documented "There is no undo", whose update verb "atomically replaces
the running executable", and whose plugin verb installs third-party code. `is_safe_story()` returns
three ways: **allow** iff the worst case is a wrong story record in the current project, repairable
by another verb of the same CLI; **destructive (2)** only if `is_known_destructive` *already* ranks
an equivalent operation at 2 by command name, with that peer named in a comment at the arm (purge
and project-delete mirror `rm|rmdir|unlink|shred`; update and plugin-install mirror
`apt|brew|yum|dnf|pacman`); **uncertain (1)** for everything else, including every unrecognised
verb. The peer requirement is load-bearing — it makes bucket 2 self-limiting, since it cannot grow
without someone first editing `is_known_destructive`, a far louder act than editing an allowlist,
and it is why no rename of `any_destructive` was needed. Enforced by
`plugins/greenlight/tests/greenlight-story.bats`, whose allowlist pin asserts **set equality**, so
it reds on a narrowing exactly as it reds on a widening — **a removed verb may be a MAJOR bump**,
because shipped docs instruct agents to type some of them.

⚠ Three traps there. **The verb surface cannot be enumerated from the CLI** — its own `help --all`
yields 45 headings of which 4 are not commands, its usage block yields 48, and two more verbs
execute while appearing in *neither*; that is why unknown verbs fail closed and why no completeness
guard exists (a sentinel test pins the fail-closed default instead). **The extractor must follow
`is_safe_git`, never `is_safe_gh`** — storyhook accepts global flags *before* the verb and two of
them take a value (`--store-path`, `--project`), so `is_safe_gh`'s `$(i+1)` form reads `--json` as
the verb and a flag-skipper that ignores values reads the path as the verb. **Do not add flag
predicates** — the doctor verb is denied whole rather than split on `--fix`, because every flag
predicate is a permanent bypass surface.

⚠ **Do not write a guard that greps shipped docs for "verbs an agent is told to type."** It was
proposed, voted for, and withdrawn by all three council seats on measurement: the only occurrences
of the purge and project-delete forms in shipped `plugins/**` were inside greenlight's *own comment
describing the defect*, so the guard would have read the sentence documenting the bug as a mandate
to keep the verb auto-approved — while reporting green. The transferable rule:
`bounded-capture-guard.sh` is sound because a `timeout` call is **shell syntax in a shell file**, a
decidable predicate over a formal grammar; the same verb inside a markdown skill is **prose**. Same
shape, different kind. Full trail: `.council/age26-greenlight-story-verb-surface/DECISION.md`.

**A test fixture named by a fixed path under `/tmp` is machine-global state, and this repo owns
several.** `/tmp/forge-integrity` holds the live integrity baselines of *every* project on the box,
keyed by a digest of each project's absolute path. `forge-integrity.bats` used to `rm -rf` that whole
root in `teardown()` — justified in its own comment as merely keeping `/tmp` tidy, since per-test
paths are already unique. The paths were unique; the **root** was not, so the blanket removal deleted
every concurrent run's baselines and those of any real forge session in another repository (AGE-34).
Measured with that removal as the *only* concurrent actor — no second suite, no working-tree churn —
**14 of 19 tests failed**; after scoping it, the configuration that had produced 37 spurious failures
produced **0**. The rule: a test may delete its own subtree of a shared root and nothing above it,
and `rmdir` (non-recursive, fails harmlessly when non-empty) is the way to reclaim the root — that
choice is load-bearing, not cosmetic, and mutation M4 pins it. Enforced behaviourally by
`tests/forge-integrity-isolation.sh` (`make test-forge-integrity-isolation`), which is
**bidirectional on purpose**: deleting the teardown line altogether satisfies "the foreign sentinel
survived" while trading a clobber for an unbounded leak, so a second arm pins that the suite still
removes its *own* subtree.

⚠ Two traps there. **No source-level guard can enforce this class here** — it was considered and
declined unanimously. An `rm`-shaped predicate fires on `greenlight.bats:295`, which hands
`'echo $(rm -rf /tmp/foo)'` to a jq encoder as **data** that never executes, while
`forge-integrity.bats:30` is a quoted string that **is** executed: same shell syntax, opposite kind,
which is AGE-26's rule and not AGE-22's. And it would miss the class's other live members anyway —
they are a fixed *port* (AGE-56) and a fixed path bound to a **variable** (AGE-57), neither of which
appears at an `rm` call site. **Second: sweep with `git ls-files` and never an extension glob.** The
sweep that found AGE-56 missed AGE-57 twice, first because `plugins/*/tests/fakes/*` are tracked but
**extensionless**, then because the literal sits in a variable — the same blind spot
`bounded-capture-guard.sh`'s header already documents. **Concurrent `make test` in one checkout is
still not safe** (AGE-56, AGE-57 remain open); AGE-34 fixed one cause of that symptom, not the
symptom. Full trail: `.council/age34-forge-integrity-shared-snapshot-root/DECISION.md`.

**A test that fails must say why, and a `$(…)` capture under `set -e` is where that gets lost.**
`deployit-cli` and `deployit-release` each define a top-level `fail()` that prints its JSON
diagnosis to **stdout** and exits 1. A test capturing one under `set -e` dies *at the capture*, with
the diagnosis sealed in the variable and never printed — **0 bytes on stdout and stderr**, and the
runner showing a bare `FAIL (exit 1)` above an empty block. Measured: that is why AGE-35's
2026-08-04 gate failure was never diagnosable, and it is **not** what the story blamed (the pre-push
hook's `tail -40`) — a full log is equally empty. Both losses are real and **undiscriminated**;
`run-tests.sh` now re-echoes each failure's first 12 lines into its summary so the surviving loss is
bounded. Fix at the capture, never at the CLI: stdout is a **protocol channel**
(`deployit-backend:486` "CLI emits exactly one JSON object"; `ok:false` → HTTP 409), and adding a
stderr line breaks `test-gc.sh:70` and `test-cli-redeploy.sh:104`, which `json.loads` a
`2>&1`-merged capture.

⚠ **The fix set cannot be found by reading source — measured, 9 files vs 12.** The defect takes four
invocation shapes and only the first is visible to a regex: plain `out=$(python3 …/deployit-cli …)`;
**array-bound** (`test-cli-rm.sh:87` `CLI=(…)` then `$("${CLI[@]}" …)`); **function-bound**
(`test-cli-preflight.sh:50` `out=$(run_preflight)`); and **output-discarded**
(`test-release-tag-exists-omits-target.sh:28` `… >/dev/null` in a bare-called function). Every miss
is the variable-binding blind spot of AGE-34/AGE-57. So `tests/deployit-capture-diagnostics.sh`
(`make test-deployit-capture-diagnostics`, **~140-170s** depending on machine load) is
**behavioural**: it injects a `fail()`-shaped
failure at the k-th CLI call, k=1..6, and pins a per-file verdict string (`L` explained / `H`
expected-and-handled / `N` fewer than k calls / `S` failed silently). **`S` is never acceptable, and
`L`→`H` is a swallow-fix** — a real failure converted to a pass — which reds by design.

⚠ **Three traps there.** **Membership must be discovered, not assumed**: an earlier draft iterated
the pinned list and compared the result to that same list — self-consistent, so deleting a row
deleted it from both sides and passed. Mutation M2 walked straight through it. The k=1 sweep must
therefore run over **all** candidates, not the pinned ones. **Do not widen the run set to all 50
deployit tests**: narrowing is a *safety* property, since the excluded files spawn 14 additional
fixed-port backend servers (`test-backend-healthz.sh` pins 18729) against still-open AGE-56. And
**two files keep their first call site unmediated on purpose** — `test-release-adhoc-signing.sh` and
`test-release-existing-tag.sh` surface the cause through ordinary repo code (Python's `assert`
dumping its second operand) and are the guard's positive control; routing them through the fix's own
idiom would make them prove the idiom rather than prove unmediated code can explain itself. Coverage
limits are filed as **AGE-60**; the unexplained flake itself is **AGE-59**, with a pre-registered
discriminator naming in advance what the next occurrence must show. Full trail:
`.council/age35-deployit-bootstrap-flake-diagnostics/DECISION.md`.

⚠ **`for x in $VAR` DOES NOT SPLIT IN zsh, and it produced a false green here.** The Bash tool runs
zsh, where unquoted *parameter* expansion is not word-split (unlike `$(…)` command substitution,
which is). A verification loop written `for n in $COVERED` ran **once**, with `$n` bound to the whole
list and a nonsense path — reporting "18 files, 0 silent, 0s" when nothing had run. A council seat
hit the identical fault in the same session. Use `$(cat file)` or an array; and if a sweep reports an
implausibly fast clean result, suspect this before believing it.

### Gate cost — quote this distribution, never a scalar

**Every scalar this repo has written about `make test` has been misread, in both
directions, from the same file.** `tests/gate-integrity.sh` asserted "~15 minutes" at two
places — numerically equal to the pre-push hook's *entire* 900s budget — and two
consecutive stories read past it to **opposite** wrong conclusions: AGE-32 concluded the
hook was not firing, AGE-35 concluded the suite sat comfortably inside budget. Both were
wrong. So the record is a distribution with a date and a regime, and anything quoting a
single number is stale by construction.

Measured 2026-08-05 by mining 1 966 Claude Code session transcripts, which record every
hook run's `durationMs` (**107** agentics gate runs), plus one direct end-to-end probe:

| Regime | Runs | Median | Max | Cancelled at the 900s budget |
|---|---|---|---|---|
| Before 2026-08-04 | 45 | ~467s | 609s | **0** |
| 2026-08-04 → 08-05 (this backlog loop, high concurrency) | 62 | — | 900s (censored) | **12 (19.4%)** |
| Direct probe, 2026-08-05, post-AGE-35, load 2.49→13.33 | 1 | — | **630s** | — |
| Same suite, same day, with **two foreign suites running concurrently** (storyhook, scad-caliper) | 1 | — | **2 229s (37m09s)** | would have breached by 2.5x |

Three things that distribution is load-bearing for:

- **The tail is load-driven, not size-driven.** All twelve breaches fall inside one
  ~28-hour window; the 45 runs before it never exceeded 609s. The variable is concurrent
  test runs from *other repos on the same machine*, which is why a run can take 311s or
  ≥900s with near-identical suite content. **Measured directly**: AGE-36's own verification
  run took **2 229s** with two foreign suites running, against **630s** solo the same day on
  the same commit — a **3.5x** multiplier from load alone, and 2.5x over the whole budget.
  If you are timing this suite, record what else was running or the number means nothing.
- **Pre-AGE-35 figures understate the current suite by ~140–170s** —
  `test-deployit-capture-diagnostics` landed 2026-08-05T03:25Z, *after* every censored run
  was recorded. The median moved ~467s → ~630s.
- **A cancelled hook ALLOWS the push.** Measured 12/12: tag pushes `v3.0.0` and `v2.39.1`,
  a branch push and a PR creation all went out with no verdict. A PreToolUse hook that
  exits 0 has its stderr discarded and a cancelled one never returns the exit 2 that
  blocks — so the gate is invisible from inside a session either way, and **absence of the
  `pre-push-tests: running …` line is not evidence the hook did not run.**

`tests/gate-deadline.sh` makes the suite refuse before that cancellation point.
⚠ **Its second claim is disclosed, not guarded:** the budget is derived from the hook's own
declared `timeout` in `~/.claude/settings.json` (observed **900s**, 2026-08-05), a file this
repo does not own. Lowering that value below our margin makes the guard **inert**, and
nothing here can detect that it has — the same call `bounded-capture-guard.sh` makes in its
"Deliberately not covered" header. The budget **cannot be raised**: it is pinned from above
by a value this repo does not control, so the only remedy for a suite that outgrows it is a
faster suite.

⚠ **The duplication is instructed, not accidental.** The global `~/.claude/CLAUDE.md` tells
every session to run the full suite locally before every push, and the hook then runs it
again — so a push pays for the suite **twice**, and the second payment is concurrent load on
the very box whose load is the measured cause of the breaches. That is a global-file fix
(outside this repo) and is filed as **AGE-64**, which `tests/gate-deadline.sh` names as its
**removal trigger** — the deadline exists only while that load does.

Related, all needing changes outside this repo: **AGE-62** (a cancelled hook allows the
push), **AGE-63** (the matcher fires on a push invocation anywhere in the command text, so
heredoc bodies and prose cost a full suite run), **AGE-65** (SPEC for inverting the gate to
a test-result attestation).

### The release path must never require a local `main` ref — and a guard here would be the wrong shape

**A tracked runtime lock file made a worktree permanently unreclaimable by the verb that exists to
reclaim it.** `.claude/scheduled_tasks.lock` was the only tracked file under `.claude/`, swept into
the index by `8d9f6fe`. Git materializes a tracked file into every new worktree; a scheduler sweep
then deletes it *there*; and both reclaim tools classify a worktree with any dirt as `dirty` and act
only on `removable` (`issue.sh:940`, `story.sh:579-580,642`). So the worktree could never be
reclaimed, and the residue accumulated until one of them captured `refs/heads/main` and broke the
release path. Untracked in AGE-61/AGE-67. ⚠ **Scope it honestly: that explains two of the four stale
worktrees.** `age-AGE-2` was clean *and* `removable` and lingered anyway — "nobody ran the reclaim
verb" is an independent cause the untracking does not touch.

**A branch can be checked out in only one worktree**, so a linked worktree holding `main` makes
`git switch main` in the primary checkout fail outright. The durable fix is not to police worktrees
but to **stop needing a local `main` at all**: a tag ref is repo-global, the org is merge-commit-only
so a tag cut on a feature branch stays correct after merge, `semver-cli`'s `cmd_validate` reads no
branch, and `delete_branch_on_merge: true` means the remote branch is already gone. Measured
2026-08-05: `git grep -E 'switch main|checkout main|pull --ff-only'` matches **no repo code**.

⚠ **The remedy is `git switch --detach <worktree>`, never `git worktree remove`.** Verified in a
fixture, both topologies: detaching preserves modified *and* untracked files while freeing the
branch. Removal is what AGE-61's own story text suggested, and it would have destroyed the 135
uncommitted files in `.claude/worktrees/dual-host-plugin-compatibility` (AGE-66).

**A gate guard over `git worktree list` was designed, costed, voted for, and withdrawn by its own
author** — and the reason is the transferable one. This repo's guards exist to **convert SILENT
failures into loud ones** (AGE-18, AGE-21, AGE-27, AGE-33, the fail-open hook, the bounded call that
*looks* bounded). This failure is already loud and self-naming:

```
fatal: refusing to fetch into branch 'refs/heads/main' checked out at '<path>'
```

It prints the offending worktree path verbatim, and the detach remedy follows directly from it. A
guard would convert a fatal that names its own cause into an earlier fatal, priced at a hard block on
unrelated pushes plus a mutation battery to maintain — and it would fire on a hazard the decoupling
already made inert. Note the *cost* argument is **not** what settled this: the honest counterfactual
is red once, cleared by one safe command, not a run of blocked stories. **Pre-registered trigger that
would make the guard right after all** (this is deferred against a signal, not declined on taste): a
**second** observed capture of `refs/heads/main` by a linked worktree, or any future step
reintroducing a local-`main` dependency such as the `git fetch origin main:main` form — which is the
one command the residue still breaks, while step 10's `git fetch origin main` is immune. Full trail:
`.council/age61-stale-worktrees-durable-half/DECISION.md`.

### An all-green fixture asserts nothing — and in this guard the verb slot hides it

`forge-contract-check.sh` harvests an invocation's remainder and validates fixed token
positions in it. AGE-43 fixed one harvest overrun: inside a fence the extraction unit is the
whole LINE (AGE-24), so the remainder ran past the closing backtick of the span that had
qualified the match, and **correct documentation reported a mangled token**. The regex change
was one token wide. The transferable part is the **test**.

"No reported token contains a backtick" is **trivially true of an empty array**, and under the
fix every false-positive fixture goes green — so the invariant fixture must also carry dead
grammar as **positive controls**. Stronger, and measured: blanketing `is_placeholder` to return
0 empties `subcommand_violations` and `relation_violations` **while leaving `verb_violations`
intact**, because the verb slot routes through `verb_slot_is_wildcard` — a *different function*.
So a **combined length floor is satisfiable with a whole slot silently dead** (1 verb + 2
subcommand + 0 relation clears a floor of 3), and a **flat token set cannot see a token
migrating BETWEEN arrays** — which is exactly what AGE-70's fix will produce. **Pin per array.**

⚠ Three traps. **The defect INVERTED the negative-example marker rather than breaking it**:
pre-fix, a marker naming the correct token was reported as a stale `token_mismatch` with the
violation standing, while only a marker naming the backtick-mangled token suppressed — so the
sanctioned escape hatch worked only for a token no author would guess. Both directions are
pinned, because a one-directional arm misses a regression that flips the other half.
**Bounding `START_RE` the same way is measured wrong** — a backticked entity in the first
argument slot displaces the relation into the second, and the bound truncates before it, losing
a real detection on well-formed input to fix a false positive reachable only from malformed
input; the rejected scope is pinned executably by mutation M5, not merely documented. And **no
assertion here detects an OVER-fix** — widening the bound to a larger delimiter class leaves
every pinned array identical — so the suite pins the reported *token* on a span whose content
legitimately carries a semicolon and a paren. Full trail:
`.council/age43-midre-trailing-backtick-scope/DECISION.md`.

⚠ **A mutation battery without a baseline arm is not a battery.** AGE-43's first battery pointed
bats at `"$SRC.bats"` where `$SRC` already ended in `.sh`; every arm ran against a file that does
not exist and reported the resulting error as the mutation being caught — **five false
"CAUGHT"s**. The baseline arm is what disclosed it, by reading `0 ok` where it should have read
`7 ok`. Same family as AGE-35's vacuous sweep.

### A value-returning env hatch must name itself — and a green gate cannot prove this one fixed

`deployit-cli` has **ten** `DEPLOYIT_SKIP_*` escape hatches. Four bare-`return` and carry no value.
Of the **six that return a value to a caller**, four already self-name — `_install_launchd:235`
(`skipped:True`), `_sparkle_sign:1222` (the literal `TEST-ED-SIGNATURE-DO-NOT-SHIP==`),
`_publish_github_release:1845` (`skipped:True` plus a display line surfaced at `:2222`),
`_run_post_test:1956` (`status:"skipped"`, printed at `:2262`). Two did not.
`_commit_and_push_index` returned **`published: True`** from the path that contacts no remote, and
`cmd_gc`/`cmd_rm` gate an irreversible `rmtree` of `serve/<id>/` on that field (AGE-48). The other,
`_wait_for_health:2646`'s bare `True`, is filed as **AGE-71**.

**Measured harm, and it is not what the story claimed.** A published removal and a hatch removal
produced **byte-identical stdout**, with the serve dir irreversibly deleted in both — so no caller
could tell them apart, and `deployit-backend:_run_cli_rm` forwards that payload **verbatim over
HTTP** to the web UI's swipe-to-delete. The story's stated Extent — that push-asserting tests "go
vacuous" under a leaked variable — is **false**: `test-cli-rm.sh` fails with `rm not pushed to
origin` and `test-cli-rm-pr-fallback.sh` (which has no precondition guard at all) fails with
`expected index_pending`. AGE-21 had already closed that hole downstream.

The rule: **an escape hatch may skip work, but it may never borrow the success vocabulary of the
path it skipped.** `_commit_and_push_index` now returns `status` in
{`published`, `pending`, `local_only`}, and `_index_change_is_effective(result)` — **total over
`dict | None`** — authorises the deletion. Two traps in that totality: `None` is *reachable*
(`cmd_gc`'s `mutate` returns it on a no-op, which `test-gc.sh:67` drives), and an unrecognised
status must fail **closed**, so a fourth member added later authorises no deletion until it is
classified. Keeping files that could have gone is recoverable; the other direction is not.

⚠ **Do not spell the pending arm `not published`.** That is what made the local-only path claim a PR
that does not exist. Each arm keys off its own status.

⚠ **`skipped` was the wrong word here, and `durable` was too — both were argued for and measured
down.** `skipped` is the file's settled hatch word, but in all three precedents it means *no work
occurred*, whereas this hatch performs a local write; borrowing it would **understate** in a fix
about a value that **overstated**. And a proposal to name the predicate `_index_change_is_durable()`
was adopted by two of three council seats before its own author refuted it:
`_reset_index_to_origin_main` is a **`git reset --hard origin/main`** and the hatch never
`git commit`s, so the hatch's write is an *uncommitted* working-tree change that the next non-hatch
call (`:1707`, `:1764`) destroys — durable only while the variable stays set. `effective` is precise
at the only instant the predicate is ever evaluated. **Had the two concessions been taken at face
value, the fix would have shipped a misleading name inside a fix about a misleading name.**

**No gate-level guard, declined on soundness rather than cost.** The only decidable predicate — an
AST walk asserting every dict-returning `DEPLOYIT_SKIP_*` early return carries a marker — covers
**4 of the 6** and is structurally blind to `_sparkle_sign`'s bare string and `_wait_for_health`'s
bare `True`, so it would report green over exactly the members it cannot see. That is AGE-35's
vacuous sweep and AGE-26's green-over-the-sentence-documenting-the-bug in one. **Pre-registered
trigger** (the council's first wording was vacuously met the day it was written, and all three seats
accepted the correction): *a hatch whose unmarked success value escapes the process — payload,
stdout, or HTTP — or authorises an irreversible action*; or the first `DEPLOYIT_SKIP_*` added
outside `deployit-cli`.

⚠ **A GREEN `make test` IS NOT EVIDENCE THE WEB UI'S DELETE PATH IS FIXED, AND THIS IS STRUCTURAL.**
`deployit-backend:466-467` runs `<state>/_plugin_root/bin/deployit-cli`, never repo code, while
`test-backend-delete.sh:20` **symlinks** `_plugin_root` at the repo. So the suite always exercises
current code and **cannot detect a stale daemon** — in either direction. Any change under
`plugins/deployit/bin/**` is **inert for the web UI** until the daemon's `_plugin_root` actually
carries it; the signal is `verify-live.sh`'s "passed", never `_healthz`, and any redeploy must run
**post-merge from `main`**, since `redeploy` is hard-refused inside a linked worktree.

⚠ **`<state>/_plugin_root` is NOT necessarily a copy, and assuming it is understates the gap.**
AGE-48's council reasoned it was one; measured on this machine it is a **symlink into the
version-keyed plugin install cache**, pinned at deployit **2.36.0** while the repo shipped **3.7.2**
— so the live daemon still runs the exact defect AGE-48 fixed. Claude Code never re-extracts a
version it already has, so a repo-side fix reaches that cache only after a `/semver bump` **and** a
marketplace update on the box. Note `~/.deployit` does not exist there either: a session probing the
conventional state dir concludes deployit was never bootstrapped while a daemon is loaded and
serving from `~/Library/Application Support/deployit`. **Verify the topology before claiming a fix
is live** — `readlink` the `_plugin_root` and grep the resolved CLI for your change. Filed as
**AGE-72**, whose remedy needs Mikey: every option changes what a live tailnet service runs, and the
honest gap is 1.5 majors of accumulated deployit change rather than one patch.

⚠ **The regression test is five-armed because every cheaper version is walkable**, and the walk is
named: a fix that adds `index_local_only` to the payload while `_commit_and_push_index` still
returns `published:True` passes any membership assertion. So the suite pins the **return dict by
equality** (reds on a re-added `published` exactly as on a removed `status`), the predicate **per
case** rather than as one combined expression (AGE-43's per-array rule), a **structural** payload
differential (`set(hatch) - set(pushed) == {index_local_only}`, every other shared key equal — *not*
"the two stdouts differ", which any incidental nondeterminism satisfies), an **absence** arm on
`index_pending` (uncovered anywhere else: that key is asserted in exactly one place suite-wide, and
only as *present*), and a **display** arm, because the measured lie was on the channel a human
actually reads. Both halves must still delete the serve dir as a positive control — an all-green
fixture asserts nothing. Full trail:
`.council/age48-published-lies-under-skip-gc-push/DECISION.md`.

**Hook ordering**: Claude Code does **not** guarantee execution order between different plugins' hooks registered on the same event (e.g. forge's and freshen's `Stop` hooks both fire on every Stop event, in unspecified order). tmux buffering (keystrokes sent by a Stop hook aren't acted on until all of that turn's hooks finish) only governs *when* an already-sent command is processed — it does not make cross-plugin ordering safe for hooks that depend on *each other's side effects* (e.g. one hook writing a signal file another hook reads). Where that matters, the dependent hook must be self-sufficient rather than assuming a write from another plugin's hook already happened — see forge's `hooks/session-stop.sh` and `references/auto-resume.md`'s **Cross-Plugin Hook Ordering** section for a worked example (and its `.freshen/.clear-pending` idempotency guard for avoiding a double action when both hooks *do* end up doing the same thing in one batch).

## When Adding a New Plugin

1. Create `plugins/<name>/.claude-plugin/plugin.json` with `name` and `description` (the `version` field is auto-managed — see below)
2. Add the skill in `plugins/<name>/skills/<name>/SKILL.md`
3. Register in `.claude-plugin/marketplace.json`
4. Keep SKILL.md as a thin router dispatching to reference docs for detailed procedures

## Plugin Version Sync

The whole marketplace shares the single repo `VERSION`. The post-bump hook
`.semver/hooks/post-bump/01-sync-plugin-versions.sh` stamps the bare version into
the top-level `.claude-plugin/marketplace.json` and each
`plugins/*/.claude-plugin/plugin.json` `version` field on every `/semver bump`,
folding the change into the release commit and moving the (unpushed) tag onto it.
This is one-way (`VERSION` → manifests) and deliberately over-eager: unchanged
plugins are restamped too, so a bump can never miss one.

- **Do not hand-edit** the `version` field in any manifest — it is derived.
- To seed a brand-new plugin or repair drift between bumps, run the hook standalone:
  `bash .semver/hooks/post-bump/01-sync-plugin-versions.sh` (files only, no git ops).
- `tests/plugin-versions.sh` (in `make test`) fails if any manifest drifts from `VERSION`.
- This hook runs automatically after every `/semver bump` (or a direct
  `semver-cli bump execute` — e.g. the non-interactive path for bumping on a
  feature branch) regardless of whether `--plugin-root` is passed; the CLI
  locates its own hook runner (fixed since AGE-3, v2.38.0-era regression). A
  bump's JSON exits `3` (not `0`) if hooks were pending but genuinely could
  not run — check `post_hooks.warnings` before reaching for the manual
  repair step above.

### Cache is version-keyed — shipped content changes MUST bump

Claude Code caches each plugin by its **version string**: an install that already
extracted version `X` never re-extracts `X` again, even when the marketplace's
content for `X` later changes. So **any change to shipped `plugins/**` runtime
content must ship with a `/semver bump`** — never mutate an already-released
version's content in place, or installs keep running the old code while the
manifest reports the (unchanged) version. This was issue #71: a deployit fix
stranded under an unbumped `2.25.1`, so no install ever received it.

- `tests/plugin-content-drift.sh` (in `make test`) enforces this — it fails the
  pre-push gate if shipped content under `plugins/**` differs from the release tag
  `v<VERSION>` (git blob OIDs are content hashes; the check is a `git diff <tag>
  HEAD`). "Shipped" excludes plugin `tests/`, `*.bats`, and plugin `README.md`; a
  `/semver bump` retags at the new HEAD, which clears the guard.
- **Landing a release-bump PR** (keep the tag from being stranded): let
  `/semver bump` create the local tag, push the **branch only** (never the tag);
  after the PR merges, re-point the tag onto main's release commit and push it
  cleanly — `git tag -f v<X.Y.Z> <main-release-sha>` then
  `git push origin v<X.Y.Z>` (no force needed on a first push). Then
  `/semver validate` should be all-PASS.

## Hardening Roadmap

The forge × storyhook seam underwent a full hardening pass (2026-07 audit + 8-workstream plan,
106 findings — see `~/Enderchest/agentics-harness-audit/`). All landed, one PR per workstream:

- ✅ WS1 — storyhook seam rewrite (verb-first CLI, real JSON shapes, DAG cycle guard)
- ✅ WS2 — state-machine correctness (F009 JSON-path fix, review/validate deadlock, resume spine)
- ✅ WS8 (F103) — docs↔CLI contract guard, regression-proofs the seam
- ✅ Critical fix — decompose's auto-created parent story could permanently deadlock `execute`
  (found by live dry-run, not in the original 106 findings)
- ✅ WS3 — agent alignment (real `agents:*` types, tool restrictions actually bind)
- ✅ WS4 — loop bookkeeping scripted (lock, verdicts, integrity, crash-recovery, predecessor-diff)
- ✅ WS5 — step-exit consolidated (fixed a live cross-project relative-path bug in all 12 step skills)
- ✅ WS7 — hooks/greenlight/portability (breaker correctness, greenlight tests+hardening, BSD/macOS)
- ✅ WS6 — tmux determinism (capture-pane verification, transition audit log)
- ✅ agentics#33 — re-scoped from "build a supervisor" to instrumentation: `forge-state.sh` now
  emits `category`/`auto_advance`/`transition_id` (the router's own pass_through vs.
  fix_loop/blocked_review/escalate_review/deploy_gate/report_complete classification, named
  instead of left implicit in `dispatch`), `--record-transition` and `forge-step-exit.sh
  --transition-id` log correlated predicted/actual lines to `.freshen/transitions.log`, and
  `forge-transition-report.sh` correlates them by id (not position) into matched/orphaned-
  predicted/orphaned-actual buckets. Pure telemetry — nothing acts on `category`/`auto_advance`
  yet. A full supervisor (or the issue's original "Level 1.5" helper) remains explicitly **not
  built**: WS6 already delivers confirmed/audited sends, and a bash reimplementation of
  categories 2–6's judgment (fix_loop's mandatory archive call, the three human-gate states)
  would be a second source of truth for exactly the class of drift `forge-contract-check.sh`
  exists to catch. Revisit only on a concrete signal — `transitions.log` data showing category-1
  transitions are a non-trivial cost, a predicted/actual mismatch (a real misroute), or a
  persistent orphaned-predicted count — not on a schedule. Full design doc:
  [agentics#33 comment](https://github.com/mikeydotio/agentics/issues/33#issuecomment-4879731013).
  Pane-option state migration remains separately deferred (reasoning in
  `plugins/forge/references/auto-resume.md`).
- ✅ storyhook repo portability follow-up (F074) — `post-git.sh`'s python3 spawn fixed
  ([storyhook#11](https://github.com/mikeydotio/storyhook/pull/11)); `session-start.sh`'s
  sed-based cwd parse investigated and left intentionally unchanged (a tested design constraint
  bans python3 there) — [storyhook#10](https://github.com/mikeydotio/storyhook/issues/10) closed

<!-- semver:start -->
## Semantic Versioning

This project uses semantic versioning managed by the `/semver` plugin.

### Version Awareness
- Read the `VERSION` file at the start of each conversation to know the current version.
- Read `.semver/config.yaml` to understand the versioning configuration.
- When discussing releases, deployments, or changes, reference the current version.

### Commit Discipline
- Write meaningful, descriptive commit messages. Each commit message may appear in an auto-generated changelog.
- Use conventional-commit-style prefixes when they fit naturally: `feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`.
- The first line of the commit message should be a concise summary (under 72 characters). Add detail in the body if needed.

### Version Bump Guidance
When recommending or performing a version bump:
- **patch** (0.0.x): Bug fixes, documentation corrections, minor refactors with no behavior change.
- **minor** (0.x.0): New features, new capabilities, non-breaking additions to the public API or user-facing behavior.
- **major** (x.0.0): Breaking changes — removed features, changed interfaces, incompatible API modifications, behavior changes that require consumers to update.

When you notice the user has completed a logical unit of work, suggest running `/semver bump` with the appropriate level.

### Releasing via GitHub
Any time a PR merges to main, perform a `/semver bump` (you choose the most appropriate component to bump), PR-and-merge the VERSION change, and then publish a github release for the new version.

### Hooks
- Custom pre-bump and post-bump hooks can be added in `.semver/hooks/`.
- Never trigger `/semver bump` from within a hook — this causes infinite recursion.

### Configuration
Versioning settings are in `.semver/config.yaml`. Do not modify this file unless the user explicitly asks to change semver settings.
<!-- semver:end -->
