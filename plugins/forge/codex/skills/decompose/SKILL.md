---
name: decompose
description: Decompose PLAN.md into storyhook stories with dependencies, priorities, and design context. Produces plan-mapping.json. Maps waves to stories with embedded DESIGN.md sections.
---

Resolve `<plugin-root>` three directories above this loaded file's containing directory.
Read `<plugin-root>/codex/references/runtime.md` before this step.

# Decompose: Plan to Stories

You are the decompose skill. Your job is to transform PLAN.md's wave structure into storyhook stories with dependencies, priorities, and embedded design context.

**Read before starting:**
- `<plugin-root>/references/storyhook-contract.md` — Story CLI command mapping
- `<plugin-root>/codex/references/story-decomposition.md` — Full decomposition spec

**Read inputs:**
- `.forge/PLAN.md` (required)
- `.forge/DESIGN.md` (required)
- `.forge/handoffs/handoff-plan.md` (if orchestrated — for context)

## Steps

### 1. Idempotency Check

If `.forge/plan-mapping.json` exists:
- Compute MD5 hash of PLAN.md content
- Compare against `plan_hash` in existing mapping
- Use the native question tool:
  - **header:** "Existing Map"
  - **question:** Hash match/mismatch message + "How would you like to proceed?"
  - **options (hash matches — plan unchanged):**
    - "Continue with existing mapping (Recommended)" / "Resume from where we left off. Pros: no wasted work, preserves story state. Cons: won't pick up manual edits outside PLAN.md."
    - "Recreate stories (destructive)" / "Delete existing stories and create fresh. Pros: clean slate if stories are corrupt. Cons: destroys all story progress and evaluator feedback."
    - "Cancel" / "Abort decomposition. Pros: safe, no side effects. Cons: pipeline stalls until re-invoked."
  - **options (hash differs — plan changed):**
    - "Continue with existing mapping" / "Use old stories despite plan changes. Pros: preserves completed work. Cons: stories may not match the updated plan."
    - "Recreate stories (destructive) (Recommended)" / "Delete old stories and decompose the updated plan. Pros: stories match current plan exactly. Cons: loses all prior story progress."
    - "Cancel" / "Abort and investigate. Pros: safe, lets you review the changes. Cons: pipeline stalls."
- If "Continue" -> skip decomposition, report existing mapping
- If "Recreate" -> proceed with fresh decomposition
- If "Cancel" -> exit

### 2. State and Type Setup

`story project new` already provides `todo`, `in-progress`, `verifying`, `blocked`,
`done` and `dropped`. Do not add those states again: duplicate additions fail.
For an older project missing required states, use `story doctor --fix`, the
supported migration. See `storyhook-contract.md`'s **Custom States** for the
single-active-role constraint.

Also register the `escalate` custom **type** triage and the blocked-stories-pause flow use to flag
a story as needing a human decision (`forge-state.sh` detects pending escalations via the
structured `story_type` field, not a title match). `story_type` values are a fixed,
project-scoped enum (`story new --type <slug>` rejects anything not registered with `story type
add` first — verified against storyhook's built-in default set, `bug`/`chore`/`epic`/`story`/`task`,
which does **not** include `escalate`). Same idempotency caveat as custom states — `story type add`
errors (exit 2, `type \`escalate\` already exists`) on a slug that's already registered; tolerate
that specific error rather than treating it as a failure:

```bash
story type add escalate --description "Needs a human decision (forge triage escalation)"
```

### 3. Extract and Verify the Task Breakdown Section

`story decompose` treats **every** Markdown heading in its input as a story, not just wave
headings — piping the entire PLAN.md would turn `## Test Strategy`, `## Resumption Points`, and
`## Risk Register` into spurious stories alongside the real tasks. Extract just the
`## Task Breakdown` section (from that heading up to, but not including, the next `## ` heading)
into a temp file:

```bash
TASKS_FILE=$(mktemp)
awk '/^## Task Breakdown/{flag=1} /^## / && !/^## Task Breakdown/{if(flag)exit} flag' .forge/PLAN.md > "$TASKS_FILE"
```

Do **not** separately run `story new` to create a parent story: `story decompose` auto-creates
one from the first heading in its input (here, "Task Breakdown"), and calling `story new` first
would leave two disconnected parent stories.

Verify `$TASKS_FILE` has:
- `### Wave N` headings for sequencing (auto-creates wave dependencies)
- `- [ ]` checkbox items for stories
- Inline `[HIGH]`, `[MEDIUM]`, `[LOW]` markers for priority (optional)

If the wave headings use a different format, normalize them to `### Wave N` first. Error if no
waves or no checkbox items are found.

### 4. Decompose (Single Call)

`story decompose` creates the parent story, every task story, and all wave `blocked-by`
dependencies in one call — this replaces what would otherwise be 60-80+ sequential CLI calls:

1. **Preview first**:
   ```bash
   story decompose --stdin --dry-run < "$TASKS_FILE"
   ```
   Verify the preview shows the expected story count, wave structure, and relationships.

2. **Create stories**:
   ```bash
   story decompose --stdin --json < "$TASKS_FILE"
   ```

3. **Record story IDs** from `.stories[].story.id` in the response. The first story returned
   corresponds to the "Task Breakdown" heading — record it as `project_story`. Each subsequent
   story maps to one task; nested `- Acceptance: …` / `- Files: …` bullets under a task's
   checkbox item are captured automatically as that story's first comment (no separate
   comment call needed for them). `project_story` can never reach `done` through the normal
   execution loop (storyhook refuses to hand a story with children back to `story next`) — this
   is expected, not a defect; see `<plugin-root>/codex/references/story-decomposition.md`'s "The project story never
   reaches `done` on its own" for how the pipeline accounts for it.

### 5. Map Stories to DESIGN.md Sections

For each story, find the relevant DESIGN.md section by matching task descriptions to section headers. **Embed the section content** (not just headers) in plan-mapping.json so the execution loop doesn't need to read DESIGN.md later.

### 6. Write plan-mapping.json

Get the mechanical fields — `plan_hash` and a per-story skeleton (real IDs and titles, judgment
fields left null) — from the scaffold script rather than hand-computing an MD5 or re-typing IDs:

```bash
bash "<plugin-root>/bin/forge-mapping-scaffold.sh" --plan .forge/PLAN.md
```

Fill in each story's judgment fields (`task_ref`, `wave`, `acceptance_criteria`, `design_section`
from Step 5, `files_expected`) onto the returned skeleton, then write the result to
`.forge/plan-mapping.json` (version-controlled):

```json
{
  "plan_hash": "<from the scaffold script>",
  "project_story": "<from the scaffold script>",
  "stories": {
    "<STORY_ID>": {
      "task_ref": "Task 1.1",
      "wave": 1,
      "title": "Create config module",
      "acceptance_criteria": "Config loads from YAML file and returns typed object",
      "design_section": "## Config Module\nLoads YAML config from disk...",
      "files_expected": ["src/config.ts"]
    }
  }
}
```

IDs come from the scaffold script's own `story list --json` read — never assume a prefix. (The
default prefix is `SH`, not `HP`; if a project runs `story project new --prefix <X>`, IDs use
`<X>` instead.)

### 7. Validate DAG

Neither `story graph` nor `story doctor` reports `blocked-by` cycles, and eyeballing rendered
`story graph` output for cycles is unreliable — see `storyhook-contract.md`'s **DAG Validation**
section for why. Instead, run the validator script:

```bash
bash "<plugin-root>/bin/forge-dag-validate.sh" .
```

- If `.ok` is `false`, fall back to the Consecutive Failure Tracking flow in
  `storyhook-contract.md`.
- If `.has_cycles` is `true`, **abort**: report the cycle(s) from `.cycles` to the user and do not
  proceed to `execute`.
- If `.has_cycles` is `false`, continue and report story count and structure to the user.

In practice this is low-risk here: the wave `blocked-by` edges created in Step 4 are always
forward (wave N+1 blocked-by wave N), which is acyclic by construction. A cycle can only be
introduced by resuming an existing `plan-mapping.json` (Step 1's "Continue" path) or a manual
`story relate` call outside this decompose flow — the validator catches both.

## Exit

**If `--orchestrated`:** Write `.forge/plan-mapping.json`, then follow the Step Exit Protocol
(`<plugin-root>/codex/references/step-handoff.md`) — write `handoff-decompose.md` (Decompose Handoff table) and run:
```bash
bash "<plugin-root>/bin/forge-step-exit.sh" --host codex --step decompose \
  --summary "create stories from plan" --next '$forge:forge execute --orchestrated'
```
No `--extra-path` is needed: the stories this step just created live in storyhook's own store
outside the repository, so there is no repo path to commit (see `<plugin-root>/codex/references/handoff-format.md`).

**If standalone:** Write outputs, report story count and structure to user, exit.
