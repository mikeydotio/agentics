# Task Management with Storyhook

This project uses **storyhook** (`story` CLI) for work tracking.

**Important:** The `.storyhook/` directory is version-controlled project data. Do NOT add it to `.gitignore`.

## Session lifecycle

1. Run `story context` at the start of every session to understand project state.
2. Run `story next` to find the highest-priority ready task.
3. Update story status as you work: `story HP-<n> is in-progress`
4. Add progress notes: `story HP-<n> "what changed and why"`
5. Mark complete: `story HP-<n> is done "summary of what was delivered"`
6. Run `story handoff --since 2h` at end of session.

## Planning mode

When creating implementation plans, create a story for each discrete work item, phase, or issue:

```
story new "Phase 1: Set up database schema"
story new "Phase 2: Implement API endpoints"
story new "Phase 3: Add authentication middleware"
```

Define relationships between stories to express dependencies and structure:

```
story HP-1 parent-of HP-2
story HP-2 precedes HP-3
story HP-5 relates-to HP-2
story HP-6 obviates HP-7
```

Set priority on each story so `story next` surfaces the right work:

```
story HP-1 priority critical
story HP-4 priority high
story HP-6 priority medium
```

## During execution

- Before starting a story: `story HP-<n> is in-progress`
- When blocked: `story HP-<n> awaits "reason"`
- When unblocked: `story HP-<n> awaits --clear`
- When done: `story HP-<n> is done "what was delivered"`
- To check what's ready: `story next --count 5`
- To see blocked work: `story list --blocked`
- To see the dependency graph: `story graph`

## Commands

| Action | Command |
|---|---|
| Project overview | `story context` |
| Next ready task | `story next` |
| List open stories | `story list` |
| Show a story | `story HP-<n>` |
| Create a story | `story new "<title>"` |
| Add a comment | `story HP-<n> "comment text"` |
| Set priority | `story HP-<n> priority high` |
| Search | `story search "<query>"` |
| Summary stats | `story summary` |
| Dependency graph | `story graph` |
| Session handoff | `story handoff --since 2h` |
