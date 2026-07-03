# Execution Loop

Complete specification for the autonomous execution loop. The SKILL.md router dispatches here for `/forge run` and `/forge resume`.

Per-iteration bookkeeping (counters, locks, verdicts, integrity checks) is scripted — see
`bin/forge-loop-state.sh`, `bin/forge-lock.sh`, `bin/forge-verdict.sh`, `bin/forge-integrity.sh`,
`bin/forge-predecessor-diff.sh` (WS4). The model calls a script and branches on its returned JSON;
it never hand-edits `.forge/state.json`'s counters, hand-computes lock staleness, or hand-diffs
the working tree. What stays genuine model judgment: constructing agent prompts, writing handoff
*content*, and deciding what a summarized predecessor diff should say when one is too large to
paste verbatim.

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
storyhook-failure streak — F093, F097):

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

Defense-in-depth: verify the generator did not modify forge state files, and (F064) did not commit.

```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/forge-integrity.sh check --phase pre-gen --forge-dir .forge --scope forge-only --session-id "$SESSION_ID"
```

Parse the JSON result:
- `tampered: false` → proceed to Step 4.
- `tampered: true`, `action: "restored"` → the generator modified `.forge/config.json` or
  `.forge/state.json`; the script already restored their exact pre-spawn content (content-hash
  based, correct even for the gitignored `state.json` — F096). Mark story blocked: `story move
  HP-N blocked`; add comment: `story comment HP-N '{"blocked_reason":"integrity","description":"Generator
  modified forge state files"}'`; continue to next iteration.
- `tampered: true`, `head_moved: true`, `action: "manual_review_required"` (F064): the generator
  committed, violating Hard Rule 3. This is more serious than the file-content case above and is
  **NOT** auto-reverted — a `git reset` here risks destroying the commit's forensic trail or
  interacting badly with any concurrent work. Instead: mark story blocked (`story move HP-N
  blocked`); add comment: `story comment HP-N '{"blocked_reason":"integrity","description":"Generator
  committed (HEAD moved from <head_before> to <head_after>) — violates Hard Rule 3. Needs manual
  review before continuing."}'` (use the script's own `head_before`/`head_after` fields); write a
  handoff noting the exact SHAs and pause (do not silently continue the loop past this — treat it
  the same as a runaway-safeguard trip).
- `tampered: true`, `action: "restore_failed"` → the script could not restore forge state files.
  Treat as blocked + pause; this needs manual intervention.

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

**Dry-run mode**: Skip subagent spawn. Return canned verdict based on mode.

### Step 5a: Post-Evaluator Integrity Check

Run this **immediately after the evaluator returns and BEFORE acting on its verdict** — a verdict
from a subagent that tampered with the working tree must never reach the commit step, pass or
fail:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/forge-integrity.sh check --phase pre-eval --forge-dir .forge --scope full-tree --session-id "$SESSION_ID"
```

**With WS3's `agents:evaluator` resolution in place (Step 5 above), this check is
belt-and-suspenders, not the primary enforcement:** when the evaluator resolves to the real
registered `agents:evaluator` type, the platform enforces `evaluator.md`'s `tools: Read, Bash,
Grep, Glob` and the evaluator structurally cannot call Write or Edit — a leaky evaluator "gets
blocked," not just "gets caught after the fact" (closes F057/F058 at the mechanism level for that
path). This check remains necessary for the `general-purpose` fallback path (no platform-level
tool restriction applies there) and as defense-in-depth either way.

Parse the JSON result:
- `tampered: false` → discard nothing; proceed to **Parse evaluator response** below.
- `tampered: true`, `action: "restored"` → the evaluator modified the working tree (content-hash
  based — this catches BOTH an edit to a file the generator already touched AND a brand-new
  untracked file, the two cases a filename-set diff misses; F092/F058). The script already
  restored the exact pre-evaluator content and removed anything newly added. Discard the
  evaluator's verdict entirely (do not act on it, pass or fail). Re-run the evaluator once (spawn
  again, fresh integrity snapshot). If it tampers again → mark story blocked: `story move HP-N
  blocked` with an integrity-violation reason.
- `tampered: true`, `head_moved: true`, `action: "manual_review_required"` → the evaluator
  committed (via Bash — it retains Bash even without Write/Edit). Same reasoning as Step 3a's
  generator case: do NOT auto-revert. Mark story blocked, write a handoff with the exact SHAs, and
  pause.
- `tampered: true`, `action: "restore_failed"` → mark blocked + pause for manual intervention.

**Parse evaluator response** (the FULL schema — see `evaluator.md`'s Output Format, the single
authoritative verdict schema). Only reachable once the integrity check above reports
`tampered: false`:
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
every single story, so an in-memory counter could never accumulate to its own threshold; F098).

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

```bash
retry:
  git checkout .  # discard failed attempt's changes
  bash ${CLAUDE_PLUGIN_ROOT}/bin/forge-loop-state.sh retry --story-id HP-N --forge-dir .forge
```

Parse the result:
- `action: "retry"` →
  ```bash
  story move HP-N todo  # with evaluator/check feedback already in comments
  ```
  continue (back to top of loop)
- `action: "block"` →
  ```bash
  story move HP-N blocked
  story comment HP-N '{"blocked_reason":"max_retries","description":"Failed <max_retries> attempts","last_feedback":{...}}'
  ```
  continue (back to top of loop — will pick next story)

The script owns `retry_counts[story_id]`, `total_retries`, and the retry-vs-block comparison
against `config.max_retries` — no model-run counter arithmetic or JSON edits.

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
```

```bash
jq '.status = "paused" | .pause_reason = "final-test-suite-failed" | .updated_at = (now | todate)' \
  .forge/state.json > .forge/state.json.tmp && mv .forge/state.json.tmp .forge/state.json
bash ${CLAUDE_PLUGIN_ROOT}/bin/forge-lock.sh release --session-id "$SESSION_ID" --forge-dir .forge
```

```
    # Do NOT remove auto-resume trigger
    Log: "Final test suite failed — manual review required. See handoffs/handoff-execute.md."
    return

  # 2. Close the project story (hygiene only -- see "The project story" above;
  #    best-effort, never a precondition for anything below).
  bash ${CLAUDE_PLUGIN_ROOT}/bin/forge-close-project-story.sh .
  # Ignore `.ok`/`.reason` beyond logging: `no_plan_mapping`, `story_cli_missing`,
  # etc. are all fine to silently continue past. Only `.closed == true` means
  # `.storyhook/` actually changed and needs to ride along in item 5's commit
  # below.

  # 3. Storyhook report
  story summary
  story handoff --since <total_duration>

  # 4. Write handoff to .forge/handoffs/handoff-execute.md (NOT COMPLETION.md):
    - Project summary
    - Stories completed with acceptance criteria
    - Test results
    - Notable decisions and patterns
    - Duration and session count

  # 5. Release the lock, then step-exit: commit (include .storyhook/ in case
  #    Step 2 closed the project story) and queue freshen for the NEXT step
  #    (review_validate) — do NOT cancel.
  bash ${CLAUDE_PLUGIN_ROOT}/bin/forge-lock.sh release --session-id "$SESSION_ID" --forge-dir .forge
  bash ${CLAUDE_PLUGIN_ROOT}/bin/forge-step-exit.sh --step execute \
    --summary "all stories complete" --next "/forge continue" --extra-path .storyhook/
  # status stays in the same two-value space as every other exit path
  # ("running" while looping, "paused" once the loop has exited for any
  # reason) — forge-step-exit.sh's own patch sets it. There is no third
  # "complete" status — storyhook + forge-state.sh (not state.json) decide
  # the review_validate transition, per Hard Rule 1 ("storyhook is
  # authoritative for story-level state — never duplicate it in forge files").
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
