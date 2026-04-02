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
- `.pilot/PLAN.md` (required)
- `.pilot/DESIGN.md` (required)
- `.pilot/handoffs/handoff-plan.md` (if orchestrated — for context)

## Steps

### 1. Idempotency Check

If `.pilot/plan-mapping.json` exists:
- Compute MD5 hash of PLAN.md content
- Compare against `plan_hash` in existing mapping
- Use AskUserQuestion:
  - **header:** "Existing Map"
  - **question:** Hash match/mismatch message + "How would you like to proceed?"
  - **options:** ["Continue with existing mapping", "Recreate stories (destructive)", "Cancel"]
- If "Continue" -> skip decomposition, report existing mapping
- If "Recreate" -> proceed with fresh decomposition
- If "Cancel" -> exit

### 2. State Setup

Ensure required storyhook states exist (idempotent):
- Check `.storyhook/states.toml` for `in-progress`, `verifying`, `blocked`
- If missing, append them:
  ```toml
  [in-progress]
  super = "open"
  description = "Generator working on this story"

  [verifying]
  super = "open"
  description = "Evaluator reviewing this story"

  [blocked]
  super = "open"
  description = "Dependency unmet, decision needed, or max retries exhausted"
  ```

### 3. Create Parent Story

```bash
story new "[Project Name] — Work Execution"
```

Record the returned ID as `project_story`.

### 4. Prepare PLAN.md for Decomposition

The PLAN.md already uses the format `storyhook_decompose_spec` expects:
- `### Wave N` headings for sequencing (auto-creates wave dependencies)
- `- [ ]` checkbox items for stories
- Inline `[HIGH]`, `[MEDIUM]`, `[LOW]` markers for priority

Verify the PLAN.md has this structure. If the wave headings use a different format, normalize them to `### Wave N` before passing to decompose_spec.

Error if no waves found or waves are empty.

### 5. Decompose via MCP (Single Call)

Use `storyhook_decompose_spec` to create all stories with wave dependencies and priorities in one call:

1. **Preview first** with `dry_run: true`:
   ```
   storyhook_decompose_spec(content: <PLAN.md content>, dry_run: true)
   ```
   Verify the preview shows the expected story count, wave structure, and relationships.

2. **Create stories**:
   ```
   storyhook_decompose_spec(content: <PLAN.md content>, dry_run: false)
   ```
   This single call replaces what was previously 60-80+ sequential CLI calls.

3. **Record returned story IDs** from the response for plan-mapping.json.

**Fallback**: If `storyhook_decompose_spec` is unavailable, use `storyhook_bulk_create` with pre-constructed relationship arrays. If MCP tools are entirely unavailable, fall back to sequential CLI creation (see `references/story-decomposition.md` for the CLI fallback procedure).

### 7. Map Stories to DESIGN.md Sections

For each story, find the relevant DESIGN.md section by matching task descriptions to section headers. **Embed the section content** (not just headers) in plan-mapping.json so the execution loop doesn't need to read DESIGN.md later.

### 8. Write plan-mapping.json

Write `.pilot/plan-mapping.json` (version-controlled):

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

```bash
story graph
```

If cycles detected -> report cycle path(s) and abort. Do not proceed with execution on a cyclic plan.

If DAG valid -> report story count and structure.

## Exit

**If `--orchestrated`:** Follow the Step Exit Protocol:
1. Write `.pilot/plan-mapping.json`
2. Write `.pilot/handoffs/handoff-decompose.md` with:
   - Key Decisions: story count, dependency structure, DAG validation result
   - Context for Next Step: story-to-task mapping summary, wave ordering
   - Open Questions: any ambiguous task boundaries
3. Commit: `git add .pilot/ .storyhook/ && git commit -m "pilot(decompose): create stories from plan"`
4. Queue freshen: `bash plugins/freshen/bin/freshen.sh queue "/pilot continue" --source pilot`
5. STOP

**If standalone:** Write outputs, report story count and structure to user, exit.
