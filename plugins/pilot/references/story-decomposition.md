# Story Decomposition

How PLAN.md wave structure maps to storyhook stories with dependencies, priorities, and acceptance criteria.

## Process

### 1. Idempotency Check

Before creating stories, check if `.pilot/plan-mapping.json` exists:

- **If exists**: Compute MD5 hash of PLAN.md and compare against `plan_hash` in the mapping
  - **Hash matches**: Offer three options via AskUserQuestion:
    - "Continue with existing mapping" — resume from where we left off
    - "Recreate stories (destructive)" — delete existing stories, create fresh
    - "Cancel" — abort
  - **Hash differs**: PLAN.md has changed since last decomposition. Warn user and offer same three options.
- **If not exists**: Proceed with fresh decomposition

### 2. State Setup

Ensure required storyhook states exist (idempotent):
- Check `.storyhook/states.toml` for `in-progress`, `verifying`, `blocked`
- If missing, append them (same logic as `/pilot init`)

### 3. Create Parent Story

```bash
story new "[Project Name] — Work Execution"
```

Record the returned ID as `project_story` in plan-mapping.json.

### 4. Decompose via MCP (Preferred — Single Call)

The PLAN.md markdown format matches what `storyhook_decompose_spec` expects:
- `### Wave N` headings → automatic wave dependency creation (later waves blocked-by earlier waves)
- `- [ ]` checkbox items → individual stories
- Inline `[HIGH]`, `[MEDIUM]`, `[LOW]` markers → priority assignment
- `#label` → label assignment

**Steps:**

1. **Preview**: Call `storyhook_decompose_spec(content: <PLAN.md>, dry_run: true)` to see what will be created
2. **Create**: Call `storyhook_decompose_spec(content: <PLAN.md>, dry_run: false)` to create all stories
3. **Record IDs**: Map returned story IDs to task references for plan-mapping.json

This replaces what was previously 60-80+ sequential CLI calls with a single MCP tool call. The MCP tool handles:
- Story creation with titles
- Wave dependency wiring (stories in wave N+1 are blocked-by stories in wave N)
- Priority assignment from inline markers
- Label assignment from inline markers

### 5. Add Acceptance Criteria

After decomposition, add acceptance criteria as comments on each story:

```
storyhook_add_comment(id: "HP-N", body: "Acceptance: Config loads from YAML and returns typed object")
```

Or via CLI: `story HP-N "Acceptance: <criteria>"`

### CLI Fallback (If MCP Unavailable)

If MCP tools are unavailable, fall back to sequential CLI creation:

```
For each wave:
  For each task in wave:
    story new "<task title>"
    → record returned story ID
    story HP-X priority <level>  (wave 1=high, 2=medium, 3+=low)
    story HP-X "Acceptance: <criteria>"

For each task T in wave N and each task U in wave N+1:
  story HP-T precedes HP-U
```

This is significantly slower (N×3 calls + M dependency calls vs. 1 MCP call) but functionally equivalent.

### 8. Map Stories to DESIGN.md

For each story, identify the relevant DESIGN.md section by matching task descriptions to section headers. **Embed the section content** (not just headers) in plan-mapping.json so the execution loop doesn't depend on reading DESIGN.md later.

### 9. Write plan-mapping.json

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
      "design_section": "## Config Module\nLoads YAML config from disk. Returns a typed configuration object.",
      "files_expected": ["src/config.ts"]
    },
    "HP-3": {
      "task_ref": "Task 1.2",
      "wave": 1,
      "title": "Create logger module",
      "acceptance_criteria": "Logger writes structured JSON to stdout",
      "design_section": "## Logger Module\nStructured JSON logger. Writes to stdout.",
      "files_expected": ["src/logger.ts"]
    }
  }
}
```

### 10. Validate DAG

After creating all stories and relationships:

```bash
story graph
```

Inspect the output for cycles. If cycles are detected:
1. Report the cycle path(s) to the user
2. Abort — do not proceed with `/pilot run` on a cyclic plan

## Offline Constraint

`.pilot/` artifacts (PLAN.md, DESIGN.md) must exist locally. During decomposition, `plan-mapping.json` embeds the relevant DESIGN.md section content, so the execution loop does not depend on reading PLAN.md or DESIGN.md after decomposition.
