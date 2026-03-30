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

### 4. Parse PLAN.md Waves

Extract waves and tasks from PLAN.md markdown structure:

```
### Wave N (...)
- [ ] Task N.M: [title]
  - Acceptance: [criteria]
  - Files: [expected files]
```

For each task:
1. `story new "<task title>"` — create the story
2. Record the returned story ID

### 5. Set Dependencies (Wave Ordering)

Tasks within the same wave are parallel (no dependencies between them).
Tasks in wave N+1 depend on ALL tasks in wave N:

```bash
# For each task T in wave N and each task U in wave N+1:
story HP-T precedes HP-U
```

### 6. Set Priorities

| Wave | Priority |
|------|----------|
| 1 | high |
| 2 | medium |
| 3+ | low |

```bash
story HP-N priority high    # wave 1
story HP-N priority medium  # wave 2
story HP-N priority low     # wave 3+
```

### 7. Add Acceptance Criteria

For each story, add the acceptance criteria as a comment:

```bash
story HP-N "Acceptance: Config loads from YAML file and returns typed object"
```

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

`.planning/` artifacts (PLAN.md, DESIGN.md) must exist locally. During decomposition, `plan-mapping.json` embeds the relevant DESIGN.md section content, so the pilot loop does not depend on reading PLAN.md or DESIGN.md after decomposition.
