# Execution Loop

**Dispatch/recovery prerequisite:** read `${CLAUDE_PLUGIN_ROOT}/references/delivery.md`; the helper owns finite
collection, pending evidence and cleanup. Handle delivery_recovery before continuing.

**Integrity prerequisite:** read `${CLAUDE_PLUGIN_ROOT}/references/integrity-results.md` completely.
It is the only result-classification contract for every snapshot and check below.

Complete specification for the autonomous execution loop. The SKILL.md router dispatches here for `/forge run` and `/forge resume`.

Per-iteration bookkeeping (counters, locks, verdicts, integrity checks) is scripted — see
`bin/forge-loop-state.sh`, `bin/forge-lock.sh`, `bin/forge-verdict.sh`, `bin/forge-integrity.sh`,
`bin/forge-predecessor-diff.sh` (WS4). The model calls a script and branches on its returned JSON;
it never hand-edits `.forge/state.json`'s counters, hand-computes lock staleness, or hand-diffs
the working tree. What stays genuine model judgment: constructing agent prompts, writing handoff
*content*, and deciding what a summarized predecessor diff should say when one is too large to
paste verbatim.

**This file is the always-loaded core — tiered, not "load all". The execute skill re-runs once
per story under the default `max_stories_per_session: 1`, so everything resident here is a
recurring cost, not a one-time one:**

Here, and reached on essentially every entry:
- **Prerequisites** and **Steps 0–7** — every iteration walks all of them.
- **Pause** — under the default `max_stories_per_session: 1`, Step 6 trips the session limit on
  every successful story, so the loop exits through Pause nearly every session. It stays
  resident for that reason, not for symmetry with the two below.

Load only when the condition applies. Each is AUTHORITATIVE for its own path exactly as this
file is for Steps 0–7 — follow it completely once loaded:
- `references/execution-loop-retry.md` — **only when an attempt has actually failed**: a
  deterministic pre-check returned `passed: false` (Step 4), or the evaluator returned
  `verdict: "fail"` (Step 5a). A story that passes first attempt never reaches it.
- `references/execution-loop-complete.md` — **only when Step 1's `story next` reports every
  story done**. This fires once per pipeline run, not once per session.

## Prerequisites

Before entering the loop, the caller must have:
1. Generated a session ID and acquired the session lock: `bash
   ${CLAUDE_PLUGIN_ROOT}/bin/forge-lock.sh acquire --session-id "$SESSION_ID" --forge-dir .forge`
   (see `references/session-locking.md`) — if `acquired` is `false`, STOP here.
2. Checked auto-resume capability (tmux availability)
3. Read/created `.forge/config.json`
4. Read/created `.forge/state.json` with `status: "running"` and `resume: null` (clear stale resume context)
5. Verified `.forge/plan-mapping.json` exists

## Loop

```
stories_this_session = 0  # counts unique stories reaching done

loop:
```

### Step 0: Runaway & Health Safeguard Check

One call covers all three halt conditions (max sessions, max total retries, and the persisted
storyhook-failure streak):

```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/forge-loop-state.sh runaway-check --forge-dir .forge
```

- `halt: true` → `write_handoff(reason)` (the script's `reason` field already names which
  safeguard tripped and the exact counter/limit values) → `goto pause`
- `halt: false` → proceed to Step 1

### Step 1: Pick Next Story

```bash
story next --json
```

Parse the response:
- **Story returned**: `bash forge-loop-state.sh storyhook-failure --result ok --forge-dir .forge`
  (resets the persisted consecutive-failure counter), proceed with this story
- **No story, all done**: `bash forge-loop-state.sh storyhook-failure --result ok --forge-dir
  .forge`, `goto complete`
- **No story, some blocked**: `bash forge-loop-state.sh storyhook-failure --result ok --forge-dir
  .forge`, `write_handoff("blocked stories remain — user intervention needed")`, `goto pause`
- **Storyhook error** (nonzero exit / unparseable JSON): `bash forge-loop-state.sh
  storyhook-failure --result fail --forge-dir .forge`, continue to top of loop (Step 0 will halt
  once the persisted counter reaches 3 — it survives the mandatory fresh state re-read per Hard
  Rule 6, unlike the old in-memory counter)

### Step 2: Load Just-in-Time Context

Load only what this specific story needs:

1. **Story criteria**: From storyhook (title, acceptance criteria from comments)
2. **Design section**: From `plan-mapping.json` → `stories[story_id].design_section`
3. **Expected files**: From `plan-mapping.json` → `stories[story_id].files_expected`
4. **Predecessor diffs**:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/bin/forge-predecessor-diff.sh --limit-stories 3 --limit-lines 5000 --project-dir .
   ```
   - `truncated: false` → paste `.diff` directly into the generator prompt.
   - `truncated: true` → `.diff` is empty (not meant to be pasted at that size); write a brief
     summary of `.commits` instead (this judgment call — what the summary should say — stays with
     the model; the script only does the mechanical truncation and reports whether it truncated).
5. **Prior evaluator feedback**: If this is a retry, extract structured JSON feedback from storyhook comments on this story

### Step 3: Generate

```bash
story move HP-N in-progress
bash ${CLAUDE_PLUGIN_ROOT}/bin/forge-lock.sh heartbeat --session-id "$SESSION_ID" --forge-dir .forge
git checkout .  # clean working tree for fresh attempt
bash ${CLAUDE_PLUGIN_ROOT}/bin/forge-integrity.sh snapshot --phase pre-gen --forge-dir .forge --scope forge-only --session-id "$SESSION_ID"
```

Apply the shared integrity result contract. Spawn no generator unless this result is a verified snapshot.
Follow its pre-worker unverified action before the dispatch instructions below.

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
- `status: "complete"` → proceed to step 3a
- `status: "blocked"` or `status: "needs_decision"` →
  - `story move HP-N blocked`
  - `story comment HP-N '{"blocked_reason":"decision","description":"<generator's description>"}'`
  - Continue to next iteration (step 0)

**Dry-run mode**: Skip subagent spawn. Return canned response based on `--dry-run-mode`.

### Step 3a: Post-Generator Integrity Check

Defense-in-depth: verify the generator did not modify forge state files, and did not commit.

```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/forge-integrity.sh check --phase pre-gen --forge-dir .forge --scope forge-only --session-id "$SESSION_ID"
```

Apply the shared integrity result contract for the generator's post-worker check. Only a verified clean check may proceed to Step 4.
Follow its unverified and tamper actions; never branch on `tampered` alone or treat restoration as validation.

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

```bash
story move HP-N verifying
bash ${CLAUDE_PLUGIN_ROOT}/bin/forge-lock.sh heartbeat --session-id "$SESSION_ID" --forge-dir .forge
bash ${CLAUDE_PLUGIN_ROOT}/bin/forge-integrity.sh snapshot --phase pre-eval --forge-dir .forge --scope full-tree --session-id "$SESSION_ID"
```

Apply the shared integrity result contract. Spawn no evaluator unless this result is a verified snapshot.
Follow its pre-worker unverified action before the dispatch instructions below.

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
    - A <files_to_read> block listing the story's files_expected + files the diff touches —
      without it the evaluator judges from the diff hunk alone, with no full-file context
    - [Fallback path only] Evaluator agent instructions (from evaluator.md) + forge override
      (from agent-overrides/evaluator-context.md)
  >
)
```

**Dry-run mode**: Skip subagent spawn. Return canned verdict based on mode.

### Step 5a: Post-Evaluator Integrity Check

Run this **immediately after the evaluator returns and BEFORE acting on its verdict** — a verdict
from a subagent that tampered with the working tree must never reach the commit step, pass or
fail:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/forge-integrity.sh check --phase pre-eval --forge-dir .forge --scope full-tree --session-id "$SESSION_ID"
```

This check is mandatory after every evaluator run. Tool restrictions are defense in depth, not integrity evidence.
Apply the shared integrity result contract for the evaluator's post-worker check. Only a verified clean check may reach **Parse evaluator response**.
Follow its unverified and tamper actions; never use the verdict after an unverified or contaminated result.

**Parse evaluator response** (the FULL schema — see `evaluator.md`'s Output Format, the single
authoritative verdict schema). Only reachable after the verified clean check above:
- `verdict: "pass"` →
  - Commit atomically: `git add -A && git commit -m "feat(<story>): <title>"`
  - `story move HP-N done`
  - Sync git if needed
  - Continue to step 5b
- `verdict: "fail"` →
  - Store the COMPACT projection (`{verdict, failures}` — see `evaluator.md`'s "Storage split")
    as a storyhook comment: `story comment HP-N '{"verdict":"fail","failures":[...]}'`
  - Continue to step 5b, then goto retry

### Step 5b: Log Verdict

Append to `.forge/verdicts.jsonl` — this is the durable, uncapped home for the evaluator's FULL
response (see `evaluator.md`'s "Storage split"; only the storyhook comment gets the compact
`{verdict, failures}` projection, not this file):

```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/forge-verdict.sh --story HP-N --attempt <attempt_number> \
  --verdict pass|fail --failures-json '[...]' --verdict-json '<the evaluator's full JSON response>' \
  --forge-dir .forge
```

The script owns the timestamp (ISO-8601, via `jq`'s own clock — never model-fabricated) and the
append. `--verdict-json` is the evaluator's full response verbatim; the script stores it as-is
under `verdict_full`. If only the compact `{verdict, failures}` shape is available (e.g. dry-run
canned responses), omit `--verdict-json` — the script falls back to constructing `verdict_full`
from `--verdict`/`--failures-json` alone.

### Step 6: State Management

```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/forge-loop-state.sh attempt --forge-dir .forge
bash ${CLAUDE_PLUGIN_ROOT}/bin/forge-lock.sh heartbeat --session-id "$SESSION_ID" --forge-dir .forge
```

`attempt` runs once per story that reached evaluation, regardless of pass/fail — it increments
`stories_attempted` and stamps `updated_at`.

If the story reached `done` this iteration:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/forge-loop-state.sh done --forge-dir .forge
```
`stories_this_session` counts unique stories reaching `done`, not total iterations — a story that
retries and eventually passes still only calls `done` once, at the point it actually reaches
`done`. Parse the result:
- `session_limit_hit: false` → continue the loop.
- `session_limit_hit: true` → `write_handoff("Session limit reached ({stories_this_session}
  stories completed)")` → `goto pause`.

```
# Incremental handoff: update .forge/handoffs/handoff-execute.md with this story's outcomes.
# This ensures crash recovery has fresh context even without a clean pause.
# Append to "Stories Completed This Session" section and update "Working Context"
# with any new patterns, micro-decisions, or code landmarks from this story.
write_handoff(incremental=true)
```

### Step 7: Architectural Drift Check

```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/forge-loop-state.sh architect-check --wave-boundary true|false --forge-dir .forge
```

Pass `--wave-boundary true` when the completed story was the last one in its wave, else `false`.
The script persists `stories_since_last_architect_review` in `.forge/state.json` — this is what
makes the trigger reachable under the default `max_stories_per_session: 1` (context clears between
every single story, so an in-memory counter could never accumulate to its own threshold).

Parse the result:
- `trigger: false` → continue the loop (no review this iteration).
- `trigger: true` → run the architect review:

  Resolve subagent_type per `references/team-roles.md`'s "Resolving subagent_type": Preferred:
  `"agents:software-architect"` (there is no "forge:" namespace — forge registers no agents of its
  own; software-architect lives in the agents plugin like every other shared agent). Fallback:
  `"general-purpose"` with `software-architect.md` + `agent-overrides/software-architect-context.md`
  inlined.

  ```
  Agent(
    subagent_type: "agents:software-architect",  # or "general-purpose" + inlined role on fallback
    prompt: <constructed prompt with:
      - [Fallback path only] software-architect.md + agent-overrides/software-architect-context.md
      - Recent commits: <git log of stories completed since last review>
      - DESIGN.md: <relevant sections>
    >
)
  ```

  If the architect reports significant drift → `write_handoff("Architectural drift detected:
  <details>")` → `goto pause`.

**Dry-run mode**: Skip architect review entirely (do not call `architect-check` either — dry runs
have no real story completions to track drift against).

### Retry

`goto retry` — reached from Step 4's failed pre-check and Step 5a's `verdict: "fail"`, and from
nowhere else. Specified in `references/execution-loop-retry.md`: read it at the moment an
attempt actually fails, and follow it completely. A first-attempt pass never reaches it.

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
```

`sessions_completed` is the one counter `forge-step-exit.sh`'s own state.json patch doesn't touch
(it only sets `status`/`updated_at`/`resume`) — increment it first, same atomic read-modify-write
idiom `hooks/session-stop.sh` uses for its own crash-path pause:

```bash
jq '.sessions_completed = ((.sessions_completed // 0) + 1)' .forge/state.json > .forge/state.json.tmp \
  && mv .forge/state.json.tmp .forge/state.json

bash ${CLAUDE_PLUGIN_ROOT}/bin/forge-lock.sh release --session-id "$SESSION_ID" --forge-dir .forge
```

Then run the step-exit script — it commits, sets `status: "paused"` with a `resume` object
(`command`, `handoff_file: "handoffs/handoff-execute.md"`, `summary`), and queues freshen to
`/forge resume` (or reports `fallback_message` if tmux is unavailable — not a fatal error, pause
completes normally either way):

```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/forge-step-exit.sh --step execute \
  --summary "paused — ${STORIES_THIS_SESSION} stories completed. ${REASON}" --next "/forge resume"
```

### Complete

`goto complete` — reached from Step 1 when `story next` reports every story done, and from
nowhere else. Specified in `references/execution-loop-complete.md`: the final test suite, the
project-story close, the storyhook report, the handoff, and the review_validate hand-off, plus
the two notes on what "Complete" does and does not mean (it is *not* the pipeline's terminal
state, and the project story never reaches `done` through this loop). Read it only when Step 1
actually reports all stories done, and follow it completely.

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
