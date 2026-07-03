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
PRE_GEN_HEAD=$(git rev-parse HEAD)  # F064 interim check — see Step 3a
```

**Resolve `subagent_type`** per `references/team-roles.md`'s "Resolving subagent_type" (Preferred:
`agents:generator` if exposed; Fallback: `general-purpose` with `generator.md` +
`agent-overrides/generator-context.md` inlined). **Spawn generator agent** as an isolated subagent:

```
Agent(
  subagent_type: "agents:generator",  # or "general-purpose" + inlined role on fallback — see above
  prompt: <constructed prompt with:
    - Story title and acceptance criteria
    - Relevant DESIGN.md section (from plan-mapping.json)
    - File list to read (files_expected + related existing files), as a <files_to_read> block
    - Memory entities for this component
    - Prior evaluator feedback (if retry)
    - [Fallback path only] Generator agent instructions (from generator.md) + forge override
      (from agent-overrides/generator-context.md)
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

Defense-in-depth: verify the generator did not modify forge state files, and (F064) did not commit.

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

**F064 — "generator never commits" check (interim, cheap):**

```bash
POST_GEN_HEAD=$(git rev-parse HEAD)
```

If `$POST_GEN_HEAD` != `$PRE_GEN_HEAD` (captured in Step 3), the generator committed, violating
Hard Rule 3. This is more serious than the checksum case above and is NOT auto-reverted — a `git
reset` here risks destroying the commit's forensic trail or interacting badly with any concurrent
work, and unlike the checksum-guarded files there's no cheap "just checkout" undo for a moved
HEAD. Instead:
- Mark story blocked: `story move HP-N blocked`
- Add comment: `story comment HP-N '{"blocked_reason":"integrity","description":"Generator committed (HEAD moved from <PRE_GEN_HEAD> to <POST_GEN_HEAD>) — violates Hard Rule 3. Needs manual review before continuing."}'`
- Write a handoff noting the exact SHAs and pause (do not silently continue the loop past this —
  treat it the same as a runaway-safeguard trip)

This is a lightweight interim guard, not exhaustive integrity scripting — the fuller
content-hash-based `bin/forge-integrity.sh` (WS4) is the durable replacement for this and Step 5a
below.

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
- Flaky tests (in `flaky_tests` array) are flagged in `.forge/handoffs/handoff-execute.md` but do not count as failures
- Scope warnings (unexpected files) are logged in `.forge/handoffs/handoff-execute.md` but do not count as failures

### Step 5: Evaluate

```
story move HP-N verifying
Update lock heartbeat (before spawning evaluator)
PRE_EVAL_SNAPSHOT=$(git stash create "forge-eval-guard-<story-id>" || true)  # see Step 5a
git diff --name-only > /tmp/forge-pre-eval-files
```

**Resolve `subagent_type`** per `references/team-roles.md`'s "Resolving subagent_type" (Preferred:
`agents:evaluator` if exposed — the platform then structurally blocks Write/Edit; Fallback:
`general-purpose` with `evaluator.md` + `agent-overrides/evaluator-context.md` inlined). **Spawn
evaluator agent** as an isolated subagent:

```
Agent(
  subagent_type: "agents:evaluator",  # or "general-purpose" + inlined role on fallback — see above
  prompt: <constructed prompt with:
    - Acceptance criteria for the story
    - git diff of uncommitted changes
    - Deterministic check output (test results, linter, stub grep)
    - Relevant DESIGN.md section
    - A <files_to_read> block listing the story's files_expected + files the diff touches (F065 —
      without this explicit block, evaluator.md's "Mandatory Initial Read" protocol never fires
      and the evaluator judges from the diff hunk alone, without full-file context)
    - [Fallback path only] Evaluator agent instructions (from evaluator.md) + forge override
      (from agent-overrides/evaluator-context.md)
  >
)
```

**Parse evaluator response** (the FULL schema — see `evaluator.md`'s Output Format, the single
authoritative verdict schema):
- `verdict: "pass"` →
  - Commit atomically: `git add -A && git commit -m "feat(<story>): <title>"`
  - `story move HP-N done`
  - Sync git if needed
  - Continue to step 6
- `verdict: "fail"` →
  - Store the COMPACT projection (`{verdict, failures}` — see `evaluator.md`'s "Storage split")
    as a storyhook comment: `story comment HP-N '{"verdict":"fail","failures":[...]}'`
  - goto retry

**Dry-run mode**: Skip subagent spawn. Return canned verdict based on mode.

### Step 5a: Post-Evaluator Integrity Check

**With WS3's `agents:evaluator` resolution in place (Step 5 above), this check is
belt-and-suspenders, not the primary enforcement:** when the evaluator resolves to the real
registered `agents:evaluator` type, the platform enforces `evaluator.md`'s `tools: Read, Bash,
Grep, Glob` and the evaluator structurally cannot call Write or Edit — a leaky evaluator "gets
blocked," not just "gets caught after the fact" (closes F057/F058 at the mechanism level for that
path). This check remains necessary for the `general-purpose` fallback path (no platform-level
tool restriction applies there) and as defense-in-depth either way.

The evaluator should have modified ZERO files. Compare the file list captured before spawn (Step
5) against after:

```bash
# After evaluator returns:
git diff --name-only > /tmp/forge-post-eval-files

diff /tmp/forge-pre-eval-files /tmp/forge-post-eval-files
```

If the file lists differ (a tracked file shows up in the diff that wasn't there before — the
evaluator modified a tracked file the generator hadn't already touched):
1. Discard the evaluator verdict.
2. Restore the actual pre-evaluator content — NOT "from the stash" (nothing is ever pushed onto
   the stash list, so that language was always false and following it literally would find
   nothing to pop): `$PRE_EVAL_SNAPSHOT` (captured in Step 5 via `git stash create`, which builds a
   commit object representing the working tree at that point WITHOUT touching the index, the
   working tree, or the stash list) is the actual restorable snapshot.
   - If `$PRE_EVAL_SNAPSHOT` is non-empty: `git checkout "$PRE_EVAL_SNAPSHOT" -- .`
   - If `$PRE_EVAL_SNAPSHOT` is empty (nothing was uncommitted before the evaluator ran — `git
     stash create` produces no output when the tree is clean): `git checkout .` is equivalent.
3. Re-run evaluator (one retry only).
4. If it modifies files again → mark story blocked: `story move HP-N blocked` with integrity violation reason.

**Known gap (F092), intentionally not fully solved here — WS4's `bin/forge-integrity.sh` closes
it:** `git diff --name-only` only lists unstaged changes to already-tracked files. It is blind to
two cases this check is supposed to catch:
- **An evaluator edit to a file the generator already modified** — the file was already in both
  the pre- and post-spawn diff-name lists, so nothing changes and the tampering is invisible.
- **An evaluator-created brand-new file** — untracked files never appear in `git diff --name-only`
  output at all, before or after.

For the `agents:evaluator` path this is an acceptable interim gap because the tool restriction
above is the real barrier for both cases (the evaluator cannot Write/Edit regardless of what this
heuristic would or wouldn't catch). For the `general-purpose` fallback path, these two cases are a
genuine blind spot until WS4 lands; don't treat this heuristic as a complete guarantee for that
path.

### Step 5b: Log Verdict

Append to `.forge/verdicts.jsonl` — this is the durable, uncapped home for the evaluator's FULL
response (see `evaluator.md`'s "Storage split"; only the storyhook comment gets the compact
`{verdict, failures}` projection, not this file):

```json
{"story": "HP-N", "attempt": <attempt_number>, "timestamp": "<now>", "verdict_full": {"verdict": "pass|fail", "failures": [...], "criteria_checks": [...], "edge_case_findings": [...], "security_findings": [...], "design_adherence": "aligned|drifted", "design_drift_details": "...", "summary": "..."}}
```

### Step 6: State Management

```
Update state.json:
  stories_attempted += 1 (if story reached evaluation, regardless of pass/fail)
  updated_at = now

Update lock heartbeat

If story reached done:
  stories_this_session += 1

# Incremental handoff: update .forge/handoffs/handoff-execute.md with this story's outcomes.
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
  Resolve subagent_type per references/team-roles.md's "Resolving subagent_type":
    Preferred: "agents:software-architect" (there is no "forge:" namespace — forge registers no
    agents of its own; software-architect lives in the agents plugin like every other shared
    agent). Fallback: "general-purpose" with software-architect.md +
    agent-overrides/software-architect-context.md inlined.

  Spawn architect-reviewer subagent:
    Agent(
      subagent_type: "agents:software-architect",  # or "general-purpose" + inlined role on fallback
      prompt: <constructed prompt with:
        - [Fallback path only] software-architect.md + agent-overrides/software-architect-context.md
        - Recent commits: <git log of stories completed since last review>
        - DESIGN.md: <relevant sections>
      >
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

**IMPORTANT:** "Complete" here means *all stories are done*, not *the pipeline is done*.
Execution must hand off to review_validate — it must NOT write `.forge/COMPLETION.md` and must NOT
cancel the freshen signal. `COMPLETION.md` is the pipeline's terminal artifact; it is owned
exclusively by the deploy step (`skills/deploy/SKILL.md`) and the "no deployment needed" branch of
the Deploy Permission Gate (`skills/forge/SKILL.md`). Writing it here would make `forge-state.sh`'s
very first check (`artifact_exists "COMPLETION.md"` → `state: complete`) treat the pipeline as
fully finished, silently skipping review, validate, triage, document, and deploy.

**The project story.** decompose auto-created a synthetic "project story" from PLAN.md's
`## Task Breakdown` heading (`plan-mapping.json`'s `project_story` — see
`references/story-decomposition.md`). storyhook's `story next` permanently refuses to ever hand
back a story with children, so the project story can *never* reach `done` through Step 1/3/5 of
this loop the way a real leaf task story does — "all real task stories done" is reached with the
project story still sitting at `todo` forever. That's expected, not a bug in this loop: reaching
`complete` only ever requires every *real* task story (i.e. everything except `project_story`) to
be `done` — `forge-state.sh`'s `check_storyhook()` already computes "all done" that way by reading
`project_story` straight out of `plan-mapping.json` and excluding it, so the `review_validate`
transition below works with zero special-casing here. Step 2 below closes the project story for
real anyway — purely so `story list` / `story summary` don't show a permanently-open story to
anyone inspecting the project afterward. If it fails or is skipped, nothing downstream breaks: the
`review_validate` transition never depended on it succeeding.

```
complete:
  # 1. Full test suite
  Run full project test suite
  If tests fail:
    Do NOT re-enter the loop
    Write failure details to .forge/handoffs/handoff-execute.md
    state.status = "paused"
    state.pause_reason = "final-test-suite-failed"
    Write state.json to disk
    Release lock
    # Do NOT remove auto-resume trigger
    Log: "Final test suite failed — manual review required. See handoffs/handoff-execute.md."
    return

  # 2. Close the project story (hygiene only -- see "The project story" above;
  #    best-effort, never a precondition for anything below).
  bash ${CLAUDE_PLUGIN_ROOT}/bin/forge-close-project-story.sh .
  # Ignore `.ok`/`.reason` beyond logging: `no_plan_mapping`, `story_cli_missing`,
  # etc. are all fine to silently continue past. Only `.closed == true` means
  # `.storyhook/` actually changed and needs to ride along in Step 4's commit.

  # 3. Storyhook report
  story summary
  story handoff --since <total_duration>

  # 4. Write handoff to .forge/handoffs/handoff-execute.md (NOT COMPLETION.md):
    - Project summary
    - Stories completed with acceptance criteria
    - Test results
    - Notable decisions and patterns
    - Duration and session count

  # 5. Commit (include .storyhook/ in case Step 2 closed the project story)
  git add .forge/ .storyhook/ && git commit -m "forge(execute): all stories complete"

  # 6. Queue freshen for the NEXT step (review_validate) — do NOT cancel:
  bash plugins/freshen/bin/freshen.sh queue "/forge continue" --source forge --summary "Execution complete — all stories done"

  # 7. Update state
  # status stays in the same two-value space as every other exit path
  # ("running" while looping, "paused" once the loop has exited for any
  # reason). There is no third "complete" status — storyhook + forge-state.sh
  # (not state.json) decide the review_validate transition, per Hard Rule 1
  # ("storyhook is authoritative for story-level state — never duplicate it
  # in forge files").
  state.status = "paused"
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
