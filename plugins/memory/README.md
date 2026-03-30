# Memory Plugin

Graph memory interface for Claude Code. Stores entities (decisions, patterns, learnings) and their relationships in a local JSONL cache, with memlayer as a semantic search backend.

## Overview

The memory plugin provides structured knowledge persistence across sessions:

- **Store** decisions, patterns, errors, and learnings as typed entities
- **Recall** relevant knowledge using local search + memlayer semantic search
- **Graph** traverse relationships between entities
- **Sync** push local cache to memlayer (when entity CRUD API is available)

## Commands

| Command | Purpose |
|---------|---------|
| `/memory store "desc" --type decision` | Store a new entity |
| `/memory recall "query"` | Search local + memlayer |
| `/memory graph <entity-id> [--depth N]` | Traverse relationships |
| `/memory sync` | Push unsynced to memlayer |

## Architecture

### Local Cache (`.memory/`)

- `entities.jsonl` — One entity per line (append-only)
- `relations.jsonl` — One relationship per line (append-only)
- `index.json` — Summary counts and sync status

### Two-Tier Recall

1. **Local**: Grep-based search of JSONL files (~500 entity ceiling)
2. **Memlayer**: Semantic search across all conversations and projects

### Entity Types

`project`, `decision`, `pattern`, `story`, `error`, `learning`, `tool`, `concept`

### Relation Types

`made-during`, `implements`, `part-of`, `depends-on`, `resolved-by`, `supersedes`, `related-to`, `caused-by`, `learned-from`

## Integration with Pilot

The pilot orchestrator queries memory systematically before each generator spawn:
```
memory recall "<component> patterns decisions"
```

After story completion, new decisions and patterns are stored as entities.
