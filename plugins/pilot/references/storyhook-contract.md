# Storyhook Command Contract

This document maps pilot operations to storyhook interfaces. Storyhook has two interfaces: **MCP tools** (preferred for batch operations and structured responses) and **CLI** (for simple state changes). No direct file manipulation of `.storyhook/` data files.

## Interface Selection Guide

| Operation | Preferred Interface | Why |
|-----------|-------------------|-----|
| **Create stories from a plan** | MCP `storyhook_decompose_spec` | Single call creates all stories with dependencies, priorities, and wave ordering |
| **Batch create with relationships** | MCP `storyhook_bulk_create` | Single call with relationships via `ref_index` |
| **Query next story** | CLI `story next --json` | Simple, returns one story |
| **Change story state** | CLI `story HP-N is <state>` | Simple one-liner |
| **Add comment** | CLI `story HP-N "<comment>"` | Simple one-liner |
| **Batch state changes** | MCP `storyhook_bulk_update` | Single call for multiple state transitions |
| **Status overview** | MCP `storyhook_get_summary` | Structured counts, avoids dumping all stories into context |
| **List all stories** | MCP `storyhook_list_stories` | JSON by default; **note: no pagination — avoid on large backlogs, prefer `get_summary`** |
| **Full story details** | MCP `storyhook_get_story` | Includes comments and relationships |
| **Dependency graph** | CLI `story graph` | Visual DAG output |
| **Search** | MCP `storyhook_search` | Structured results |

## MCP Tools (Preferred for Batch Operations)

| Tool | Purpose | Key Parameters |
|------|---------|---------------|
| `storyhook_decompose_spec` | **Parse markdown spec into stories** — `### Wave N` headings auto-create wave dependencies; `- [ ]` items become stories; `[HIGH]` sets priority; `#label` sets labels. Use `dry_run: true` to preview. | `content` (markdown), `dry_run` (bool) |
| `storyhook_bulk_create` | Create multiple stories with relationships in one call. Use `ref_index` to reference other stories in the same batch. | `stories` (array with title, priority, labels, relationships) |
| `storyhook_bulk_update` | Batch state transitions. Each update is independent — failures don't block others. | `updates` (array of {id, state}) |
| `storyhook_create_story` | Create a single story with priority, labels, and initial state. | `title`, `priority`, `labels`, `state` |
| `storyhook_update_story` | Update a single story. **Important: processes ONE field per call** in priority order (state > priority > labels > assignee). To update state AND priority, make two calls. | `id`, `state`, `priority`, `labels` |
| `storyhook_get_story` | Get full story details including comments and relationships. | `id` |
| `storyhook_get_next` | Get next actionable story with full context. | — |
| `storyhook_get_summary` | Summary counts by state/priority. **Use this for status checks instead of `list_stories`.** | — |
| `storyhook_list_stories` | List all stories. **No pagination** — dumps entire backlog. Prefer `get_summary` for status, `get_next` for task selection. | `state`, `priority` (filters) |
| `storyhook_add_relationship` | Add dependency between stories. | `story_a`, `relation`, `story_b` |
| `storyhook_add_comment` | Add comment to a story. | `id`, `body` |
| `storyhook_search` | Search stories by text. | `query` |
| `storyhook_get_graph` | Dependency graph visualization. | — |
| `storyhook_generate_report` | Generate report (for human consumption, not agent reasoning — use `get_summary` instead). | `format` |
| `storyhook_commit_sync` | Scan commits and link to stories. | — |

## CLI Commands (For Simple Operations)

| Command | Purpose | Output Format |
|---------|---------|---------------|
| `story new "<title>"` | Create a single story | Returns story ID (e.g., HP-5) |
| `story next --json` | Get next actionable story | JSON object or empty |
| `story list --json` | List all stories | JSON array |
| `story search "<query>"` | Search stories | Matching stories |
| `story summary` | Summary statistics | Human-readable text |
| `story context` | Project context summary | Human-readable text |
| `story handoff --since <duration>` | Generate handoff narrative | Human-readable text |
| `story graph` | Dependency graph | DAG visualization |
| `story decompose --stdin` | Decompose markdown spec from stdin | Created stories |
| `story HP-N is <state>` | Set story state | Confirmation |
| `story HP-N priority <level>` | Set priority (critical/high/medium/low) | Confirmation |
| `story HP-N precedes HP-M` | Set dependency relationship | Confirmation |
| `story HP-N "<comment>"` | Add comment to story | Confirmation |

## JSON Output

Always request `--json` output where available for CLI commands. MCP tools return JSON by default.

### `story next --json` Expected Format

```json
{
  "id": "HP-5",
  "title": "Create config module",
  "state": "todo",
  "priority": "high",
  "comments": []
}
```

If no story is available, the command returns empty output (exit code 0).

### `story list --json` Expected Format

```json
[
  {"id": "HP-2", "title": "...", "state": "done", "priority": "high"},
  {"id": "HP-3", "title": "...", "state": "todo", "priority": "medium"}
]
```

## State Management

### Setting State
```bash
story HP-N is todo
story HP-N is in-progress
story HP-N is verifying
story HP-N is blocked
story HP-N is done
```

States must exist in `.storyhook/states.toml` first. Run `/pilot init` before using custom states.

### Adding Evaluator Feedback

Store structured JSON as a comment to prevent prompt injection:
```bash
story HP-N '{"verdict":"fail","failures":[{"criterion":"API returns 404","evidence":"handler returns 500","suggestion":"add NotFoundError catch"}]}'
```

### Adding Blocked Reason

```bash
story HP-N '{"blocked_reason":"decision","description":"Need user input on auth strategy"}'
story HP-N '{"blocked_reason":"max_retries","description":"Failed 4 attempts","last_feedback":{...}}'
```

## Dependency Management

### Setting Dependencies (Wave Ordering)
```bash
# Task HP-3 must complete before HP-5 can start
story HP-3 precedes HP-5
```

### Validating DAG
```bash
story graph
```
Inspect output for cycles. If the graph contains cycles, the plan is invalid.

## Priority Levels

| Level | Meaning | Assigned To |
|-------|---------|-------------|
| `critical` | Must complete first | Blockers, prerequisites |
| `high` | Wave 1 tasks | Early wave tasks |
| `medium` | Wave 2+ tasks | Later wave tasks |
| `low` | Nice-to-have | Optional tasks |

## Error Handling

### Consecutive Failure Tracking
Track consecutive storyhook command failures. Reset counter to 0 on ANY successful operation.

| Consecutive Failures | Action |
|---------------------|--------|
| 1-2 | Log warning, retry operation |
| 3 | Pause pilot with handoff: "storyhook unavailable" |

### Common Errors
- **Story not found**: Story ID does not exist — check plan-mapping.json
- **Invalid state**: State not in states.toml — run `/pilot init`
- **Permission error**: `.storyhook/` not writable
