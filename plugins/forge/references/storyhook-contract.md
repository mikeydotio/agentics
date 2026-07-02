# Storyhook Command Contract

This document maps forge operations to the real `story` CLI. Storyhook has **one** interface: the
CLI. There is no MCP server — storyhook does not expose one. No direct file manipulation of
`.storyhook/` data files.

The CLI is strictly **verb-first**: the first token after `story` must be a known subcommand.
There is no id-first form (`story HP-N is done` does not exist and errors with `unknown command`,
exit 2). Verify any command you're unsure of with `story help <command>` or `story help --all`.

## Command Reference

| forge needs to… | Command | Notes |
|---|---|---|
| Create a story | `story new "<title>"` | Returns the new story's JSON (`.story.story.id`) |
| Get next actionable story | `story next --json` | See **JSON Output** below — shape and empty-case both differ from what you'd guess |
| List all stories | `story list --json` | Double-nested — see **JSON Output** |
| Show one story | `story show <id> --json` | |
| Set state | `story move <id> <state> ["<comment>"]` | Comment is optional and applied atomically with the transition |
| Set multiple fields at once | `story set <id> --state <slug> --priority <level> …` | See **Field Updates** below |
| Add comment | `story comment <id> "<text>"` | Free text or a JSON blob serialized as text — never raw untrusted text (see **Structured Feedback**) |
| Set priority | `story prioritize <id> <critical\|high\|medium\|low\|none>` | |
| Add/remove labels | `story label <id> <csv>` / `story unlabel <id> <csv>` | |
| Assign | `story assign <id> <member-id\|handle>` | |
| Set "awaiting" reason (does NOT change state) | `story block <id> "<reason>"` / `story unblock <id>` | Orthogonal to the `blocked` *state* — see **Blocked: State vs. Awaiting** |
| Reopen a closed story | `story reopen <id>` | |
| Delete | `story delete <id> "<reason>"` | |
| Dependency between stories | `story relate <a> <relationship> <b>` | Only 8 relations exist — see **Relationship Vocabulary** |
| Remove a dependency | `story unrelate <a> <relationship> <b>` | |
| Decompose a plan into stories | `story decompose --stdin --json` (create) or `story decompose --stdin --dry-run` (preview) | One call does the whole job — see **Decompose** |
| Add a custom state | `story state add <slug> --super OPEN\|CLOSED [--role active]` | Idempotent-unsafe: errors (exit 2) if the slug already exists — see **Custom States** |
| Status overview | `story summary --json` | `.summary.{total_open,total_closed,by_state,by_priority,blocked_count,ready_count,ready_stories}` |
| Dependency graph | `story graph [--critical-path] [--parallel-groups]` | Text/ASCII output only — no JSON, no cycle report (see **DAG Validation**) |
| Search | `story search "<query>" --json` | |
| Project context | `story load-context [--format json]` | |
| Handoff narrative | `story handoff [--since <duration>]` | |

## Relationship Vocabulary

The **only** valid relationship types are:

```
relates-to  blocks  blocked-by  parent-of  child-of  duplicate-of  obviates  obviated-by
```

`story relate <a> <relationship> <b>` rejects anything else — e.g. `precedes`, `follows`,
`starts-before`, `finishes-after`, `coincides-with`, `conflicts-with` all error with
`unsupported relationship`. Do not use them.

The **dependency scheduler** (`story next`, `story graph`, readiness) reads only `blocks` /
`blocked-by`. For wave ordering (predecessor must finish before successor starts):

```bash
story relate <predecessor> blocks <successor>
# equivalently:
story relate <successor> blocked-by <predecessor>
```

Prefer letting `story decompose --stdin` create these edges automatically (see **Decompose**)
over hand-relating stories.

## JSON Output

Every `--json` response is an envelope with `"result": "ok"`. **Every story's fields are nested
one level deeper than you'd expect**: each story is `{"story": {...fields...}}`, not the fields
at the top level.

### `story next --json`

With the default count (1), one ready story:

```json
{
  "result": "ok",
  "story": {
    "story": {
      "id": "HP-5",
      "title": "Create config module",
      "state": "todo",
      "priority": "high",
      "comments": [],
      "relationships": []
    }
  }
}
```

Path to the story fields: **`.story.story.*`** (not `.story.*` or `.*`).

When nothing is ready, the command does **not** return empty output — it returns a message
envelope:

```json
{"result": "ok", "message": "no ready stories"}
```

Detect "nothing ready" by checking for `.message`, not by checking for empty stdout. To
distinguish "all done" from "some blocked," consult `story summary --json`
(`.summary.ready_count`, `.summary.blocked_count`, `.summary.total_open`) or `story list --json`.

### `story list --json`

```json
{
  "result": "ok",
  "stories": [
    {"story": {"id": "HP-2", "title": "...", "state": "done", "priority": "high", "relationships": [...]}},
    {"story": {"id": "HP-3", "title": "...", "state": "todo", "priority": "medium", "relationships": [...]}}
  ]
}
```

Path to each story's fields: **`.stories[].story.*`** (not `.stories[].*`).

### `story summary --json`

```json
{
  "result": "ok",
  "summary": {
    "total_open": 2, "total_closed": 0,
    "by_state": [["in-progress", 1], ["todo", 1]],
    "by_priority": [["critical", 1]],
    "blocked_count": 1, "flagged_count": 0, "ready_count": 1,
    "ready_stories": [{"story": {"id": "HP-1", "...": "..."}}]
  }
}
```

### `story decompose --stdin --json` (real, non-dry-run, run)

```json
{
  "result": "ok",
  "message": "Created 5 stories with 8 relationships:\n  HP-2 child-of HP-1\n  ...",
  "stories": [{"story": {"id": "HP-1", "title": "...", "...": "..."}}, ...]
}
```

Created IDs are at **`.stories[].story.id`**.

## Field Updates

`story set <id> [--title …] [--state …] [--priority …] [--assignee …] [--labels …] [--blocked "reason"] [--unblocked] [--json '{...}']`
updates several fields in a single call. `--json` accepts only these keys:
`title, state, priority, assignee, labels, blocked, story_type` — any other key errors
(`unknown field "<name>" in JSON. Valid fields: ...`). For single-field updates, the dedicated
verbs (`move`, `prioritize`, `assign`, `label`, `block`) are more concise and preferred.

## Structured Feedback (evaluator verdicts, blocked reasons)

The evaluator's structured verdict (`{"verdict":"fail","failures":[...]}`) and the generator's
blocked-reason payload (`{"blocked_reason":"decision","description":"..."}`) are **not** valid
`set --json` payloads — they contain keys outside the fixed field list above. Store them as a
**comment** (the JSON serialized to text, so downstream reads get structured fields rather than
freeform prose — this also prevents prompt injection via the evaluator-to-generator feedback
path):

```bash
story comment <id> '{"verdict":"fail","failures":[{"criterion":"API returns 404","evidence":"handler returns 500","suggestion":"add NotFoundError catch"}]}'
story comment <id> '{"blocked_reason":"decision","description":"Need user input on auth strategy"}'
story comment <id> '{"blocked_reason":"max_retries","description":"Failed 4 attempts","last_feedback":{...}}'
```

## Blocked: State vs. "Awaiting"

Storyhook has two unrelated concepts named around "blocked" — do not conflate them:

- **The `blocked` *state*** (a custom state forge adds — see **Custom States**) is a normal state
  transition: `story move <id> blocked`. It participates in the state machine like any other
  state.
- **The `block`/`unblock` *verb*** sets an `awaiting` reason string on a story **without changing
  its state**: `story block <id> "waiting for design"` / `story unblock <id>`. This is orthogonal
  to state — a `todo` or `in-progress` story can be "awaiting" something while still being in
  that state.

If forge wants both — a state transition *and* a recorded reason — do both explicitly:

```bash
story move <id> blocked
story comment <id> '{"blocked_reason":"decision","description":"..."}'
```

## Custom States

`story init` seeds `todo` / `in-progress` (role: active) / `done` by default. Any additional
states forge needs (e.g. `verifying`, `blocked`) must be created explicitly:

```bash
story state add verifying --super OPEN --role active
story state add blocked --super OPEN --role active
```

`story state add` is **not** idempotent — re-running it on an existing slug errors
(`error: state \`verifying\` already exists`, exit 2). There is no `story state list` to check
first; callers that need idempotency should tolerate/ignore that specific exit-2 error rather
than treating it as a failure. Do not hand-edit `.storyhook/states.toml` directly.

## Decompose

`story decompose` does the entire plan-to-stories job in one call — do not hand-loop `story new`
per task. It accepts a file path or stdin, and parses:

- `### Wave N` headings → automatic `blocked-by` edges from every story in wave N+1 to every
  story in wave N
- `- [ ]` checkbox items → individual stories
- `[HIGH]` / `[LOW]` (etc.) inline markers → priority
- `#label` → labels
- Heading nesting → `parent-of` / `child-of` (a synthetic parent story is created from the
  document's top heading)

```bash
# Preview (no writes):
story decompose --stdin --dry-run < PLAN.md
# or, from a file, without needing stdin:
story decompose PLAN.md --dry-run

# Create for real, capturing created IDs:
story decompose --stdin --json < PLAN.md
```

Parse created IDs from `.stories[].story.id` in the `--json` response.

**Gotcha:** every Markdown heading in the input becomes a story, not just `### Wave N` headings —
piping a full PLAN.md that also has `## Test Strategy` / `## Resumption Points` / `## Risk
Register` sections creates a spurious story per section. Forge's decompose flow handles this by
extracting only the `## Task Breakdown` section first — see `references/story-decomposition.md`.

## DAG Validation

`story graph` is text/ASCII only — it has no `--json` mode and reports no cycle information for
`blocked-by` edges. `story doctor` only catches parent/child cycles, not `blocked-by` cycles.
**Do not** ask the model to "eyeball `story graph` for cycles" — visual cycle detection from
rendered output is unreliable.

In practice this is low-risk for the decompose path specifically: `story decompose` only emits
forward cross-wave `blocked-by` edges (wave N+1 blocked-by wave N), which are acyclic by
construction. A `blocked-by` cycle can only arise from a manual `story relate` call outside
decompose. A general-purpose cycle validator (parsing `story list --json` relationships and
detecting cycles in the `blocked-by` graph) is a known remaining gap — not implemented as part of
this pass.

## Priority Levels

| Level | Meaning |
|-------|---------|
| `critical` | Must complete first — blockers, prerequisites |
| `high` | Early wave tasks |
| `medium` | Later wave tasks |
| `low` | Nice-to-have |
| `none` | Default — no priority assigned |

## Error Handling

### Consecutive Failure Tracking
Track consecutive storyhook command failures. Reset the counter to 0 on ANY successful operation.

| Consecutive Failures | Action |
|---------------------|--------|
| 1-2 | Log warning, retry operation |
| 3 | Pause forge with handoff: "storyhook unavailable" |

### Common Errors
- **`unknown command`** (exit 2): the first token wasn't a real verb — check this document, not
  memory; the CLI has no id-first forms.
- **`unsupported relationship`** (exit 2): the relation isn't one of the 8 listed above.
- **Story not found**: story ID does not exist — check plan-mapping.json.
- **`unknown field "<name>" in JSON`**: a `set --json` payload used a key outside
  `title, state, priority, assignee, labels, blocked, story_type` — use `comment` instead for
  free-form structured data.
- **Invalid state**: state not yet created — see **Custom States** above.
- **Permission error**: `.storyhook/` not writable.
