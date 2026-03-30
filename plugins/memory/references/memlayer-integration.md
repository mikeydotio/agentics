# Memlayer Integration

## Overview

Memlayer is a memory-as-a-service backend that provides semantic search across all past conversations and projects. The memory plugin uses it as a secondary recall source (local cache is primary).

## When to Search Memlayer

| Trigger | Query Pattern | Purpose |
|---------|--------------|---------|
| `/pilot resume` | `"<project> pilot"` | Recover prior session context |
| Before generator spawn | `"<component> patterns decisions"` | Systematic per-story recall |
| `/pilot complete` | Store entities | Record project knowledge |
| `/memory recall` (explicit) | User's query | User-driven cross-project recall |

## How to Search

```bash
memlayer search "<query>"
```

The `memlayer` CLI provides:
- `memlayer search "<query>"` — hybrid search across conversations
- `memlayer recent` — list recent sessions
- `memlayer session <uuid>` — full session history

Use keyword-rich queries for best results.

## Graceful Degradation

If memlayer is unavailable (network error, not installed):
- Log warning: "memlayer unavailable — using local cache only"
- Continue with local-only recall
- Never block on memlayer failures

## What to Store

After pilot completes a story, store:
1. **Decisions made** → `decision` entities
2. **Patterns established** → `pattern` entities
3. **Errors encountered** → `error` entities
4. **Lessons learned** → `learning` entities

After pilot completes all stories:
1. **Project summary** → update `project` entity
2. **Cross-cutting patterns** → `pattern` entities
3. **Key decisions** → `decision` entities

## Memlayer Upgrade Roadmap

This is outside agentic-workflows scope but shapes the plugin's design (tracked: mikeydotio/memlayer#41):

1. Entity CRUD endpoints: `POST /entities`, `GET /entities?type=decision`
2. Relation CRUD: `POST /relations`, `GET /relations?from=:id`
3. Graph traversal: `GET /graph/:id?depth=N`
4. Embedding on entities
5. Hybrid recall across conversations and entities

The local cache format intentionally matches the planned API shape, so sync becomes a simple POST per entity/relation.
