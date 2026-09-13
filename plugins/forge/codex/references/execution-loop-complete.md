# Execution Loop: Complete

The `goto complete` target of the loop in `<plugin-root>/codex/references/execution-loop.md`, reached from Step 1
when `story next` reports every story done. AUTHORITATIVE for the completion path exactly as
`execution-loop.md` is for Prerequisites and Steps 0–7 — follow it completely.

Loaded only when Step 1 actually reports all stories done. That happens once per pipeline run,
not once per session, so it is not part of the per-story entry cost.

Covers: what "Complete" does and does not mean (it is not the pipeline's terminal state — deploy
owns `COMPLETION.md`), why the synthetic project story never reaches `done` through this loop,
the final test suite and its failure branch, the best-effort project-story close, the storyhook
report, the handoff, and the step-exit that hands off to review_validate.

### Complete

**IMPORTANT:** "Complete" here means *all stories are done*, not *the pipeline is done*.
Execution must hand off to review_validate — it must NOT write `.forge/COMPLETION.md` and must NOT
cancel the freshen signal. `COMPLETION.md` is the pipeline's terminal artifact; it is owned
exclusively by the deploy step (`<plugin-root>/codex/skills/deploy/SKILL.md`) and the "no deployment needed" branch of
the Deploy Permission Gate (`<plugin-root>/codex/skills/forge/SKILL.md`). Writing it here would make `forge-state.sh`'s
very first check (`artifact_exists "COMPLETION.md"` → `state: complete`) treat the pipeline as
fully finished, silently skipping review, validate, triage, document, and deploy.

**The project story.** decompose auto-created a synthetic "project story" from PLAN.md's
`## Task Breakdown` heading (`plan-mapping.json`'s `project_story` — see
`<plugin-root>/codex/references/story-decomposition.md`). storyhook's `story next` permanently refuses to ever hand
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
bash "<plugin-root>/bin/forge-lock.sh" release --session-id "$SESSION_ID" --forge-dir .forge
```

```
    # Do NOT remove auto-resume trigger
    Log: "Final test suite failed — manual review required. See handoffs/handoff-execute.md."
    return

  # 2. Close the project story (hygiene only -- see "The project story" above;
  #    best-effort, never a precondition for anything below).
  bash "<plugin-root>/bin/forge-close-project-story.sh" .
  # Ignore `.ok`/`.reason` beyond logging: `no_plan_mapping`, `story_cli_missing`,
  # etc. are all fine to silently continue past. `.closed` is informational
  # only -- the close writes to storyhook's own store, which is outside the
  # repository, so item 5's commit has nothing to pick up either way.

  # 3. Storyhook report
  story summary
  story handoff --since <total_duration>

  # 4. Write handoff to .forge/handoffs/handoff-execute.md (NOT COMPLETION.md):
    - Project summary
    - Stories completed with acceptance criteria
    - Test results
    - Notable decisions and patterns
    - Duration and session count

  # 5. Release the lock, then step-exit: commit and queue freshen for the NEXT
  #    step (review_validate) — do NOT cancel. No --extra-path is needed:
  #    storyhook keeps story state outside the repository.
  bash "<plugin-root>/bin/forge-lock.sh" release --session-id "$SESSION_ID" --forge-dir .forge
  bash "<plugin-root>/bin/forge-step-exit.sh" --host codex --step execute \
    --summary "all stories complete" --next '$forge:forge continue'
  # status stays in the same two-value space as every other exit path
  # ("running" while looping, "paused" once the loop has exited for any
  # reason) — forge-step-exit.sh's own patch sets it. There is no third
  # "complete" status — storyhook + forge-state.sh (not state.json) decide
  # the review_validate transition, per Hard Rule 1 ("storyhook is
  # authoritative for story-level state — never duplicate it in forge files").
```
