# Execution Loop

Complete specification for the autonomous execution loop. The SKILL.md router dispatches here for `/pilot run` and `/pilot resume`.

## Prerequisites

Before entering the loop, the caller must have:
1. Acquired the session lock
2. Set up the auto-resume trigger (or skipped if validation failed)
3. Read/created `.pilot/config.json`
4. Read/created `.pilot/state.json` with `status: "running"`
5. Verified `.pilot/plan-mapping.json` exists

## Loop

```
stories_this_session = 0  # counts unique stories reaching done

loop:
```

### Step 0: Storyhook Health Check

Before every operation that touches storyhook, track consecutive failures:

```
If state.storyhook_consecutive_failures >= 3:
  → write_handoff("storyhook unavailable — 3 consecutive failures")
  → goto pause
```

The counter resets to 0 on ANY successful storyhook operation. Pattern: fail, fail → counter=2 → succeed → counter=0.

### Step 0a: Runaway Safeguard Check

```
Read config.json (fresh from disk every iteration)
Read state.json (fresh from disk every iteration)

If state.sessions_completed >= config.max_sessions:
  → write_handoff("Runaway safeguard: max sessions reached ({sessions_completed}/{max_sessions}). Review progress with /pilot status.")
  → goto pause

If state.total_retries >= config.max_total_retries:
  → write_handoff("Runaway safeguard: max total retries reached ({total_retries}/{max_total_retries}). Review progress with /pilot status.")
  → goto pause
```

### Step 1: Pick Next Story

```bash
story next --json
```

Parse the response:
- **Story returned**: Proceed with this story
- **No story, all done**: `goto complete`
- **No story, some blocked**: `write_handoff("blocked stories remain — user intervention needed")`, `goto pause`
- **Storyhook error**: Increment `storyhook_consecutive_failures`, continue to top of loop

### Step 2: Load Just-in-Time Context

Load only what this specific story needs:

1. **Story criteria**: From storyhook (title, acceptance criteria from comments)
2. **Design section**: From `plan-mapping.json` → `stories[story_id].design_section`
3. **Expected files**: From `plan-mapping.json` → `stories[story_id].files_expected`
4. **Predecessor diffs**: Git diffs from recently completed stories
   - Truncated: most recent 3 stories OR 5000 lines, whichever is smaller
   - If larger → generate a brief summary instead
5. **Prior evaluator feedback**: If this is a retry, extract structured JSON feedback from storyhook comments on this story

### Step 3: Generate

```
story HP-N is in-progress
Update lock heartbeat (before spawning — reflects active work)
git checkout .  # clean working tree for fresh attempt
```

**Spawn generator agent** as an isolated subagent:

```
Agent(
  subagent_type: "general-purpose",
  prompt: <constructed prompt with:
    - Story title and acceptance criteria
    - Relevant DESIGN.md section (from plan-mapping.json)
    - File list to read (files_expected + related existing files)
    - Memory entities for this component
    - Prior evaluator feedback (if retry)
    - Generator agent instructions (from agents/generator.md)
  >
)
```

**Parse generator response**:
- `status: "complete"` → proceed to step 4
- `status: "blocked"` or `status: "needs_decision"` →
  - `story HP-N is blocked`
  - `story HP-N '{"blocked_reason":"decision","description":"<generator's description>"}'`
  - Continue to next iteration (step 0)

**Dry-run mode**: Skip subagent spawn. Return canned response based on `--dry-run-mode`.

### Step 3a: Post-Generator Integrity Check

Defense-in-depth: verify the generator did not modify pilot state files.

```bash
# Before generator spawn, compute checksums:
md5sum .pilot/config.json .pilot/state.json > /tmp/pilot-pre-gen-checksums

# After generator returns:
md5sum .pilot/config.json .pilot/state.json > /tmp/pilot-post-gen-checksums

diff /tmp/pilot-pre-gen-checksums /tmp/pilot-post-gen-checksums
```

If checksums differ:
- Revert `.pilot/` changes: `git checkout .pilot/`
- Mark story blocked: `story HP-N is blocked`
- Add comment: `story HP-N '{"blocked_reason":"integrity","description":"Generator modified pilot state files"}'`
- Continue to next iteration

### Step 4: Deterministic Pre-Checks

Follow `references/deterministic-checks.md`:

1. **Test suite**: Run project tests
   - If test fails → re-run failing test once
   - If passes on re-run → flag as flaky, record in handoff.md, proceed
   - If fails again → store feedback as storyhook comment → goto retry

2. **Linter / type checker**: Run project linter
   - If fails → store feedback → goto retry

3. **Stub grep**: Scan modified files for TODO/FIXME/stub patterns
   - If stubs found → store feedback → goto retry

### Step 4a: Generator Scope Check

```bash
git diff --name-only
```

Compare against `plan-mapping.json`'s `files_expected` for this story.

- Unexpected files modified → log warning in handoff.md (warning only, not failure)

### Step 5: Evaluate

```
story HP-N is verifying
Update lock heartbeat (before spawning evaluator)
```

**Spawn evaluator agent** as an isolated subagent:

```
Agent(
  subagent_type: "general-purpose",
  prompt: <constructed prompt with:
    - Acceptance criteria for the story
    - git diff of uncommitted changes
    - Deterministic check output (test results, linter, stub grep)
    - Relevant DESIGN.md section
    - Evaluator agent instructions (from agents/evaluator.md)
  >
)
```

**Parse evaluator response**:
- `verdict: "pass"` →
  - Commit atomically: `git add -A && git commit -m "feat(<story>): <title>"`
  - `story HP-N is done`
  - Sync git if needed
  - Continue to step 6
- `verdict: "fail"` →
  - Store structured JSON feedback as storyhook comment:
    `story HP-N '{"verdict":"fail","failures":[...]}'`
  - goto retry

**Dry-run mode**: Skip subagent spawn. Return canned verdict based on mode.

### Step 5a: Post-Evaluator Integrity Check

The evaluator should have modified ZERO files.

```bash
git diff --name-only
```

If any files were modified that weren't there before the evaluator:
1. Discard evaluator verdict
2. Revert evaluator's changes: `git checkout .` (only the evaluator's changes — generator's changes are uncommitted)
   - Actually: since generator's changes are also uncommitted, we need to be careful
   - Better: use `git stash` before evaluator, `git stash pop` after, then check if anything extra appeared
   - Simplification: Record `git diff --name-only` before evaluator spawn. After evaluator, compare. If new files appeared, that's the evaluator.
3. Re-run evaluator (one retry only)
4. If it modifies files again → mark story blocked: `story HP-N is blocked` with integrity violation reason

### Step 5b: Log Verdict

Append to `.pilot/verdicts.jsonl`:

```json
{"story": "HP-N", "attempt": <attempt_number>, "verdict": "pass|fail", "failures": [...], "timestamp": "<now>"}
```

### Step 6: Canary Check

```
If state.canary_remaining > 0:
  Present evaluator verdict to user via AskUserQuestion:
    header: "Canary Review: <story title>"
    question: "<verdict summary>. Do you agree with this assessment?"
    options: ["Approved", "Override — I disagree", "Pause — let me review"]

  If "Approved" → canary_remaining -= 1, proceed
  If "Override" →
    If evaluator passed but user disagrees → story HP-N is todo (retry)
    If evaluator failed but user approves → commit, story HP-N is done
  If "Pause" → goto pause
```

See `references/canary-mode.md` for full protocol.

### Step 7: State Management

```
Update state.json:
  stories_attempted += 1 (if story reached evaluation, regardless of pass/fail)
  updated_at = now

Update lock heartbeat

If story reached done:
  stories_this_session += 1

If stories_this_session >= config.max_stories_per_session:
  → write_handoff("Session limit reached ({stories_this_session} stories completed)")
  → goto pause
```

`stories_this_session` counts unique stories reaching `done`, not total iterations. A story that retries 3 times and passes counts as 1.

### Step 8: Architectural Drift Check

```
Track stories_since_last_architect_review (in-memory counter, not persisted)

If completed story was last in its wave OR stories_since_last_architect_review >= 3:
  Spawn architect-reviewer subagent:
    Agent(
      subagent_type: "ideate:software-architect",
      prompt: "Review recent diffs against DESIGN.md contracts.
               Check for naming inconsistencies, interface drift, pattern violations.
               Recent commits: <git log of stories completed since last review>
               DESIGN.md: <relevant sections>"
    )
  Reset stories_since_last_architect_review = 0

  If architect reports significant drift:
    → write_handoff("Architectural drift detected: <details>")
    → goto pause
```

**Dry-run mode**: Skip architect review.

### Step 9: Re-Calibration Prompt

```
If state.stories_attempted % 10 == 0 AND state.canary_remaining == 0:
  Log note in handoff.md:
    "10 stories since last calibration check — review recent verdicts in .pilot/verdicts.jsonl"
```

### Retry

```
retry:
  git checkout .  # discard failed attempt's changes

  retry_count = state.retry_counts[story_id] || 0
  retry_count += 1
  state.retry_counts[story_id] = retry_count
  state.total_retries += 1

  If retry_count < config.max_retries:
    story HP-N is todo  # with evaluator/check feedback already in comments
    Write state.json to disk
    continue  # back to top of loop

  If retry_count >= config.max_retries:
    story HP-N is blocked
    story HP-N '{"blocked_reason":"max_retries","description":"Failed <max_retries> attempts","last_feedback":{...}}'
    Write state.json to disk
    continue  # back to top of loop — will pick next story
```

### Pause

```
pause:
  write_handoff()  # includes working context summary — see references/handoff-format.md
  state.status = "paused"
  state.sessions_completed += 1
  Write state.json to disk
  Release lock (delete lock.json)
  # Remote trigger will resume in next cycle
  return
```

### Complete

```
complete:
  # 1. Full test suite
  Run full project test suite
  If tests fail:
    Do NOT re-enter the loop
    Write failure details to handoff.md
    state.status = "paused"
    state.pause_reason = "final-test-suite-failed"
    Write state.json to disk
    Release lock
    # Do NOT remove auto-resume trigger
    Log: "Final test suite failed — manual review required. See handoff.md."
    return

  # 2. Storyhook report
  story summary
  story handoff --since <total_duration>

  # 3. Completion artifact
  Write .planning/COMPLETION.md:
    - Project summary
    - Stories completed with acceptance criteria
    - Test results
    - Notable decisions and patterns
    - Duration and session count

  # 4. Remove trigger
  Remove crontab entry (or disable systemd timer)

  # 5. Update state
  state.status = "complete"
  Write state.json to disk
  Release lock (delete lock.json)
```

## State Transition Summary

| From | To | Trigger |
|------|-----|---------|
| `todo` | `in-progress` | Story picked by orchestrator |
| `in-progress` | `verifying` | Generator completes |
| `verifying` | `done` | Evaluator passes + pre-checks pass |
| `verifying` | `todo` | Evaluator fails, retries remaining |
| `verifying` | `blocked` | Evaluator fails, max retries exhausted |
| `in-progress` | `blocked` | Generator reports needs_decision |
| `blocked` | `todo` | User unblocks manually |
| `in-progress` | `todo` | Crash recovery |
| `verifying` | `todo` | Crash recovery |

No transition targets `failed` — the state does not exist.
