---
name: execute
description: Generator-evaluator execution loop with retry and session persistence. Implements stories autonomously through isolated subagent spawning.
argument-hint: "[--dry-run [--dry-run-mode all-pass|all-fail|mixed]]"
---

# Execute: Autonomous Generator-Evaluator Loop

You are the execute skill. Your job is to implement stories autonomously through a generator-evaluator loop with session persistence, retry logic, and clean handoffs.

**Read before starting (load all — this is the most complex skill):**
- `references/execution-loop.md` — Full loop specification (AUTHORITATIVE — follow it completely)
- `references/session-locking.md` — Lock protocol
- `references/recovery-protocol.md` — Resume/recovery sequence
- `references/auto-resume.md` — Freshen-based auto-resume
- `references/deterministic-checks.md` — Pre-checks before evaluator
- `references/verification-protocol.md` — Evaluator criteria and debiasing
- `references/handoff-format.md` — Handoff artifact spec
- `references/storyhook-contract.md` — Story CLI command mapping (verb-first; the CLI has no MCP interface)
- `references/team-roles.md` — "Resolving subagent_type" — governs the generator/evaluator/software-architect spawns below

**Read inputs:**
- `.forge/plan-mapping.json` (required)
- `.forge/config.json` (read or create with defaults)
- `.forge/handoffs/handoff-decompose.md` (if fresh start)
- `.forge/handoffs/handoff-execute.md` (if resuming — this is the most recent execute handoff)

## Hard Rules

1. **Storyhook is authoritative** for story-level state.
2. **One story at a time** through the generator-evaluator loop.
3. **Generator does NOT commit.** Commits happen only after evaluation passes.
4. **Evaluator has NO Write/Edit tools.** It judges, never fixes.
5. **Clean working tree** before each generator spawn: `git checkout .`
6. **State files re-read every iteration** from disk.
7. **Structured JSON** for all evaluator feedback in storyhook comments.
8. **`jq` for JSON construction** in all shell commands.

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
3. Read or create `.forge/config.json` with defaults (must match `skills/forge/SKILL.md`'s
   Settings section byte-for-byte — see that section's note on why
   `max_total_retries` is 100, not a smaller number, per F097):
   ```json
   {
     "yolo": false,
     "max_fix_cycles": 3,
     "max_fix_cycles_yolo": 10,
     "when_in_doubt": "escalate",
     "max_retries": 4,
     "max_stories_per_session": 1,
     "max_sessions": 200,
     "max_total_retries": 100,
     "heartbeat_window_minutes": 30
   }
   ```
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

Follow `references/execution-loop.md` **completely**. High-level flow:

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

### Pause (session limit, blocked, error)

1. Write handoff to `.forge/handoffs/handoff-execute.md` with **cold-start essentials**:
   - Patterns Established (naming, architecture, error handling)
   - Micro-Decisions (not in DESIGN.md but load-bearing)
   - Code Landmarks (key files and their roles)
   - Test State (pass/fail/flaky, run command, env setup)
2. Update state.json: `status: "paused"`, increment `sessions_completed`
3. Release lock
4. Queue freshen: `bash plugins/freshen/bin/freshen.sh queue "/forge resume" --source forge --summary "Execution paused — [N] stories completed this session"`
5. STOP

### Complete (all stories done)

When all stories reach `done` (see `references/execution-loop.md`'s "The project story" note —
this excludes `plan-mapping.json`'s `project_story`, which `story next` can never hand back and so
never reaches `done` through the loop itself):
1. Run full project test suite
   - If fails → set `status: "paused"`, `pause_reason: "final-test-suite-failed"`, do NOT cancel freshen
2. Close the project story (hygiene only, best-effort — never a precondition for anything below):
   `bash ${CLAUDE_PLUGIN_ROOT}/bin/forge-close-project-story.sh .` — ignore `.ok`/`.reason` beyond
   logging; only `.closed == true` means `.storyhook/` changed and must ride along in step 5's commit.
3. Generate storyhook report: `story summary` + `story handoff`
4. Write handoff to `.forge/handoffs/handoff-execute.md`
5. Commit (include `.storyhook/` in case step 2 closed the project story):
   `git add .forge/ .storyhook/ && git commit -m "forge(execute): all stories complete"`
6. Queue freshen for next step (review+validate): `bash plugins/freshen/bin/freshen.sh queue "/forge continue" --source forge --summary "Execution complete — all stories done"`
7. STOP

**If standalone:** Same loop, but on completion return to user instead of queuing freshen.
