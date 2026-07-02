# Recovery Protocol

Resume and recovery sequence for forge — restoring context after session boundaries or crashes.

## Recovery Sequence (`/forge resume`)

### 1. Lock Check

- Check `.forge/lock.json`
- If heartbeat fresh (< `heartbeat_window_minutes`) → exit: "Work is already running"
- If lock exists but heartbeat stale → break lock, log warning
- Acquire new lock
- Clear stale resume context: set `state.resume = null` (prevents prior session's resume metadata from persisting)

### 2. State Read

- Read `.forge/state.json`
- If missing → this is a fresh start from decompose, not a resume (see **Fresh-Start vs. Resume
  Discriminator** below) — this recovery sequence does not apply; follow execute/SKILL.md's Fresh
  Start entry mode instead.
- If present but malformed → report clear error, exit (do not guess)
- `status` is only ever `"running"` or `"paused"` (see `references/execution-loop.md`'s Complete
  block) — there is no `"complete"` status to check here. Whether execution should hand off to
  review_validate is decided by storyhook + `forge-state.sh`, never by state.json alone (Hard Rule
  1: storyhook is authoritative for story-level state).

### 3. Handoff Read (Primary Context Source)

- Read `.forge/handoffs/handoff-execute.md` if it exists
- Extract: patterns established, micro-decisions, code landmarks, test state, blockers, why did we stop
- Feed extracted context into the generator prompt for the next story
- **If `.forge/handoffs/handoff-execute.md` is missing** → pause and ask the user via `AskUserQuestion` (see `references/step-handoff.md` for the missing-handoff protocol — `forge-state.sh`'s `expected_handoff`/`expected_handoff_present` fields name this specific file for the `execute` state). Do NOT silently continue with degraded context.

### 4. Crash Recovery

Query storyhook for stories in inconsistent states:

```bash
story list --json
```

Any story in `in-progress` or `verifying` state indicates a crash mid-work:
- Reset these stories to `todo`: `story move HP-N todo`
- Clean working tree: `git checkout .`

This ensures no partially-completed work contaminates the next attempt.

### 5. Determine Next Action

```bash
story next --json
```

Check what's available:
- Stories available → proceed to execution loop
- No stories, all `done` → follow the Complete path in `references/execution-loop.md` (write
  handoff, commit, queue freshen to `/forge continue`) so the pipeline hands off to review_validate
  — even if state.json said `paused`. Do NOT write `.forge/COMPLETION.md` here (see the note
  in `execution-loop.md`'s Complete section — that artifact is the pipeline's terminal marker,
  owned by deploy).
- No stories, some (but not all) `blocked` and at least one `todo`/`in-progress`/`verifying` →
  proceed to execution loop as normal (there is still actionable work)
- No stories, and every non-`done` story is `blocked` → pause: `forge-state.sh` reports this as
  state `blocked` (`dispatch: "blocked_review"`) — follow `skills/forge/SKILL.md`'s **Blocked
  Stories Pause**, not a generic "user intervention needed" message

### 6. Context Gathering and Validation

Run context gathering and validation as a single step:

```bash
git log --oneline -10
```

Run the project test suite — this simultaneously verifies codebase health AND validates handoff claims:

- If handoff says "tests pass" but tests fail → trust current state, not handoff
- If handoff references files that don't exist → note discrepancy, remove from code landmarks
- If git log shows commits not mentioned in handoff → session crashed mid-story, flag this
- If handoff has a `## WARNING: Incomplete Handoff` section → treat as degraded context, log to verdict history

This step is especially important when the handoff is from a much older session. Trust current disk state over handoff claims when they conflict.

### 7. Decision Point

- If tests fail → stop: user must fix test failures before resuming
- If decision needed (blocked stories requiring user input) → stop
- Otherwise → enter execution loop

## Cross-Layer Inconsistency Detection

If `state.json` says `paused` but all stories are `done`:
- Follow the Complete path (write handoff, commit, queue freshen to `/forge continue`) exactly as
  if the loop had just finished normally — state.json was stale. Do NOT write `.forge/COMPLETION.md`
  (it is the pipeline's terminal artifact, not "this execute session finished").
- This handles the case where a session completed all stories but crashed before updating state.json

## Fresh-Start vs. Resume Discriminator

`execute/SKILL.md` is dispatched identically (`execute --orchestrated`) both for a brand-new
execute step and for every crash/auto-resume — the skill must not guess which one it is:

- **`state_json_exists: false`** (from `forge-state.sh`) → **Fresh Start**: initialize
  `.forge/state.json` from scratch; do NOT run this recovery protocol (there is nothing to
  recover); read `.forge/handoffs/handoff-decompose.md` for context (`forge-state.sh`'s
  `expected_handoff` names this file for a fresh `execute` state).
- **`state_json_exists: true`** → **Resume**: follow this recovery protocol in full, including
  Crash Recovery (step 4). Never re-initialize `state.json` in this case — doing so silently wipes
  `total_retries`/`retry_counts`/`sessions_completed` and defeats the runaway safeguards.

This is a fact read from disk, not an inference from conversation context — see execute/SKILL.md's
Entry Modes.
