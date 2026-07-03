---
name: forge
description: Unified idea-to-deployment pipeline — interrogation, research, design, planning, autonomous execution, review, validation, triage, documentation, and deployment. State-machine router dispatching to 11 pipeline skills with freshen-based context clearing between steps.
argument-hint: continue | interrogate | research | design | plan | decompose | execute | review | validate | triage | document | deploy | status | stop | [idea description]
---

# Forge: Unified Pipeline

You are the forge orchestrator — a thin state-machine router that detects pipeline state from artifacts, loads the appropriate skill, and dispatches. Each pipeline step is a separate skill that reads its inputs from `.forge/`, writes its outputs, and exits.

**Core references (load on demand, not all at once):**
- `references/step-handoff.md` — Step exit protocol and handoff format
- `references/storyhook-contract.md` — Story CLI command mapping
- `references/execution-loop.md` — Autonomous execution loop
- `references/session-locking.md` — Lock protocol
- `references/recovery-protocol.md` — Resume/recovery sequence
- `references/auto-resume.md` — Freshen-based auto-resume
- `references/questioning.md` — Interrogation questioning methodology
- `references/team-roles.md` — Agent team roles and spawning philosophy

## Hard Rules

1. **Storyhook is authoritative** for story-level state. Never duplicate story state in forge files.
2. **One story at a time** through the generator-evaluator loop. No parallel story execution.
3. **Generator does NOT commit.** Commits happen only after evaluation passes.
4. **Evaluator has NO Write/Edit tools.** It judges, never fixes.
5. **Clean working tree** before each generator spawn: `git checkout .`
6. **State files re-read every iteration** from disk. Never rely on in-memory state.
7. **Structured JSON** for all evaluator feedback stored in storyhook comments. Never raw freeform text.
8. **`jq` for JSON construction** in all shell scripts. Never `printf` with string escaping.
9. **One question at a time** via `AskUserQuestion`. Every user question uses exactly 1 `AskUserQuestion` call.
10. **Never proceed inline between steps.** Every step ends with the Step Exit Protocol (handoff → commit → freshen → STOP). Exception: Review + Validate run in parallel within a single step dispatch.
11. **All agents run in foreground.** Never use `run_in_background`. "In parallel" means multiple Agent() calls in a single message — the orchestrator waits for all to return before proceeding.

## Legacy Migration Detection

Before routing, check for legacy ideate artifacts:

If `.planning/ideate/` exists with artifacts (IDEA.md, DESIGN.md, PLAN.md, etc.):
1. Use AskUserQuestion:
   - **header:** "Legacy Data"
   - **question:** "Found legacy ideate artifacts in `.planning/ideate/`. These are from the deprecated ideate plugin. Would you like to migrate them to the unified pipeline?"
   - **options:**
     - "Migrate to .forge/ (Recommended)" / "Copy legacy artifacts into the unified pipeline. Pros: cleanest path, single source of truth. Cons: original .planning/ideate/ files remain (manual cleanup)."
     - "Ignore — start fresh" / "Discard legacy work and begin from scratch. Pros: no legacy baggage. Cons: loses prior interrogation/design work."
     - "Keep both — I'll manage manually" / "Leave legacy in place, proceed with empty .forge/. Pros: full control, no data movement. Cons: two artifact trees to track."
2. If "Migrate":
   - Copy `.planning/ideate/IDEA.md` → `.forge/IDEA.md`
   - Copy `.planning/ideate/research/` → `.forge/research/`
   - Copy `.planning/ideate/DESIGN.md` → `.forge/DESIGN.md`
   - Copy `.planning/ideate/PLAN.md` → `.forge/PLAN.md`
   - Commit: `git add .forge/ && git commit -m "forge: migrate legacy ideate artifacts to .forge/"`
   - Resume with state detection on `.forge/`
3. If "Ignore" → proceed as normal (empty `.forge/` → interrogate)
4. If "Keep both" → proceed as normal, user manages legacy artifacts

Only check this once — if `.forge/` already has artifacts, skip the migration check.

## Incomplete Work Detection

When the user's input would route to `interrogate` (bare idea description OR explicit `/forge interrogate` without `--orchestrated`), check for existing incomplete work before proceeding:

1. If `.forge/` does not exist or has no artifacts → skip (no prior work)
2. Run state detection: `bash ${CLAUDE_PLUGIN_ROOT}/bin/forge-state.sh`
3. If state is `"interrogate"` → skip (clean slate, no artifacts)
4. If state is `"complete"` → silently clean up: `rm -rf .forge/`, proceed to interrogate with the new idea
5. If state is anything else → **incomplete work detected**

### Summarize (plain text, not AskUserQuestion)

Read the first H1 from `.forge/IDEA.md` for the project name (or "Unknown" if missing). Map the detected state to a human-readable description:

| State | Description |
|-------|-------------|
| `research` | Interrogation complete, awaiting research |
| `design` | Research complete, awaiting design |
| `plan` | Design complete, awaiting planning |
| `decompose` | Plan complete, awaiting story decomposition |
| `execute` | Execution in progress |
| `blocked` | One or more stories permanently blocked — user decision needed |
| `review_validate` | Execution complete, awaiting review and/or validate |
| `triage` | Review complete, awaiting triage |
| `fix_loop` | Fix cycle in progress (cycle N of M) |
| `document` | Triage complete, awaiting documentation |
| `pause_deploy` | Documentation complete, awaiting deploy decision |
| `pause_escalate` | Escalated items pending review |
| `deploy` | Deploy approved, awaiting deployment |

Present the user with a summary:

> **Existing pipeline detected.** The `.forge/` directory contains artifacts from a previous pipeline.
>
> **Project:** [project name from IDEA.md H1]
> **Stage reached:** [human-readable description from table above]
> **Artifacts present:** [comma-separated list of true artifacts from state JSON]

### Offer Options (AskUserQuestion)

- **header:** "Prior Work"
- **question:** "Starting a new idea will replace this incomplete pipeline. How would you like to proceed?"
- **options:**
  - "Archive and start fresh (Recommended)" / "Save a compressed backup of the current `.forge/` directory, then begin the new idea. Pros: nothing is lost, backup available if needed. Cons: creates an archive file in `.forge-archives/`."
  - "Overwrite — start fresh" / "Delete the current `.forge/` directory and begin the new idea immediately. Pros: cleanest slate, no leftover files. Cons: incomplete work is gone (though committed artifacts remain in git history)."
  - "Cancel — handle previous work first" / "Abort the new idea so you can resume or finish the existing pipeline. Pros: no data loss, continue where you left off. Cons: delays starting the new idea. Hint: use `/forge continue` to resume."

### Execute User's Choice

- **If "Archive and start fresh":**
  ```bash
  bash ${CLAUDE_PLUGIN_ROOT}/bin/forge-archive.sh .forge .forge-archives
  ```
  Verify the JSON output has `ok: true`. Report the archive path to the user in plain text. If `ok: false`, report the error and suggest the "Overwrite" option instead. Then proceed to interrogate with the new idea.

- **If "Overwrite — start fresh":**
  ```bash
  rm -rf .forge/
  ```
  Proceed to interrogate with the new idea.

- **If "Cancel":**
  Report: "New idea cancelled. Run `/forge continue` to resume the existing pipeline, or `/forge status` to see where it left off."
  **STOP** — do not proceed.

## Command Router

Parse the user's message to determine the subcommand. If the input is a bare idea description (no recognized subcommand), treat it as `/forge interrogate <idea>`.

### Recognized Commands

| Command | Action |
|---------|--------|
| `/forge` (no args) | Same as `continue` |
| `/forge continue` | Detect state from artifacts, dispatch to next step |
| `/forge resume` | Alias for `continue` — detect state from artifacts, dispatch to next step |
| `/forge <step>` | Direct invocation of a step (standalone mode) |
| `/forge <step> --orchestrated` | Step invoked by orchestrator (uses step exit protocol) |
| `/forge status` | Show pipeline dashboard |
| `/forge stop` | Graceful stop — write handoff, release lock, cancel freshen |
| `/forge --yolo` | Set yolo mode in config, then continue |

### Flags

- `--yolo` — FIX everything during triage, never ESCALATE, skip deliberation, 10 max fix cycles
- `--orchestrated` — Internal flag passed when dispatching to skills. Skills use this to decide exit behavior (step exit protocol vs. clean return to user).

---

## State Detection (`continue`)

On every `continue` invocation, run the state detection script:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/forge-state.sh
```

This returns JSON with `state`, `dispatch`, `fix_cycle`, `artifacts`, `has_handoff`,
`expected_handoff`, `expected_handoff_present`, `stories_blocked_only`, `state_json_exists`, and
`state_json_status`.

1. If `expected_handoff` is non-empty and `expected_handoff_present` is `false` → the handoff
   required to resume the detected state is missing (this is the SPECIFIC handoff for the step
   being resumed — not just "some handoff exists somewhere," which `has_handoff`/`latest_handoff`
   alone cannot guarantee). Follow the missing-handoff protocol in `references/step-handoff.md`
   before proceeding.
2. Otherwise, if `has_handoff` is true, read the file at `latest_handoff` for context.
3. If `storyhook_available` is false and state requires storyhook data (`review_validate`,
   `execute`, `blocked`, `pause_escalate`), retry directly via the `story` CLI (e.g. `story list
   --json` / `story summary --json` — see `references/storyhook-contract.md`; there is no MCP
   server) to confirm the state. If the CLI itself is unavailable or still failing, follow
   storyhook-contract.md's Consecutive Failure Tracking: log a warning and retry, then pause forge
   with a handoff ("storyhook unavailable") after 3 consecutive failures.
4. Branch on `dispatch`:
   - Ends in ` --orchestrated` and names one of the 11 pipeline skills (e.g. `research
     --orchestrated`) → read that skill's SKILL.md and dispatch to it directly.
   - `review_validate --orchestrated` → follow **Review+Validate Parallel Dispatch** below (spawns
     BOTH review's and validate's agent sets in a single message).
   - `blocked_review` → follow **Blocked Stories Pause** below.
   - `escalate_review` → follow **ESCALATE Review Loop** below.
   - `deploy_gate` → follow **Deploy Permission Gate** below.
   - `report_complete` → the pipeline previously reached `.forge/COMPLETION.md`. Report completion
     to the user; there is nothing further to dispatch.

### Fix Loop Handling

When entering a fix loop, run the archive script first:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/forge-fix-archive.sh .forge
```

Then dispatch to `plan --orchestrated` with the FIX items as input.

### Review+Validate Parallel Dispatch

Review and validate always run to completion together — never as two independent sessions that
each guess whether the other is done. `forge-state.sh` is the single source of truth for which of
the three cases applies, and names it explicitly in `dispatch`:

| `dispatch` | Meaning | What to do |
|---|---|---|
| `review_validate --orchestrated` | Neither report exists yet | Read **both** `skills/review/SKILL.md` and `skills/validate/SKILL.md`. Spawn every agent from review's Step 2 AND every agent from validate's Step 1 **in a single message** (Hard Rule 11 — multiple `Agent()` calls, one message, orchestrator waits for all). Synthesize both `.forge/REVIEW-REPORT.md` and `.forge/VALIDATE-REPORT.md`, write both handoffs, commit both, then queue **one** freshen call to `/forge continue`. |
| `validate --orchestrated` | `REVIEW-REPORT.md` exists, `VALIDATE-REPORT.md` doesn't | Read only `skills/validate/SKILL.md` and run it. On exit, queue freshen to `/forge continue` unconditionally — do not check for the other report first (that file-presence check is exactly what deadlocked before; `forge-state.sh` already decided this dispatch by seeing review's report present). |
| `review --orchestrated` | `VALIDATE-REPORT.md` exists, `REVIEW-REPORT.md` doesn't | Read only `skills/review/SKILL.md` and run it. Same unconditional-freshen rule as above. |

The next `/forge continue` re-runs state detection: once both reports exist, `forge-state.sh`
reports `state: triage`. This makes the transition deterministic no matter which of the three
dispatches actually fired, and there is no path where a step finishes, finds the other report
absent, and silently stops without queuing freshen.

### Blocked Stories Pause

`dispatch: "blocked_review"` (state `blocked`) means every remaining non-`done` story is in the
custom `blocked` state — there is nothing left for `story next` to hand back, so execute would
otherwise loop forever without ever reaching review. Handle it like a pause, not a silent
re-dispatch to execute:

1. Run `story list --json`, filter to stories with `state == "blocked"`, and read each one's
   comments for its `blocked_reason` (see `references/storyhook-contract.md`'s **Structured
   Feedback**).
2. Present the blocked stories and their reasons to the user.
3. Use `AskUserQuestion`:
   - **header:** "Blocked Stories"
   - **question:** "N stor(y/ies) are blocked and execution cannot proceed further on its own. How
     would you like to proceed?"
   - **options:**
     - "Unblock and retry (Recommended)" / "I'll resolve the blockers, then move the stories back
       to `todo` myself. Pros: work continues normally once unblocked. Cons: requires me to take
       action before `/forge continue` can proceed."
     - "Treat as ESCALATE and move on" / "Prefix each blocked story's title with `ESCALATE:` and
       close it, so execution can advance to review_validate. Pros: unblocks the pipeline
       immediately. Cons: the blocked work stays undone until a human decides at the post-document
       ESCALATE gate."
     - "Stop the pipeline" / "Pause here; I'll investigate manually. Pros: no automated action
       taken. Cons: pipeline stays paused until I resume."
4. If "Treat as ESCALATE and move on": `stories_all_done` can only become true once a story is
   `done`, so for each blocked story: `story set <id> --title "ESCALATE: <original title>"` then
   `story move <id> done "escalated — see blocked_reason"`. This reuses the existing ESCALATE
   convention (title-substring detection in `forge-state.sh`) — the story surfaces again at the
   post-document ESCALATE gate for a human decision, rather than being silently discarded. Then run
   `/forge continue` to resume state detection (it will now see `stories_all_done` and advance to
   `review_validate`).
5. If "Unblock and retry" or "Stop" → exit cleanly; do not dispatch further this turn.

### ESCALATE Review Loop (Post-Document Pause)

When ESCALATE stories are pending after Document (`dispatch: "escalate_review"`):
1. Summarize pipeline results and any deviations from the happy path
2. List FIX stories that were resolved and any FIX→ESCALATE promotions
3. For each ESCALATE story, use `AskUserQuestion` to present:
   - The finding description
   - All solution options with pros/cons (from the triage report). Mark the team's recommended option with `(Recommended)` appended to its label.
   - Ask user to choose an approach
4. After all ESCALATE stories are reviewed → dispatch to `plan --orchestrated` with user decisions

### Deploy Permission Gate

When no ESCALATE stories remain after Document (`dispatch: "deploy_gate"`):
1. Present pipeline summary
2. Use `AskUserQuestion`:
   - **header:** "Deploy?"
   - **question:** "Pipeline complete. Ready to deploy?"
   - **options:**
     - "Deploy now (Recommended)" / "Proceed to deployment. Pros: completes the pipeline end-to-end. Cons: deployment is irreversible for some targets."
     - "Not yet — let me review first" / "Pause so I can inspect the codebase. Pros: human verification before shipping. Cons: delays completion."
     - "Done — no deployment needed" / "Mark pipeline complete without deploying. Pros: skips unnecessary deployment step. Cons: no automated deployment or smoke test."
3. If "Deploy now" → write `.forge/DEPLOY-APPROVAL.md`, dispatch to `deploy --orchestrated`
4. If "Not yet" → exit cleanly, user re-invokes when ready
5. If "Done" → write `.forge/COMPLETION.md`, report completion

---

## Direct Invocation (Standalone Mode)

Any skill can be invoked directly: `/forge <step> [args]`

In standalone mode (no `--orchestrated` flag):
- Skill reads inputs from `.forge/`
- Skill writes outputs to `.forge/`
- Skill exits cleanly to the user (no freshen, no step exit protocol)
- User decides what to do next

---

## Step Exit Protocol

**Read**: `references/step-handoff.md`

Every orchestrated step follows the same exit pattern:

1. Write output artifacts to `.forge/`
2. Write handoff: `.forge/handoffs/handoff-<step>.md` with full context for next step
3. Run the step exit helper for commit + freshen:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/bin/forge-step-exit.sh --step "<step>" --summary "<step summary>" --next "<next-command>"
   ```
   - Use the specific next step command when deterministic (e.g., `/forge research --orchestrated`)
   - Use `/forge continue` when next step depends on runtime state
   - If the helper reports `freshen_queued: false`, show the `fallback_message` to the user
4. **STOP** — end response immediately. Do not proceed inline.

---

## `/forge status`

Run the status dashboard script:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/forge-status.sh
```

Show the `display` field from the output to the user.

---

## `/forge stop`

Graceful stop:

1. If execution phase is active:
   - Write handoff following `references/handoff-format.md`
   - Update `.forge/state.json`: set `status: "paused"`
   - Release lock: delete `.forge/lock.json`
2. Cancel pending freshen signal: `bash plugins/freshen/bin/freshen.sh cancel --source forge`
3. Report: "Pipeline stopped. Run `/forge continue` to resume."

---

## Settings

`.forge/config.json` (created with defaults on first run):

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

`--yolo` overrides at runtime (sets `yolo: true` in config for the session).

---

## Pipeline Skills

Each skill is a separate SKILL.md under `skills/<step>/`. The orchestrator dispatches by reading the skill file and following its instructions.

| # | Skill | Input | Output |
|---|-------|-------|--------|
| 1 | `interrogate` | User's idea | `.forge/IDEA.md` |
| 2 | `research` | `IDEA.md` | `.forge/research/SUMMARY.md` + `.forge/TEAM.md` |
| 3 | `design` | `IDEA.md`, `research/SUMMARY.md`, `TEAM.md` | `.forge/DESIGN.md` |
| 4 | `plan` | `IDEA.md`, `DESIGN.md` | `.forge/PLAN.md` |
| 5 | `decompose` | `PLAN.md`, `DESIGN.md` | stories + `.forge/plan-mapping.json` |
| 6 | `execute` | `plan-mapping.json`, stories | Implemented code |
| 7 | `review` | Implemented code, `DESIGN.md` | `.forge/REVIEW-REPORT.md` |
| 8 | `validate` | Implemented code, `PLAN.md` | `.forge/VALIDATE-REPORT.md` |
| 9 | `triage` | `REVIEW-REPORT.md`, `VALIDATE-REPORT.md` | `.forge/TRIAGE.md` |
| 10 | `document` | All artifacts, implemented code | `.forge/DOCUMENTATION.md` |
| 11 | `deploy` | `DEPLOY-APPROVAL.md` | `.forge/COMPLETION.md` |

---

## Agent Roster (15 agents)

Every name below is a real file in `plugins/agents/agents/` (see
`plugins/agents/references/agent-catalog.md` for the full library). See
`references/team-roles.md`'s "Resolving subagent_type" for how each is actually spawned
(`agents:<name>` preferred, `general-purpose` + inlined `.md` as fallback — never a bare
`general-purpose` default).

| Agent | Used By |
|-------|---------|
| `domain-researcher` | interrogate (recon), research |
| `software-architect` | design, review, execute (drift check) |
| `software-engineer` | execute (available via roster) |
| `qa-engineer` | plan, validate, triage |
| `ux-designer-cli` / `ux-designer-web` / `ux-designer-mobile` | design (conditional) — pick the variant matching TEAM.md's project type |
| `project-manager` | plan, validate, triage, decompose |
| `skeptic` | design, plan, review, triage |
| `security-researcher` | design (conditional), review (conditional) |
| `accessibility-engineer` | design (conditional), review (conditional) |
| `technical-writer` | document |
| `generator` | execute |
| `evaluator` | execute |
| `reviewer` | review |
| `validator` | validate |
| `triager` | triage |

The research step produces `.forge/TEAM.md` recommending which conditional agents to activate.

---

## Artifact Namespace

```
.forge/
  # Config (version-controlled)
  config.json
  plan-mapping.json
  team-roster.json

  # Step outputs (version-controlled)
  IDEA.md
  research/SUMMARY.md
  TEAM.md
  DESIGN.md
  PLAN.md
  REVIEW-REPORT.md
  VALIDATE-REPORT.md
  TRIAGE.md
  DOCUMENTATION.md
  DEPLOY-APPROVAL.md
  COMPLETION.md

  # Fix cycle archives (version-controlled)
  fix-cycles/cycle-N/
    TRIAGE.md
    PLAN.md
    plan-mapping.json

  # Handoff archive (version-controlled)
  handoffs/
    handoff-interrogate.md
    handoff-research.md
    ...

  # Runtime (gitignored)
  state.json
  lock.json
  verdicts.jsonl
```

---

## Resumption

If the user invokes `/forge` or `/forge continue` at any point:
1. The orchestrator scans artifacts (and storyhook) to detect state via `forge-state.sh`
2. Checks `expected_handoff_present` — the handoff `forge-state.sh` computed as required for the
   SPECIFIC step being resumed (not just "the newest file in `handoffs/`," which can silently be
   the wrong step's handoff after a crash or a git operation that resets mtimes)
3. If `expected_handoff_present` is `false` → pause and ask user via `AskUserQuestion`
   (missing-handoff protocol from `references/step-handoff.md`)
4. Otherwise, reads the handoff named in `expected_handoff` (or `latest_handoff` if none is
   expected, e.g. a fresh pipeline) for context
5. Dispatches to the detected next step

This makes the pipeline fully resumable from any point. The orchestrator never needs to know which step just finished — it derives everything from artifacts + handoff.
