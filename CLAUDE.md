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

**storyhook** is a hard test-time requirement, and this repository's suites are written against **storyhook major 3** (>=3.0.0, <4.0.0). The pin is enforced by `tests/storyhook-version-pin.sh` (`make test-storyhook-version-pin`), which fails the gate naming the observed and expected versions — an incompatible or unverifiable CLI is never skipped into a green. Measured on the real v3.0.0 binary: all 526 Forge tests and all nine root grammar tests pass. Measured on the real v1.0.0 binary: 87 assertions fail across three suites, none naming a version. Raising the pin means porting the suites, then changing `STORYHOOK_MAJOR` in that file *and* this sentence together.

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

### Testing belongs to each repository (AGE-102 / SH-682)

Agentics no longer installs a global pre-push test hook. Each repository owns
its test commands and enforcement; this repository keeps its headless suite in
`make test`. The isolated-store wrapper still protects the developer's tracker.
The hook-only deadline and installer were retired with the hook.

For an existing installation, run `python3 hooks/retire-pre-push-hook.py` to
inspect it, then add `--apply` to back up and remove the Claude and Codex
registrations and active scripts. Unrelated settings and Git hooks are preserved.
See `docs/global-hook-retirement.md` for the migration contract. Historical
AGE-36/AGE-62 timing and cancellation evidence remains in Git history and PROGRESS.md.

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

### Derive the character class, never enumerate it — and make pins BRACKET a rule, not describe it

AGE-69 finished a line AGE-43 had started. Inside a fence the extraction unit is the whole LINE
(AGE-24), so the remainder harvest glued any adjacent delimiter onto the checked token and
**reported correct documentation as a violation** — `(story project new)` → `new)`. The shipped
guard already stripped exactly one trailing comma (`sub="${sub%,}"`): the class was known and
handled for `,` alone.

**What ships is a derived rule, not a list**: `strip_trailing_glue` trims until the token ends in
`[A-Za-z0-9]`. Both slots are validated by **exact match** against a vocabulary harvested from the
live `story` binary, and **no member ends in a non-alphanumeric** — measured over the real
derivation, **97 members** (48 verbs, 8 relations, 41 subcommand members), whole charset `[a-z-]`
with the hyphen never trailing. That makes the rule **sound**: no trailing trim can turn a
non-member *into* a member, so it cannot manufacture a false negative, and a search for a
constructible counter-example **failed and is recorded as failed**.

⚠ **An enumerated set was proposed twice by the council and lost three times over, and the reasons
generalise past this file.** (1) **CRLF defeats every enumeration** — a wholly correct CRLF file
reports `new)^M`, byte-identical to no fix, because CR is not a character anyone thinks to
enumerate; worse, it mangles the **positive controls** too (`init` → `init^M`), so every reported
token becomes unsatisfiable by any `expect-dead` marker and **the whole suppression mechanism dies
silently**. (2) **Bash will void an enumerated class without saying so** — a `]` moved out of first
position inside a *variable-expanded* class does not narrow it, it disables it entirely, exit 0,
gate green. (Literal `]`-first in `[[ ]]` is a *loud* syntax error; the variable form is the silent
one, and it is the form an enumerated set needs.) (3) There is **no corpus evidence to pick a set
from** — across all 150 tracked `.md` files there are zero trailing-glue occurrences.

**The transferable test lesson: pins must BRACKET a rule, not describe it.** Describing it passes
every mutant.

- **CEILING** — AGE-43's mid-token arm (`baz)qux`, `foo;bar`), now extended to the **relation**
  array, which it never covered. Reds on a strip not confined to the trailing edge.
- **FLOOR** — a CRLF arm. Reds on any narrowing back to an enumerated set.
- **BOUNDARY** — a digit-terminal arm. Reds on a one-character error in the class itself.

⚠ **The boundary arm is the whole point, and it must assert PRESENCE.** `[!A-Za-z]` — one character
different — is byte-identical to the correct rule on AGE-43's over-fix arm, on every per-array pin,
on the AGE-70 pin **and on the real 29-file corpus, which stays green**. Yet `new2` and `blocks2`
**vanish from the violation set**, because their stems are *live* vocabulary. That is a **false
negative**, the one direction a drift guard cannot afford, so the arm pins those rows as present
rather than pinning a token's spelling. **Mutation M9 is caught by that arm and by nothing else in
an 83-test suite.**

⚠ **Scope is the subcommand and relation slots only, and the boundary is executable.** The verb
slot has the same symptom through a different mechanism (its capture class `[A-Za-z0-9_.-]` absorbs
`. - _`). Extending the strip there **reds the real corpus** — `contract_ok:false`, violation
`<id`, and **the live `<id>` suppression destroyed** — because `verb_slot_is_wildcard` tests a
**balanced** `<...>` while `is_placeholder` is **leading-only**. It also migrates tokens *between*
violation arrays. That is **AGE-74**; the real-corpus arm is now hardened with `contract_ok == true`
plus the exact suppression set, because "no token carries a backtick" plus a file count were blind
to it. Full trail: `.council/age69-delimiter-glue-scope/DECISION.md`.

⚠ **Run a mutation battery against an isolated repo COPY, not the working tree.** A first attempt
here mutated the tracked file, hit the 10-minute tool timeout, and was killed mid-run; the trap
restored correctly, but that is luck you should not need. Also: **a prediction that one arm alone
catches a mutant is worth checking** — two such council predictions were measured down (26 tests
and 12 tests respectively), and only M9 was genuinely alone.

### A grammar earns its permission by POSITION, and a pin can certify the bug it names

AGE-70 finished the line AGE-43 and AGE-69 had been walking. `read -ra` splits the harvested
remainder on whitespace while the checked slots are **fixed indexes**, so a multi-word span
contributes its own words and displaces every later index — ``story relate `story next --id`
blocks AGE-2`` reported `next`, a word from *inside* the span, and `story relate "AGE 1" …`
reported `1`. Correct documentation reported as a violation, and worse: the quoted form carries a
real dead relation that the shipped guard **never names**. What ships is a closer-stack splitter
behind a one-in-one-out accessor, with `MID_RE` and its bound **untouched**.

**The scope ruling is the transferable part, and it is not "which characters".** The chair built
the obvious fix — one lexical scanner owning both the argument split *and* a span-level remainder
bound — and it passed the real corpus, the whole 83-test suite, 21 hand-built rows and a cost
probe. A council seat tasked with attacking it killed it in one round with **five
counter-examples**: three outright **regressions against shipped**, one leaving the AGE-70 false
positive *itself* unfixed on a nested `$( … )`, and one needing nothing more exotic than the
apostrophes in **`it's`** and **`AGE-1's`**. The rule that survived, 3-0, with two of three seats
voting against their own proposal:

> **The same span grammar is SAFE in the splitter and UNSAFE in the bound.**

Inside a fence the extraction unit is the whole LINE (AGE-24), so the input is **prose with shell
embedded in it**, and every grammar strong enough to parse the shell also misparses the English —
`don't` is not an open quote. What differs is the *consequence*: in the splitter a misparse
**merges two tokens**, the slot lands on a wildcard or a real token, and the guard still reports —
loud and local. In the bound it **truncates** before the slot, `is_placeholder("")` returns 0, and
the guard reports **GREEN**. So enumeration is permissible in the splitter (shell's own fixed
syntax, no live authority to derive from, same footing as the `expect-dead` marker syntax) and
impermissible in the bound — **the same list, in the other position, is a silent-false-negative
generator.** That is four derived rules refuted by construction here now (AGE-69's enumerated
class, AGE-43's bound, backtick parity, this one). Not carelessness: each was a sound statement
about *shell*, evaluated over text that is not shell. The deferred half is **AGE-79**, which
carries all five counter-examples as pre-registered acceptance criteria and a measured ladder of
three candidates — including one that is correct on every row anyone has tried and was
**deliberately not shipped because no adversary has attacked it**.

⚠ **A CHARACTERIZATION PIN THAT ASSERTS EQUALITY TO A WRONG VALUE IS A MUTANT'S ALIBI**, and this
indicts a convention these notes have been recommending. AGE-70's own pin asserted the relation
array equalled the token *the bug produces*. So reverting the fix scored **82 ok / 1 not ok,
byte-identical to a correct fix** — the pin did not merely fail to detect the regression, it
**certified** it. A characterization pin must be written so a *correct* fix reds it: pin
**absence/presence**, or the story ID, not a defect's output. Audit any pin whose asserted value
equals what the defect emits.

⚠ **"Structurally unverifiable" deserves one more measurement.** The council's mutation battery
ruled the subcommand call site unpinnable — index 0, `is_placeholder` is leading-only, so no
later-index displacement is reachable — and measured a revert at byte-identical 82/1. Right about
*displacement*, wrong about the reported **token**: a span opening **mid-word** is not leading, so
a `project` subcommand written `ne"w x"` reports `ne"w` shipped and `ne"w x` fixed. The arm now
kills that mutant. Note the two mechanisms **compose** — the split decides where the token ends,
then AGE-69's `strip_trailing_glue` trims it — so the pin must fix both shapes.

⚠ **That sentence is reworded rather than marked, and the reason is a defect this fix introduced.**
Written as a complete invocation it reds the gate, and **the sanctioned escape hatch cannot
suppress it**: the marker's token capture is `([^[:space:]]+)`, while the splitter can now report a
token containing a **space**. Before AGE-70 `read -ra` made that unrepresentable, so the two
grammars agreed by accident. The only marker that would work is one no author can type — AGE-43's
inversion class, one layer on. Filed as **AGE-80**; found on the **first document written after the
fix**, which is the whole evidence that it is reachable.

⚠ **A per-character scan in bash is quadratic and the fix is free.** `${s:i:1}` is O(i): measured
on a 21 KB unit, 3.10s → **21.30s**, and **34.60s** through a prefix walk. The proposed remedy was
a *length budget degrading to the old bound*; that was measured **unnecessary** — passing the
wanted index into the scan and stopping there restores it to at-or-below shipped. **A budget that
silently degrades to a different bound is a second code path with no arm pinning which one ran.**
Longest real corpus unit: **488 chars**, so the cost is latent, not live.

⚠ Two process notes. **If a council seat's job is to falsify, it must be able to execute** — the
first sitting seated `skeptic` (no Bash) as challenger; swapping in `hypothesis-challenger` is the
only reason the five counter-examples exist. And **a mutation battery must run against an isolated
repo COPY with a baseline arm first**: the 10-minute tool timeout killed this one mid-run (again),
and only the copy kept the working tree safe. Use `bats --filter` — a full-suite run per mutant
does not fit. Full trail: `.council/age70-slot-displacement-scope/DECISION.md`.

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

### A failed request is not evidence about the state it was meant to change

`_kickstart_daemon` ran `launchctl kickstart -k` under `check=True, timeout=10` and let both
`TimeoutExpired` and `CalledProcessError` escape. Two things were wrong, and only one of them was
the timeout. `kickstart -k` waits for the old instance to die *and* a new one to spawn, so 10s is
too tight for a job in a respawn storm — but the deeper error was treating the **request** as a
verdict on the **daemon**. `_wait_for_health` runs immediately after and is the only thing that
knows. A restart request that failed is context to carry; the health probe rules. `redeploy` now
carries the reason into both outcomes (`kickstart_warning`), and the timeout defaults to 60s
(`DEPLOYIT_KICKSTART_TIMEOUT`).

The raising also landed **after** `_sync_plugin_root` had already repaired the symlinks, so the
command destroyed the report of a repair it had successfully made. A partial success that reports
nothing is worse than a failure that reports the part that landed.

⚠ **A pinned indirection outlives its target, and rots in silence.** AGE-72's note above records
that `<state>/_plugin_root` is a symlink into the version-keyed plugin install cache. AGE-85 is
what happens at the other end of that arrangement: prune the cache version and both stable links
dangle, while the plist goes on naming them forever. launchd then respawns the job into the same
ENOENT for as long as nobody looks — **34,007 times** on the machine this was found on, every one
of them logged to `backend.err.log` and nowhere else. `status` reported a bare `backend: DOWN`;
`deploy` printed one `Connection refused` warning, published to the index, and returned `ok`. The
install page 502'd. **Any pinned path that outlives what it points at needs a liveness check at the
point of use, not just a writer that got it right once.**

The repair rule is narrow on purpose: `_heal_backend_link` fixes a link that is **broken**, and
leaves one that **resolves** alone even when it names a different root. A dangling link means the
daemon is already dead, so re-pointing it can displace nothing; a resolving link may be a
deliberate `redeploy --source <checkout>` pin, and silently dragging it back to the cache copy
would be its own defect. `status` stays read-only — it names the stale link and the remedy, and
repairs nothing.

**The class, not the instance.** `main()` now converts any unexpected exception into the JSON
contract (`ok:false`, `unexpected:true`, the command named, traceback still on stderr). The
orchestrator skill's entire interface is `ok`/`display`; it has nothing to show a user when a
traceback arrives instead. Ten other `check=True` subprocess calls in `deployit-cli` could have
escaped the same way, and `cmd_status` catches only `FileNotFoundError` around a `json.loads` — the
guard's regression test drives that real corrupt-index path rather than a synthetic raise. The
backstop is not a licence to stop catching what a command can actually explain.

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

- The candidate test graph runs `tests/plugin-content-drift.sh` regressions and
  explicitly evaluates candidate source with `scripts/check-plugin-content.sh`.
  Unreleased changes and missing tags are disclosed, never called release proof.
  This contract is identical in ordinary, linked and detached checkouts.
- **Before release publication or normal version-keyed installation from a
  checkout, `make validate-release` must pass.** It combines manifest-version
  validation with strict tag-to-HEAD and staged/unstaged/untracked shipped-content
  checks. Missing release tags fail. The checker defaults to strict release mode.
  VERSION and the marketplace manifest count, alongside plugin runtime files;
  plugin tests, `*.bats`, and top-level plugin READMEs remain excluded.
- Disposable installation smokes test candidate packaging, not release readiness
  or the user's active cache. After supported installation, verify the installed
  runtime separately. No repository command intercepts external installers.
  See `docs/spec/plugin-content-validation.md` for the full contract.
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
