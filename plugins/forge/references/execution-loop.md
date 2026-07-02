# Execution Loop

Complete specification for the autonomous execution loop. The SKILL.md router dispatches here for `/forge run` and `/forge resume`.

## Prerequisites

Before entering the loop, the caller must have:
1. Acquired the session lock
2. Checked auto-resume capability (tmux availability)
3. Read/created `.forge/config.json`
4. Read/created `.forge/state.json` with `status: "running"` and `resume: null` (clear stale resume context)
5. Verified `.forge/plan-mapping.json` exists

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
  → write_handoff("Runaway safeguard: max sessions reached ({sessions_completed}/{max_sessions}). Review progress with /forge status.")
  → goto pause

If state.total_retries >= config.max_total_retries:
  → write_handoff("Runaway safeguard: max total retries reached ({total_retries}/{max_total_retries}). Review progress with /forge status.")
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
story move HP-N in-progress
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
    - Generator agent instructions (from plugins/agents/agents/generator.md)
  >
)
```

**Parse generator response**:
- `status: "complete"` → proceed to step 4
- `status: "blocked"` or `status: "needs_decision"` →
  - `story move HP-N blocked`
  - `story comment HP-N '{"blocked_reason":"decision","description":"<generator's description>"}'`
  - Continue to next iteration (step 0)

**Dry-run mode**: Skip subagent spawn. Return canned response based on `--dry-run-mode`.

### Step 3a: Post-Generator Integrity Check

Defense-in-depth: verify the generator did not modify forge state files.

```bash
# Before generator spawn, compute checksums:
md5sum .forge/config.json .forge/state.json > /tmp/forge-pre-gen-checksums

# After generator returns:
md5sum .forge/config.json .forge/state.json > /tmp/forge-post-gen-checksums

diff /tmp/forge-pre-gen-checksums /tmp/forge-post-gen-checksums
```

If checksums differ:
- Revert `.forge/` changes: `git checkout .forge/`
- Mark story blocked: `story move HP-N blocked`
- Add comment: `story comment HP-N '{"blocked_reason":"integrity","description":"Generator modified forge state files"}'`
- Continue to next iteration

### Step 4: Deterministic Pre-Checks

Run the pre-checks script:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/forge-prechecks.sh --story-id HP-N --mapping .forge/plan-mapping.json
```

Parse the JSON result:
- If `all_passed` is true → proceed to evaluation
- If any check has `passed: false`:
  - Store failure details as storyhook comment: `story comment HP-N '{"check":"<name>","details":"<details>"}'`
  - Goto retry
- Flaky tests (in `flaky_tests` array) are flagged in handoff.md but do not count as failures
- Scope warnings (unexpected files) are logged in handoff.md but do not count as failures

### Step 5: Evaluate

```
story move HP-N verifying
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
    - Evaluator agent instructions (from plugins/agents/agents/evaluator.md)
  >
)
```

**Parse evaluator response**:
- `verdict: "pass"` →
  - Commit atomically: `git add -A && git commit -m "feat(<story>): <title>"`
  - `story move HP-N done`
  - Sync git if needed
  - Continue to step 6
- `verdict: "fail"` →
  - Store structured JSON feedback as storyhook comment:
    `story comment HP-N '{"verdict":"fail","failures":[...]}'`
  - goto retry

**Dry-run mode**: Skip subagent spawn. Return canned verdict based on mode.

### Step 5a: Post-Evaluator Integrity Check

The evaluator should have modified ZERO files. Record the file list before and compare after:

```bash
# Before evaluator spawn:
git diff --name-only > /tmp/forge-pre-eval-files

# After evaluator returns:
git diff --name-only > /tmp/forge-post-eval-files

diff /tmp/forge-pre-eval-files /tmp/forge-post-eval-files
```

If new files appeared (evaluator modified code):
1. Discard evaluator verdict
2. Restore pre-evaluator state: `git checkout .` then re-apply generator changes from the stash
3. Re-run evaluator (one retry only)
4. If it modifies files again → mark story blocked: `story move HP-N blocked` with integrity violation reason

### Step 5b: Log Verdict

Append to `.forge/verdicts.jsonl`:

```json
{"story": "HP-N", "attempt": <attempt_number>, "verdict": "pass|fail", "failures": [...], "timestamp": "<now>"}
```

### Step 6: State Management

```
Update state.json:
  stories_attempted += 1 (if story reached evaluation, regardless of pass/fail)
  updated_at = now

Update lock heartbeat

If story reached done:
  stories_this_session += 1

# Incremental handoff: update handoff.md with this story's outcomes.
# This ensures crash recovery has fresh context even without a clean pause.
# Append to "Stories Completed This Session" section and update "Working Context"
# with any new patterns, micro-decisions, or code landmarks from this story.
write_handoff(incremental=true)

If stories_this_session >= config.max_stories_per_session:
  → write_handoff("Session limit reached ({stories_this_session} stories completed)")
  → goto pause
```

`stories_this_session` counts unique stories reaching `done`, not total iterations. A story that retries 3 times and passes counts as 1.

### Step 7: Architectural Drift Check

```
Track stories_since_last_architect_review (in-memory counter, not persisted)

If completed story was last in its wave OR stories_since_last_architect_review >= 3:
  Spawn architect-reviewer subagent:
    Agent(
      subagent_type: "forge:software-architect",
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

### Retry

```
retry:
  git checkout .  # discard failed attempt's changes

  retry_count = state.retry_counts[story_id] || 0
  retry_count += 1
  state.retry_counts[story_id] = retry_count
  state.total_retries += 1

  If retry_count < config.max_retries:
    story move HP-N todo  # with evaluator/check feedback already in comments
    Write state.json to disk
    continue  # back to top of loop

  If retry_count >= config.max_retries:
    story move HP-N blocked
    story comment HP-N '{"blocked_reason":"max_retries","description":"Failed <max_retries> attempts","last_feedback":{...}}'
    Write state.json to disk
    continue  # back to top of loop — will pick next story
```

### Pause

```
pause:
  # The handoff MUST include Cold-Start Essentials (see references/handoff-format.md):
  #   - Patterns Established (naming, architecture, error handling)
  #   - Micro-Decisions (not in DESIGN.md but load-bearing)
  #   - Code Landmarks (key files and their roles)
  #   - Test State (pass/fail/flaky, run command, env setup)
  # This is critical because context WILL be cleared before resume.
  write_handoff()
  state.status = "paused"
  state.sessions_completed += 1
  state.resume = {
    command: "/forge resume",
    handoff_file: "handoffs/handoff-execute.md",
    summary: "Execution paused — {stories_this_session} stories completed. {reason}"
  }
  Write state.json to disk
  Release lock (delete lock.json)

  # Queue automatic context clear + resume via freshen:
  #   bash plugins/freshen/bin/freshen.sh queue "/forge resume" --source forge --summary "Execution paused — [N] stories completed"
  # If the queue command fails (tmux not available), log a warning:
  #   "Auto-resume unavailable. Run /forge resume manually."
  # Do NOT treat freshen failure as a fatal error — pause completes normally.
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
  Write .forge/COMPLETION.md:
    - Project summary
    - Stories completed with acceptance criteria
    - Test results
    - Notable decisions and patterns
    - Duration and session count

  # 4. Cancel freshen signal
  bash plugins/freshen/bin/freshen.sh cancel --source forge

  # 5. Update state
  state.status = "complete"
  state.resume = null
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
