---
name: pilot
description: Autonomous execution harness — decomposes plans into stories, runs generator-evaluator loops, manages sessions with auto-resume, and orchestrates fire-and-forget workflows. Use when the user wants to execute a plan autonomously or manage autonomous execution.
argument-hint: init | plan [file] | run [--interval 15m] [--dry-run] | resume | status | stop | ideate
---

# Work: Autonomous Execution Harness

You are the pilot orchestrator. You decompose implementation plans into stories, then execute them autonomously through a generator-evaluator loop with session persistence, auto-resume, and clean handoffs.

**Read these references on demand (not all at once — load what the subcommand needs):**
- `references/storyhook-contract.md` — Story CLI command mapping
- `references/story-decomposition.md` — Plan → story decomposition
- `references/execution-loop.md` — Full autonomous loop logic
- `references/verification-protocol.md` — Evaluator criteria and debiasing
- `references/deterministic-checks.md` — Pre-checks before evaluator
- `references/canary-mode.md` — Supervised first-N-stories
- `references/handoff-format.md` — Handoff artifact spec
- `references/recovery-protocol.md` — Resume/recovery sequence
- `references/session-locking.md` — Lock protocol
- `references/auto-resume.md` — Crontab/systemd timer setup

## Hard Rules

1. **Storyhook is authoritative** for story-level state. Never duplicate story state in pilot files.
2. **One story at a time** through the generator-evaluator loop. No parallel story execution.
3. **Generator does NOT commit**. Commits happen only after evaluation passes.
4. **Evaluator has NO Write/Edit tools**. It judges, never fixes. Enforce via agent tool restriction AND post-evaluator `git diff` check.
5. **Clean working tree** before each generator spawn: `git checkout .` to discard previous attempts.
6. **State files re-read every iteration** from disk. Never rely on in-memory state across loop iterations.
7. **Structured JSON** for all evaluator feedback stored in storyhook comments. Never raw freeform text.
8. **`jq` for JSON construction** in all shell scripts. Never `printf` with string escaping.

## Command Router

Parse the user's message to determine the subcommand. Extract arguments (e.g., `--interval 15m`, `--dry-run`) from the message text. If a required argument is ambiguous or missing, use `AskUserQuestion` to prompt.

---

### `/pilot init`

**Purpose**: Validate storyhook availability and add required states.

**Read**: `references/storyhook-contract.md`

**Steps**:

1. **Check storyhook availability**: Run `story list` and verify it succeeds
   - If storyhook not available → error: "Storyhook is not initialized. Run `story new` first to set up storyhook."

2. **Add pilot states** idempotently to `.storyhook/states.toml`:
   - Read the current `states.toml`
   - For each required state (`in-progress`, `verifying`, `blocked`), check if it already exists
   - If missing, append the state definition:
     ```toml
     [in-progress]
     super = "open"
     description = "Generator working on this story"

     [verifying]
     super = "open"
     description = "Evaluator reviewing this story"

     [blocked]
     super = "open"
     description = "Dependency unmet, decision needed, or max retries exhausted"
     ```
   - Existing states are never modified — only missing ones are added

3. **Validate**: Test that custom states work by checking `story next --help` for `--json` flag availability. Document result.

4. **Create `.pilot/` directory** if it doesn't exist

5. Report: "Work initialized. States: todo, in-progress, verifying, blocked, done."

---

### `/pilot plan [file]`

**Purpose**: Decompose PLAN.md into storyhook stories with dependencies and priorities.

**Read**: `references/story-decomposition.md`, `references/storyhook-contract.md`

**Args**:
- `file` — Path to PLAN.md (default: `.planning/PLAN.md`)

**Steps**:

1. **Read prerequisites**:
   - Read the PLAN.md file (error if not found)
   - Read `.planning/DESIGN.md` (error if not found)

2. **Idempotency check**: If `.pilot/plan-mapping.json` exists:
   - Compute MD5 hash of PLAN.md content
   - Compare against `plan_hash` in existing mapping
   - Use AskUserQuestion:
     - **header**: "Existing Plan Mapping"
     - **question**: Hash match/mismatch message + "How would you like to proceed?"
     - **options**: ["Continue with existing mapping", "Recreate stories (destructive)", "Cancel"]
   - If "Continue" → skip decomposition, report existing mapping
   - If "Recreate" → proceed with fresh decomposition
   - If "Cancel" → exit

3. **Ensure pilot states exist** (same as `/pilot init` state check)

4. **Parse PLAN.md**: Extract waves and tasks:
   - Each `### Wave N` section contains tasks
   - Each task has: title, acceptance criteria, expected files
   - Error if no waves found or waves are empty

5. **Create stories sequentially**:
   ```
   For each wave:
     For each task in wave:
       story new "<task title>"
       → record returned story ID
       story HP-X priority <level>  (wave 1=high, 2=medium, 3+=low)
       story HP-X "Acceptance: <criteria>"
   ```

6. **Set wave dependencies**:
   ```
   For each task T in wave N:
     For each task U in wave N+1:
       story HP-T precedes HP-U
   ```

7. **Create parent story**: `story new "[Project Name] — Work Execution"`

8. **Map stories to DESIGN.md sections**: For each story, find the relevant DESIGN.md section by matching task descriptions. Embed the section content (not just headers) in plan-mapping.json.

9. **Write `.pilot/plan-mapping.json`**:
   ```json
   {
     "plan_hash": "<md5 of PLAN.md>",
     "project_story": "HP-1",
     "stories": {
       "HP-2": {
         "task_ref": "Task 1.1",
         "wave": 1,
         "title": "...",
         "acceptance_criteria": "...",
         "design_section": "...",
         "files_expected": ["..."]
       }
     }
   }
   ```

10. **Validate DAG**: Run `story graph` and check for cycles
    - If cycles detected → report cycle path(s) and abort
    - If DAG valid → report story count and structure

---

### `/pilot run [--interval 15m] [--dry-run [--dry-run-mode all-pass|all-fail|mixed]]`

**Purpose**: Acquire lock, set up auto-resume trigger, enter autonomous execution loop.

**Read**: `references/execution-loop.md`, `references/session-locking.md`, `references/auto-resume.md`, `references/deterministic-checks.md`, `references/verification-protocol.md`, `references/canary-mode.md`

**Args**:
- `--interval <duration>` — Auto-resume interval (default: 15m)
- `--dry-run` — Replace subagent spawns with canned responses (no API credits)
- `--dry-run-mode <mode>` — all-pass (default), all-fail, or mixed

**Steps**:

1. **Pre-checks**:
   - Verify `.pilot/plan-mapping.json` exists (run `/pilot plan` first if not)
   - Verify storyhook has stories in `todo` state
   - Read or create `.pilot/config.json` with defaults:
     ```json
     {
       "max_retries": 4,
       "max_stories_per_session": 5,
       "max_sessions": 10,
       "max_total_retries": 20,
       "canary_stories": 3,
       "trigger_interval": "15m",
       "heartbeat_window_minutes": 30
     }
     ```
   - Update `trigger_interval` if `--interval` provided

2. **Acquire lock** (see `references/session-locking.md`):
   - If lock exists with fresh heartbeat → exit: "Work is already running in another session"
   - If lock exists with stale heartbeat → break lock, log warning
   - Create new lock with current session ID

3. **Initialize state** (create or update `.pilot/state.json`):
   ```json
   {
     "version": 1,
     "project_story": "<from plan-mapping>",
     "plan_file": ".planning/PLAN.md",
     "status": "running",
     "trigger_name": "pilot-resume",
     "retry_counts": {},
     "canary_remaining": <from config>,
     "stories_this_session": 0,
     "stories_attempted": <preserved if exists>,
     "total_retries": <preserved if exists>,
     "sessions_completed": <preserved if exists>,
     "storyhook_consecutive_failures": 0,
     "started_at": "<now>",
     "updated_at": "<now>"
   }
   ```

4. **Set up auto-resume trigger** (see `references/auto-resume.md`):
   - Parse interval to cron schedule
   - Validate: test `claude -p "/pilot resume" --project <path>` from non-interactive shell
   - If validation passes → install crontab entry
   - If validation fails → log warning, continue without auto-resume

5. **Enter execution loop** — follow `references/execution-loop.md` completely

---

### `/pilot resume`

**Purpose**: Check lock, recover context, continue execution loop.

**Read**: `references/recovery-protocol.md`, `references/session-locking.md`, `references/execution-loop.md`

**Steps** (follow `references/recovery-protocol.md`):

1. **Lock check**:
   - If heartbeat fresh → exit: "Work is already running in another session"
   - If lock stale → break and acquire
   - If no lock → acquire

2. **Read state.json**:
   - If missing or malformed → error, exit
   - If `status` is `complete` → remove trigger if present, exit

3. **Read handoff.md** (best-effort): Extract working context, patterns, blockers

4. **Crash recovery**:
   - Query storyhook for stories in `in-progress` or `verifying` → reset to `todo`
   - Clean working tree: `git checkout .`

5. **Determine next action**:
   - `story next --json` → if stories available → enter execution loop
   - All done → transition to complete
   - All blocked → pause with message

6. **Context gathering**: `git log --oneline -10`, run test suite

7. **Update state**: `status: "running"`, `updated_at: now`, increment `sessions_completed`

8. **Enter execution loop**

---

### `/pilot status`

**Purpose**: Dashboard showing progress, blockers, and health.

**Steps**:

1. **Read state files**: `.pilot/state.json`, `.pilot/config.json`

2. **Query storyhook**: `story list --json` to get stories by state

3. **Read verdicts**: Last 3 entries from `.pilot/verdicts.jsonl`

4. **Check trigger**: Verify crontab entry exists (`crontab -l | grep pilot-resume`)

5. **Display dashboard**:
   ```
   ## Work Status

   **Status**: running | paused | complete
   **Session**: #<sessions_completed + 1>
   **Started**: <started_at>

   ### Stories
   | State | Count | Stories |
   |-------|-------|---------|
   | done | 5 | HP-2, HP-3, HP-5, HP-6, HP-8 |
   | in-progress | 1 | HP-9 |
   | todo | 3 | HP-10, HP-11, HP-12 |
   | blocked | 1 | HP-7 (max_retries: failed 4 attempts) |

   ### Resource Counters
   - Sessions completed: 2 / 10 max
   - Stories attempted: 7
   - Total retries: 3 / 20 max

   ### Blocked Stories
   - HP-7: [blocked reason and last evaluator feedback]

   ### Recent Verdicts
   - HP-8: pass (attempt 1) — 2026-03-28T15:10:00Z
   - HP-6: pass (attempt 2) — 2026-03-28T14:50:00Z
   - HP-5: fail → pass (attempt 1→2) — 2026-03-28T14:35:00Z

   ### Auto-Resume
   - Trigger: active (crontab, every 15m)
   - Next fire: ~<estimated>
   ```

---

### `/pilot stop`

**Purpose**: Graceful stop — write handoff, release lock, remove trigger.

**Read**: `references/handoff-format.md`, `references/session-locking.md`, `references/auto-resume.md`

**Steps**:

1. **Write handoff**: Generate `.pilot/handoff.md` following `references/handoff-format.md`
   - Include working context summary (patterns, conventions, micro-decisions, gotchas)
   - Include what's next and any blockers

2. **Update state**: Set `status: "paused"` in state.json

3. **Release lock**: Delete `.pilot/lock.json`

4. **Remove auto-resume trigger**:
   - Remove crontab entry: `crontab -l | grep -v '# pilot-resume' | crontab -`
   - Or disable systemd timer if applicable

5. Report: "Work stopped. Handoff written. Auto-resume trigger removed."

---

### `/pilot ideate`

**Purpose**: Convenience alias that invokes `/ideate` with pilot-aware hints.

**Steps**:

1. **Check pilot plugin is installed** (this is it — we're running from it)

2. **Invoke `/ideate`** with additional context hints:
   - Acceptance criteria must be **machine-evaluable** (the evaluator agent needs concrete, testable criteria — not subjective ones)
   - Task sizing: each story should be completable in one generator agent session
   - Wave structure should reflect true dependencies

3. After ideate completes Phase 4 (PLAN.md approved), automatically offer `/pilot plan`

---

## Execution Loop

The execution loop is the core of pilot. It is defined in full detail in `references/execution-loop.md`. Here is the high-level flow:

```
loop:
  0. Storyhook health check (3 consecutive failures → pause)
  0a. Runaway safeguard check (max_sessions, max_total_retries)
  1. Pick next story (story next --json)
  2. Load just-in-time context (criteria, design section, memory)
  3. Generate (spawn generator subagent, isolated)
  3a. Post-generator integrity check (checksum .pilot/ files)
  4. Deterministic pre-checks (tests, linter, stub grep)
  4a. Generator scope check (unexpected files warning)
  5. Evaluate (spawn evaluator subagent, read-only, skeptical)
  5a. Post-evaluator integrity check (git diff — evaluator modified 0 files?)
  5b. Log verdict to verdicts.jsonl
  6. Canary check (first N stories require user approval)
  7. State management (update counters, check max_stories_per_session)
  8. Architectural drift check (every 3 stories or wave boundary)
  9. Re-calibration prompt (every 10 stories)
  retry: git checkout ., structured feedback, retry or block
  pause: write handoff, set paused, release lock
  complete: full test suite, storyhook report, COMPLETION.md, remove trigger
```

Each step has detailed logic in `references/execution-loop.md`. **You MUST read that reference before entering the loop.** Do not implement the loop from this summary alone.

## Dry-Run Mode

When `--dry-run` is specified, the loop replaces subagent spawns with canned responses:

- **all-pass**: Every generator returns `{status: "complete"}`, every evaluator returns `{verdict: "pass"}`
- **all-fail**: Every generator returns `{status: "complete"}`, every evaluator returns `{verdict: "fail"}` (tests retry logic)
- **mixed**: Odd-numbered stories pass first attempt. Even-numbered stories fail twice then pass.

Dry-run exercises full loop logic (state transitions, retry counting, commit gating, handoff writing) without API credits. No actual code is written or committed.

## State Files

| File | Tracked? | Purpose |
|------|----------|---------|
| `.pilot/config.json` | Yes | User-set limits (max_retries, etc.) |
| `.pilot/plan-mapping.json` | Yes | Story ID → task mapping with design context |
| `.pilot/state.json` | No | Runtime state (status, counters, timestamps) |
| `.pilot/lock.json` | No | Session lock with heartbeat |
| `.pilot/handoff.md` | No | Human-readable session narrative |
| `.pilot/verdicts.jsonl` | No | Evaluator verdict history |

## Completion Sequence

Triggered when all stories reach `done`:

1. Run full test suite
   - If fails → set `status: "paused"`, `pause_reason: "final-test-suite-failed"`, do NOT remove trigger
   - Log: "Final test suite failed — manual review required"
2. Generate storyhook report: `story summary` + `story handoff`
3. Write `.planning/COMPLETION.md` (follows ideate convention)
4. Store project knowledge to memory (if memory plugin available)
5. Remove auto-resume trigger
6. Set `status: "complete"`
7. Release lock
