---
name: execute
description: Generator-evaluator execution loop with retry and session persistence. Implements stories autonomously through isolated subagent spawning.
argument-hint: "[--dry-run [--dry-run-mode all-pass|all-fail|mixed]]"
effort: high
---

<!-- AGE-104 DELIVERY BEGIN -->
Read `${CLAUDE_PLUGIN_ROOT}/references/delivery.md` completely before this step, including standalone entry.
The local helper owns all specialist dispatch/wait/retry/cleanup; persist intent before
native dispatch and use the state-derived result envelope. On delivery_recovery, inspect
and recover existing batches before any fresh dispatch, artifact-based advancement or
cleanup. Preserve partial changes and write an incomplete handoff on failure; never
convert delivery failure into an evaluator verdict or a fresh generator retry.
In Plan mode inspect only; do not initialize delivery state or dispatch writers.
<!-- AGE-104 DELIVERY END -->

# Execute: Autonomous Generator-Evaluator Loop

You are the execute skill. Your job is to implement stories autonomously through a generator-evaluator loop with session persistence, retry logic, and clean handoffs.

**Read before starting — tiered, not "load all" (this skill re-runs once per
story under the default `max_stories_per_session: 1`, so every reference eagerly loaded here is a
recurring cost, not a one-time one):**

Always load, every entry:
- `references/execution-loop.md` — Full loop specification (AUTHORITATIVE — follow it completely)
- `references/storyhook-contract.md` — Story CLI command mapping (verb-first; the CLI has no MCP interface) — needed for every `story` call
- `references/team-roles.md`'s "Resolving subagent_type" section — governs the generator/evaluator/software-architect spawns below

Load only when the condition applies:
- `references/execution-loop-retry.md` — **only when an attempt has actually failed** (a
  pre-check returned `passed: false`, or the evaluator returned `verdict: "fail"`). A
  first-attempt pass never needs it. AUTHORITATIVE for that path — follow it completely.
- `references/execution-loop-complete.md` — **only when `story next` reports every story
  done**. Fires once per pipeline run, not once per session. AUTHORITATIVE for that path —
  follow it completely.
- `references/recovery-protocol.md` — **only on Resume** (`state_json_exists: true`, see Entry Modes below). A Fresh Start never needs it.
- `references/handoff-format.md` — **only once a pause or Complete is actually about to happen** (session limit hit, blocked, error, all stories done). Not needed while still looping through generate/evaluate.
- `references/session-locking.md` — **only if a `forge-lock.sh` call returns something other than the expected success** (contention, staleness) and you need the full protocol to interpret it. The inline calls in this skill and in `execution-loop.md` already carry the correct flags for the happy path.
- `references/auto-resume.md` — **only if freshen behaves unexpectedly** (queue/cancel fails in a surprising way, or you need to explain resume latency/hook-ordering guarantees to the user). The actionable step is just calling `forge-step-exit.sh`; this doc is mechanism background, not an instruction to follow.
- `references/deterministic-checks.md` — **only if a pre-check's `passed: false` needs more context than its own `details` field gives you.** The happy path (`all_passed: true`) never needs it.

The evaluator's own methodology and verdict schema live in its agent definition
(`agents/evaluator.md`) — that is the evaluator's context to carry when spawned, not the
orchestrator's, and not something this skill ever reads.

**Read inputs:**
- `.forge/plan-mapping.json` (required)
- `.forge/config.json` (read or create with defaults)
- `.forge/handoffs/handoff-decompose.md` (if fresh start)
- `.forge/handoffs/handoff-execute.md` (if resuming — this is the most recent execute handoff)

## Hard Rules

`skills/forge/SKILL.md`'s Hard Rules 1-8 apply here verbatim (storyhook authority, one story at a time,
generator-never-commits, evaluator-never-writes, clean working tree, re-read state from disk,
structured JSON feedback, `jq` for JSON) — read them there rather than re-deriving a second copy
here. Rule 9 (one `AskUserQuestion` at a time) applies if this skill ever needs to ask the user
something. Rule 11 (bounded agent delivery) governs every generator/evaluator/architect spawn
below. Rule 10's step-exit ordering is this skill's own Exit section, below.

## Entry Modes

`forge-state.sh` is dispatched at `execute --orchestrated` identically for a brand-new execute step
and for every crash/auto-resume — do NOT infer which one this is from conversation context. Read
the `state_json_exists` field from `forge-state.sh`'s JSON output (this is why it always runs
before dispatch — see `skills/forge/SKILL.md`'s State Detection section):

- **`state_json_exists: false`** → **Fresh Start** (below). There has never been an execute
  session for this pipeline run.
- **`state_json_exists: true`** → **Resume** (below). At least one execute session has already run
  the loop. Re-initializing `state.json` in this case would silently wipe
  `total_retries`/`retry_counts`/`sessions_completed` and defeat the runaway safeguards — never
  do it.

### Fresh Start (from decompose) — `state_json_exists: false`

1. Verify `.forge/plan-mapping.json` exists
2. Verify storyhook has stories in `todo` state
3. Read or create `.forge/config.json` with the defaults in `skills/forge/SKILL.md`'s **Settings**
   section — read them from there. Do not restate them here: the copy that used to live at this
   step carried a "keep byte-for-byte in sync" instruction and had already drifted out of sync
   anyway.
4. Generate a session ID (e.g. `sess-$(date -u +%Y%m%dT%H%M%SZ)-$$`) and acquire the lock:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/bin/forge-lock.sh acquire --session-id "$SESSION_ID" --forge-dir .forge
   ```
   If `acquired` is `false` (a fresh lock is held by another session), STOP and report:
   "Work is already running in another session (held_by: `<held_by>`)." See
   `references/session-locking.md` for the full protocol this script implements.
5. Initialize `.forge/state.json`
6. Check auto-resume capability (tmux availability)
7. Enter execution loop

### Resume (from auto-resume or manual `/forge continue`)

Follow `references/recovery-protocol.md`:
1. Lock check (fresh heartbeat → exit, stale → break, no lock → acquire)
2. Read state.json (missing → error, complete → exit)
3. Read handoff (missing → pause and ask user)
4. Crash recovery (reset in-progress/verifying stories to todo, clean tree)
5. Context gathering (git log, test suite)
6. Enter execution loop

## Execution Loop

<!-- AGE-55 INTEGRITY BEGIN -->
Read `${CLAUDE_PLUGIN_ROOT}/references/integrity-results.md` completely before the loop.
Require a verified snapshot before each generator or evaluator dispatch. Require a verified clean check
before pre-check progression or verdict use. Every evaluator path uses the post-worker check.
<!-- AGE-55 INTEGRITY END -->

Follow `references/execution-loop.md` **completely** — plus `references/execution-loop-retry.md`
once an attempt fails and `references/execution-loop-complete.md` once every story is done. High-level flow:

```
loop:
  0. Runaway & health safeguard check (forge-loop-state.sh runaway-check — max_sessions,
     max_total_retries, persisted storyhook-failure streak, all in one call)
  1. Pick next story (story next --json)
  2. Load just-in-time context (criteria, design section, predecessor diffs via
     forge-predecessor-diff.sh, prior feedback)
  3. Generate (spawn generator subagent)
  3a. Post-generator integrity check (forge-integrity.sh, content-hash based)
  4. Deterministic pre-checks (tests, linter, stub grep)
  4a. Generator scope check
  5. Evaluate (spawn evaluator subagent, read-only)
  5a. Post-evaluator integrity check (forge-integrity.sh, full-tree scope — runs BEFORE the
      verdict is acted on)
  5b. Log verdict to verdicts.jsonl (forge-verdict.sh)
  6. State management (forge-loop-state.sh attempt/done — update counters, check session limit)
  7. Architectural drift check (forge-loop-state.sh architect-check — persisted counter, every 3
     stories or wave boundary)
  retry: git checkout ., structured feedback, forge-loop-state.sh retry or block
  pause: write handoff (MUST include cold-start essentials), release lock, queue freshen
  complete: all stories done → transition to review+validate
```

### Generator and Evaluator Subagent Spawns

Full spawn construction (subagent_type resolution, override wiring, the `<files_to_read>` block)
is authoritative in `references/execution-loop.md` Steps 3 and 5 — read it there, don't re-derive
it here. In short: resolve `subagent_type` per `references/team-roles.md`'s "Resolving
subagent_type" (`agents:generator` / `agents:evaluator` preferred; `general-purpose` + inlined
`generator.md`/`evaluator.md` + the matching `agent-overrides/*-context.md` only as fallback —
never default straight to `general-purpose`, that's exactly what makes the Hard Rules cosmetic).

## Dry-Run Mode

When `--dry-run` is specified, replace subagent spawns with canned responses:
- **all-pass**: Every generator `{status: "complete"}`, every evaluator `{verdict: "pass"}`
- **all-fail**: Generator completes, evaluator always fails (tests retry logic)
- **mixed**: Odd stories pass first attempt, even stories fail twice then pass

Exercises full loop logic without API credits.

## State Files

| File | Tracked | Purpose |
|------|---------|---------|
| `config.json` | Yes | User-set limits |
| `plan-mapping.json` | Yes | Story-to-task mapping |
| `state.json` | No | Runtime state |
| `lock.json` | No | Session lock |
| `verdicts.jsonl` | No | Verdict history |

## Exit

Both paths below end in `forge-step-exit.sh` (`references/step-handoff.md`). Pause does not use its
default commit scope unmodified: it needs the session counter incremented first (a field
`forge-step-exit.sh` doesn't know about). Complete uses the default scope — closing the project
story in its step 2 writes to storyhook's own store, which is outside the repository and has no
path to commit (see `references/handoff-format.md`).

### Pause (session limit, blocked, error)

1. Write handoff to `.forge/handoffs/handoff-execute.md` (content: see step-handoff.md's Execute
   Handoff table — Working Context is REQUIRED here; see `references/handoff-format.md`'s
   "Cold-Start Essentials" for what each of its four subsections must contain)
2. Increment the session counter (the one `state.json` field `forge-step-exit.sh`'s own patch
   doesn't touch):
   ```bash
   jq '.sessions_completed = ((.sessions_completed // 0) + 1)' .forge/state.json > .forge/state.json.tmp \
     && mv .forge/state.json.tmp .forge/state.json
   ```
3. Release lock: `bash ${CLAUDE_PLUGIN_ROOT}/bin/forge-lock.sh release --session-id "$SESSION_ID" --forge-dir .forge`
4. ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/bin/forge-step-exit.sh --step execute \
     --summary "paused — [N] stories completed this session" --next "/forge resume"
   ```
5. STOP

### Complete (all stories done)

When all stories reach `done` (see `references/execution-loop-complete.md`'s "The project story" note —
this excludes `plan-mapping.json`'s `project_story`, which `story next` can never hand back and so
never reaches `done` through the loop itself):
1. Run full project test suite
   - If fails → set `status: "paused"`, `pause_reason: "final-test-suite-failed"`, do NOT cancel
     freshen, and do not proceed past this step (see `execution-loop-complete.md` for the
     exact state.json patch)
2. Close the project story (hygiene only, best-effort — never a precondition for anything below):
   `bash ${CLAUDE_PLUGIN_ROOT}/bin/forge-close-project-story.sh .` — ignore `.ok`/`.reason` beyond
   logging. `.closed` is informational only: the close writes to storyhook's store, not the repo,
   so there is nothing for step 5's commit to pick up either way.
3. Generate storyhook report: `story summary` + `story handoff`
4. Write handoff to `.forge/handoffs/handoff-execute.md`
5. ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/bin/forge-step-exit.sh --step execute \
     --summary "all stories complete" --next "/forge continue"
   ```
6. STOP

**If standalone:** Same loop, but on completion return to user instead of queuing freshen.
