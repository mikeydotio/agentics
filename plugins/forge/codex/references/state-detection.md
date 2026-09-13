# State Detection and Dispatch

**Dispatch/recovery prerequisite:** read `<plugin-root>/references/delivery.md`; the helper owns finite
collection, pending evidence and cleanup. Handle delivery_recovery before continuing.

How `$forge:forge continue` decides which step runs next, and the five non-pass-through cases that need
handling in the router rather than a step skill.

Loaded by `<plugin-root>/codex/skills/forge/SKILL.md` on every `continue`. The `state` → branch mapping here is the
router's whole job; everything else it does is bookkeeping.

## Contents

- State detection call and its JSON contract
- Branch order (`state` before `dispatch` — load-bearing)
- Fix Loop Handling
- Review+Validate Parallel Dispatch
- Blocked Stories Pause
- ESCALATE Review Loop (post-document pause)
- Deploy Permission Gate

On every `continue` invocation, run the state detection script:

```bash
bash "<plugin-root>/bin/forge-state.sh" --record-transition
```

This returns JSON with `state`, `dispatch`, `category`, `auto_advance`, `transition_id`,
`fix_cycle`, `artifacts`, `has_handoff`, `expected_handoff`, `expected_handoff_present`,
`stories_blocked_only`, `state_json_exists`, and `state_json_status`.

`category`/`auto_advance` (agentics#33) are the same classification this section's branch order
already encodes (pass_through / fix_loop / blocked_review / escalate_review / deploy_gate /
report_complete) — pure telemetry today, not something to branch on; continue following `state`
then `dispatch` exactly as below. `--record-transition` appends a `predicted` line to
`.freshen/transitions.log` (best-effort, never fails this call) so the classification and the step
that actually ran can later be measured against each other. Carry `transition_id` forward in this
turn's context: whichever step this dispatches to must pass it as `--transition-id` to its
`forge-step-exit.sh` call (see `<plugin-root>/codex/references/step-handoff.md`'s Step Exit Protocol) so the two lines
correlate. If this state detection call is skipped (e.g. `state` was already known from context and
`continue` wasn't re-run), there is no `transition_id` to thread through — omit
`--transition-id` from that step's exit call rather than inventing one.

1. If `expected_handoff` is non-empty and `expected_handoff_present` is `false` → the handoff
   required to resume the detected state is missing (this is the SPECIFIC handoff for the step
   being resumed — not just "some handoff exists somewhere," which `has_handoff`/`latest_handoff`
   alone cannot guarantee). Follow the missing-handoff protocol in `<plugin-root>/codex/references/step-handoff.md`
   before proceeding.
2. Otherwise, if `has_handoff` is true, read the file at `latest_handoff` for context.
3. If `storyhook_available` is false and state requires storyhook data (`review_validate`,
   `execute`, `blocked`, `pause_escalate`), retry directly via the `story` CLI (e.g. `story list
   --json` / `story summary --json` — see `<plugin-root>/references/storyhook-contract.md`; there is no MCP
   server) to confirm the state. If the CLI itself is unavailable or still failing, follow
   storyhook-contract.md's Consecutive Failure Tracking: log a warning and retry, then pause forge
   with a handoff ("storyhook unavailable") after 3 consecutive failures.
4. Branch on **`state` first, then `dispatch`** — check `state` before falling through to the
   generic `--orchestrated` bullet below. This ordering is load-bearing, not stylistic:
   `fix_loop`'s `dispatch` value is the literal string `"plan --orchestrated"` — byte-for-byte
   identical to a genuine first-time transition into `plan` from `design`. `dispatch` alone cannot
   tell those two cases apart; only `state` can. Checking the generic bullet first would route a
   fix-loop re-entry straight to `plan --orchestrated` and silently skip **Fix Loop Handling**
   below (and, with it, `forge-fix-archive.sh` — the ONLY thing that increments the fix-cycle
   counter). There is no dispatch-only shortcut here — always check `state ==
   "fix_loop"` before anything else:
   - `state == "fix_loop"` → follow **Fix Loop Handling** below. Do NOT fall through to the
     generic bullet just because `dispatch` also happens to end in ` --orchestrated`.
   - `review_validate --orchestrated` → follow **Review+Validate Parallel Dispatch** below (spawns
     BOTH review's and validate's agent sets in bounded delivery waves).
   - `blocked_review` → follow **Blocked Stories Pause** below.
   - `escalate_review` → follow **ESCALATE Review Loop** below.
   - `deploy_gate` → follow **Deploy Permission Gate** below.
   - `report_complete` → the pipeline previously reached `.forge/COMPLETION.md`. Report completion
     to the user; there is nothing further to dispatch.
   - Otherwise, `dispatch` ends in ` --orchestrated` and names one of the 11 pipeline skills (e.g.
     `research --orchestrated`) → read that skill's SKILL.md and dispatch to it directly.

## Fix Loop Handling

`state == "fix_loop"` is the ONLY entry point that may run `plan --orchestrated` with FIX items as
input — never dispatch to `plan` for this case any other way (see the ordering note above). The
archive-and-increment step is mandatory and unconditional, not a suggestion to run "when
convenient": it is the sole mechanism that advances the fix-cycle counter `forge-state.sh` gates
`max_fix_cycles`/`max_fix_cycles_yolo` against, so skipping it defeats the runaway-fix-loop
safeguard entirely.

```bash
bash "<plugin-root>/bin/forge-fix-archive.sh" .forge
```

Verify the JSON output has `ok: true` before proceeding — if `ok: false` (see the script's
`error` field, e.g. `nothing_to_archive`), stop and investigate rather than dispatching to `plan`
with a counter that did not actually advance.

Only after the archive call returns `ok: true`: dispatch to `plan --orchestrated` with the FIX
items as input.

## Review+Validate Parallel Dispatch

Review and validate always run to completion together — never as two independent sessions that
each guess whether the other is done. `forge-state.sh` is the single source of truth for which of
the three cases applies, and names it explicitly in `dispatch`:

| `dispatch` | Meaning | What to do |
|---|---|---|
| `review_validate --orchestrated` | Neither report exists yet | Read **both** `<plugin-root>/codex/skills/review/SKILL.md` and `<plugin-root>/codex/skills/validate/SKILL.md`. Spawn every agent from review's Step 2 AND every agent from validate's Step 1 **through native dispatch within available concurrency slots**, collecting all results before proceeding. Synthesize both `.forge/REVIEW-REPORT.md` and `.forge/VALIDATE-REPORT.md`, write both handoffs, commit both, then queue **one** freshen call to `$forge:forge continue`. |
| `validate --orchestrated` | `REVIEW-REPORT.md` exists, `VALIDATE-REPORT.md` doesn't | Read only `<plugin-root>/codex/skills/validate/SKILL.md` and run it. On exit, queue freshen to `$forge:forge continue` unconditionally — do not check for the other report first (that file-presence check is exactly what deadlocked before; `forge-state.sh` already decided this dispatch by seeing review's report present). |
| `review --orchestrated` | `VALIDATE-REPORT.md` exists, `REVIEW-REPORT.md` doesn't | Read only `<plugin-root>/codex/skills/review/SKILL.md` and run it. Same unconditional-freshen rule as above. |

The next `$forge:forge continue` re-runs state detection: once both reports exist, `forge-state.sh`
reports `state: triage`. This makes the transition deterministic no matter which of the three
dispatches actually fired, and there is no path where a step finishes, finds the other report
absent, and silently stops without queuing freshen.

## Blocked Stories Pause

`dispatch: "blocked_review"` (state `blocked`) means every remaining non-`done` story is in the
custom `blocked` state — there is nothing left for `story next` to hand back, so execute would
otherwise loop forever without ever reaching review. Handle it like a pause, not a silent
re-dispatch to execute:

1. Run `story list --json`, filter to stories with `state == "blocked"`, and read each one's
   comments for its `blocked_reason` (see `<plugin-root>/references/storyhook-contract.md`'s **Structured
   Feedback**).
2. Present the blocked stories and their reasons to the user.
3. Use `the native question tool`:
   - **header:** "Blocked Stories"
   - **question:** "N stor(y/ies) are blocked and execution cannot proceed further on its own. How
     would you like to proceed?"
   - **options:**
     - "Unblock and retry (Recommended)" / "I'll resolve the blockers, then move the stories back
       to `todo` myself. Pros: work continues normally once unblocked. Cons: requires me to take
       action before `$forge:forge continue` can proceed."
     - "Treat as ESCALATE and move on" / "Prefix each blocked story's title with `ESCALATE:` and
       close it, so execution can advance to review_validate. Pros: unblocks the pipeline
       immediately. Cons: the blocked work stays undone until a human decides at the post-document
       ESCALATE gate."
     - "Stop the pipeline" / "Pause here; I'll investigate manually. Pros: no automated action
       taken. Cons: pipeline stays paused until I resume."
4. If "Treat as ESCALATE and move on": `stories_all_done` can only become true once a story is
   `done`, so for each blocked story: `story set <id> --title "ESCALATE: <original title>" --type
   escalate` then `story move <id> done "escalated — see blocked_reason"`. `--type escalate` sets
   the structured `story_type` field `forge-state.sh` actually detects (not a title
   substring; the `ESCALATE:` prefix is kept only for human readability) — the story surfaces
   again at the post-document ESCALATE gate for a human decision, rather than being silently
   discarded. Then run `$forge:forge continue` to resume state detection (it will now see
   `stories_all_done` and advance to `review_validate`).
5. If "Unblock and retry" or "Stop" → exit cleanly; do not dispatch further this turn.

## ESCALATE Review Loop (Post-Document Pause)

When ESCALATE stories are pending after Document (`dispatch: "escalate_review"`):
1. Summarize pipeline results and any deviations from the happy path
2. List FIX stories that were resolved and any FIX→ESCALATE promotions
3. For each ESCALATE story, use `the native question tool` to present:
   - The finding description
   - All solution options with pros/cons (from the triage report). Mark the team's recommended option with `(Recommended)` appended to its label.
   - Ask user to choose an approach
4. After all ESCALATE stories are reviewed → dispatch to `plan --orchestrated` with user decisions

## Deploy Permission Gate

When no ESCALATE stories remain after Document (`dispatch: "deploy_gate"`):
1. Present pipeline summary
2. Use `the native question tool`:
   - **header:** "Deploy?"
   - **question:** "Pipeline complete. Ready to deploy?"
   - **options:**
     - "Deploy now (Recommended)" / "Proceed to deployment. Pros: completes the pipeline end-to-end. Cons: deployment is irreversible for some targets."
     - "Not yet — let me review first" / "Pause so I can inspect the codebase. Pros: human verification before shipping. Cons: delays completion."
     - "Done — no deployment needed" / "Mark pipeline complete without deploying. Pros: skips unnecessary deployment step. Cons: no automated deployment or smoke test."
3. If "Deploy now" → write `.forge/DEPLOY-APPROVAL.md`, dispatch to `deploy --orchestrated`
4. If "Not yet" → exit cleanly, user re-invokes when ready
5. If "Done" → write `.forge/COMPLETION.md`, report completion
