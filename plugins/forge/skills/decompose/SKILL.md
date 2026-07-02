---
name: decompose
description: Decompose PLAN.md into storyhook stories with dependencies, priorities, and design context. Produces plan-mapping.json. Maps waves to stories with embedded DESIGN.md sections.
argument-hint: ""
---

# Decompose: Plan to Stories

You are the decompose skill. Your job is to transform PLAN.md's wave structure into storyhook stories with dependencies, priorities, and embedded design context.

**Read before starting:**
- `references/storyhook-contract.md` — Story CLI command mapping
- `references/story-decomposition.md` — Full decomposition spec

**Read inputs:**
- `.forge/PLAN.md` (required)
- `.forge/DESIGN.md` (required)
- `.forge/handoffs/handoff-plan.md` (if orchestrated — for context)

## Steps

### 1. Idempotency Check

If `.forge/plan-mapping.json` exists:
- Compute MD5 hash of PLAN.md content
- Compare against `plan_hash` in existing mapping
- Use AskUserQuestion:
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

### 2. State Setup

`story init` already seeds `todo` / `in-progress` / `done`. Create the two additional states the
execution loop needs:

```bash
story state add verifying --super OPEN --role active
story state add blocked --super OPEN --role active
```

`story state add` is **not** idempotent — it errors (exit 2, `state \`<slug>\` already exists`) if
the slug already exists, and there is no `story state list` to check first. Tolerate that specific
exit-2 error rather than treating it as a failure. Never hand-edit `.storyhook/states.toml`
directly.

### 3. Extract the Task Breakdown Section

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

### 4. Verify Wave Structure

Verify `$TASKS_FILE` has:
- `### Wave N` headings for sequencing (auto-creates wave dependencies)
- `- [ ]` checkbox items for stories
- Inline `[HIGH]`, `[MEDIUM]`, `[LOW]` markers for priority (optional)

If the wave headings use a different format, normalize them to `### Wave N` first. Error if no
waves or no checkbox items are found.

### 5. Decompose (Single Call)

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
   comment call needed for them).

### 7. Map Stories to DESIGN.md Sections

For each story, find the relevant DESIGN.md section by matching task descriptions to section headers. **Embed the section content** (not just headers) in plan-mapping.json so the execution loop doesn't need to read DESIGN.md later.

### 8. Write plan-mapping.json

Write `.forge/plan-mapping.json` (version-controlled):

```json
{
  "plan_hash": "<md5 of PLAN.md>",
  "project_story": "HP-1",
  "stories": {
    "HP-2": {
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

### 9. Validate DAG

`story graph` is text-only and reports no cycle information for `blocked-by` edges; `story doctor`
only catches parent/child cycles. Do not eyeball `story graph` output for cycles — that judgment
is unreliable from rendered text.

In practice this is low-risk here: the wave `blocked-by` edges created in Step 5 are always
forward (wave N+1 blocked-by wave N), which is acyclic by construction. A cycle can only be
introduced by a manual `story relate` call outside this decompose flow, which this skill doesn't
perform. A general-purpose `blocked-by` cycle validator is a known remaining gap (see
`storyhook-contract.md`'s DAG Validation section) — not implemented as part of this pass.

Report story count and structure to the user.

## Exit

**If `--orchestrated`:** Follow the Step Exit Protocol:
1. Write `.forge/plan-mapping.json`
2. Write `.forge/handoffs/handoff-decompose.md` with:
   - Key Decisions: story count, dependency structure, DAG validation result
   - Context for Next Step: story-to-task mapping summary, wave ordering
   - Open Questions: any ambiguous task boundaries
3. Commit: `git add .forge/ .storyhook/ && git commit -m "forge(decompose): create stories from plan"`
4. Queue freshen: `bash plugins/freshen/bin/freshen.sh queue "/forge execute --orchestrated" --source forge --summary "Decomposition complete — stories created"`
5. STOP

**If standalone:** Write outputs, report story count and structure to user, exit.
