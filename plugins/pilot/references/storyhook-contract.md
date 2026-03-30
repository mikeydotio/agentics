# Storyhook Command Contract

This document maps every pilot operation to real `story` CLI commands. Pilot uses the `story` CLI exclusively — no direct file manipulation of `.storyhook/` data files.

## Available Commands

| Command | Purpose | Output Format |
|---------|---------|---------------|
| `story new "<title>"` | Create a new story | Returns story ID (e.g., HP-5) |
| `story next --json` | Get next actionable story | JSON object or empty |
| `story list --json` | List all stories | JSON array |
| `story search "<query>"` | Search stories | Matching stories |
| `story summary` | Summary statistics | Human-readable text |
| `story context` | Project context summary | Human-readable text |
| `story handoff --since <duration>` | Generate handoff narrative | Human-readable text |
| `story graph` | Dependency graph | DAG visualization |
| `story HP-N is <state>` | Set story state | Confirmation |
| `story HP-N priority <level>` | Set priority (critical/high/medium/low) | Confirmation |
| `story HP-N precedes HP-M` | Set dependency relationship | Confirmation |
| `story HP-N "<comment>"` | Add comment to story | Confirmation |

## Commands That DO NOT Exist

- `story decompose` — does not exist; use sequential `story new` + relationships
- `storyhook_bulk_create` — no bulk API; create stories one at a time
- `story state add` — does not exist; edit `.storyhook/states.toml` directly

## JSON Output

Always request `--json` output where available. If `--json` flag is unavailable for a command, parse human-readable output.

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
