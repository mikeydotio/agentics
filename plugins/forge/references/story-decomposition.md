# Story Decomposition

How PLAN.md's `## Task Breakdown` wave structure maps to storyhook stories with dependencies,
priorities, and acceptance criteria. See `references/storyhook-contract.md` for the full command
reference (relationship vocabulary, JSON shapes, custom states) — this document covers only the
decompose-specific procedure.

## Process

### 1. Idempotency Check

Before creating stories, check if `.forge/plan-mapping.json` exists:

- **If exists**: Compute MD5 hash of PLAN.md and compare against `plan_hash` in the mapping
  - **Hash matches**: Offer three options via AskUserQuestion:
    - "Continue with existing mapping (Recommended)" / "Resume from where we left off. Pros: no wasted work, preserves story state. Cons: won't pick up manual edits."
    - "Recreate stories (destructive)" / "Delete existing stories, create fresh. Pros: clean slate. Cons: destroys all story progress."
    - "Cancel" / "Abort. Pros: safe, no side effects. Cons: pipeline stalls."
  - **Hash differs**: PLAN.md has changed since last decomposition. Warn user and offer same three options but mark "Recreate stories (destructive) (Recommended)" instead.
- **If not exists**: Proceed with fresh decomposition

### 2. State Setup

`story init` already seeds `todo` / `in-progress` / `done`. Create the two additional states
forge's execution loop needs:

```bash
story state add verifying --super OPEN --role active
story state add blocked --super OPEN --role active
```

`story state add` is not idempotent — it errors (exit 2, `state \`<slug>\` already exists`) if the
slug is already present. Tolerate that specific error rather than treating it as a failure; there
is no `story state list` to check first. Never hand-edit `.storyhook/states.toml`.

### 3. Extract the Task Breakdown Section

`story decompose` treats **every** Markdown heading in its input as a story, not just wave
headings — piping the entire PLAN.md would turn `## Test Strategy`, `## Resumption Points`, and
`## Risk Register` (all present in the plan/SKILL.md PLAN.md template) into spurious stories
alongside the real tasks. Extract just the `## Task Breakdown` section (from that heading up to,
but not including, the next `## ` heading):

```bash
TASKS_FILE=$(mktemp)
awk '/^## Task Breakdown/{flag=1} /^## / && !/^## Task Breakdown/{if(flag)exit} flag' .forge/PLAN.md > "$TASKS_FILE"
```

Do **not** separately run `story new` to create a parent story: `story decompose` auto-creates
one from the first heading in its input (here, "Task Breakdown"), and calling `story new` first
would leave two disconnected parent stories.

Verify `$TASKS_FILE` has `### Wave N` headings and `- [ ]` checkbox items before proceeding; if
the wave headings use a different format, normalize them to `### Wave N` first. Error if no waves
or no checkbox items are found.

### 4. Decompose (Single Call)

`story decompose` creates the parent story, every task story, and all wave dependencies in one
call. It parses:

- `### Wave N` headings → `blocked-by` edges from every wave-N+1 story to every wave-N story
- `- [ ]` checkbox items → individual stories
- `[HIGH]` / `[MEDIUM]` / `[LOW]` inline markers → priority
- `#label` → labels
- Nested bullets under a task (e.g. `- Acceptance: …`, `- Files: …`) → that story's initial
  comment, captured automatically — no separate `story comment` call needed for them
- The input's top-level heading ("Task Breakdown") → the synthetic parent story (`parent-of` /
  `child-of` edges to every created story)

```bash
# Preview first — verify story count, wave structure, relationships:
story decompose --stdin --dry-run < "$TASKS_FILE"

# Create for real:
story decompose --stdin --json < "$TASKS_FILE"
```

Record `.stories[].story.id` from the `--json` response: the first story is `project_story` (the
"Task Breakdown" parent), and each subsequent story maps to one task for `plan-mapping.json`.

If a task needs acceptance criteria beyond what's already captured from its nested bullets, add
it as an additional comment:

```bash
story comment <id> "Acceptance: Config loads from YAML and returns typed object"
```

### 5. Map Stories to DESIGN.md

For each story, identify the relevant DESIGN.md section by matching task descriptions to section
headers. **Embed the section content** (not just headers) in plan-mapping.json so the execution
loop doesn't depend on reading DESIGN.md later.

### 6. Write plan-mapping.json

Write `.forge/plan-mapping.json` (version-controlled):

```json
{
  "plan_hash": "<md5 of PLAN.md>",
  "project_story": "<STORY_ID>",
  "stories": {
    "<STORY_ID>": {
      "task_ref": "Task 1.1",
      "wave": 1,
      "title": "Create config module",
      "acceptance_criteria": "Config loads from YAML file and returns typed object",
      "design_section": "## Config Module\nLoads YAML config from disk. Returns a typed configuration object.",
      "files_expected": ["src/config.ts"]
    }
  }
}
```

IDs come from `story new` / `story decompose` output — never assume a prefix. (The default prefix
is `SH`, not `HP`; if a project runs `story init --prefix <X>`, IDs use `<X>` instead.)

### 7. Validate DAG

Neither `story graph` (text or `--json`) nor `story doctor` reports `blocked-by` cycles — do not
have the model eyeball `story graph` output for cycles (see `storyhook-contract.md`'s **DAG
Validation** section for why that's unreliable). Instead, run the validator script:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/forge-dag-validate.sh .
```

- If `.ok` is `false` (script couldn't run — `story` CLI missing or `story list --json` failed),
  fall back to the Consecutive Failure Tracking flow in `storyhook-contract.md`.
- If `.has_cycles` is `true`, **abort decompose**: report the cycle(s) from `.cycles` to the user
  (each is a story-ID path that closes back on itself) and do not proceed to `execute` — a cyclic
  `blocked-by` graph has no valid execution order.
- If `.has_cycles` is `false`, report the story count and structure to the user and continue.

`story decompose` itself only emits forward cross-wave `blocked-by` edges, which are acyclic by
construction, so a fresh decompose should always pass. The check matters most when Step 1 chose
"Continue with existing mapping" (inheriting whatever the graph already looked like) or when a
manual `story relate` call was made outside decompose.

## Offline Constraint

`.forge/` artifacts (PLAN.md, DESIGN.md) must exist locally. During decomposition,
`plan-mapping.json` embeds the relevant DESIGN.md section content, so the execution loop does not
depend on reading PLAN.md or DESIGN.md after decomposition.
