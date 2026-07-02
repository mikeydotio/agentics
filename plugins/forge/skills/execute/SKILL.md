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
3. Read or create `.forge/config.json` with defaults:
   ```json
   {
     "yolo": false,
     "max_fix_cycles": 3,
     "max_fix_cycles_yolo": 10,
     "when_in_doubt": "escalate",
     "max_retries": 4,
     "max_stories_per_session": 1,
     "max_sessions": 200,
     "max_total_retries": 20,
     "heartbeat_window_minutes": 30
   }
   ```
4. Acquire lock (see `references/session-locking.md`)
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
  0. Storyhook health check (3 consecutive failures → pause)
  0a. Runaway safeguard check (max_sessions, max_total_retries)
  1. Pick next story (story next --json)
  2. Load just-in-time context (criteria, design section, predecessor diffs, prior feedback)
  3. Generate (spawn generator subagent)
  3a. Post-generator integrity check (checksums)
  4. Deterministic pre-checks (tests, linter, stub grep)
  4a. Generator scope check
  5. Evaluate (spawn evaluator subagent, read-only)
  5a. Post-evaluator integrity check (git diff)
  5b. Log verdict to verdicts.jsonl
  6. State management (update counters, check session limit)
  7. Architectural drift check (every 3 stories or wave boundary)
  retry: git checkout ., structured feedback, retry or block
  pause: write handoff (MUST include cold-start essentials), release lock, queue freshen
  complete: all stories done → transition to review+validate
```

### Generator Subagent Spawn

```
Agent(
  subagent_type: "general-purpose",
  prompt: <constructed with:
    - Story title and acceptance criteria
    - Relevant DESIGN.md section (from plan-mapping.json)
    - File list to read (files_expected + related existing files)
    - Prior evaluator feedback (if retry)
    - Generator agent instructions (from plugins/agents/agents/generator.md)
  >
)
```

### Evaluator Subagent Spawn

```
Agent(
  subagent_type: "general-purpose",
  prompt: <constructed with:
    - Acceptance criteria for the story
    - git diff of uncommitted changes
    - Deterministic check output
    - Relevant DESIGN.md section
    - Evaluator agent instructions (from plugins/agents/agents/evaluator.md)
  >
)
```

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

When all stories reach `done`:
1. Run full project test suite
   - If fails → set `status: "paused"`, `pause_reason: "final-test-suite-failed"`, do NOT cancel freshen
2. Generate storyhook report: `story summary` + `story handoff`
3. Write handoff to `.forge/handoffs/handoff-execute.md`
4. Commit: `git add .forge/ && git commit -m "forge(execute): all stories complete"`
5. Queue freshen for next step (review+validate): `bash plugins/freshen/bin/freshen.sh queue "/forge continue" --source forge --summary "Execution complete — all stories done"`
6. STOP

**If standalone:** Same loop, but on completion return to user instead of queuing freshen.
