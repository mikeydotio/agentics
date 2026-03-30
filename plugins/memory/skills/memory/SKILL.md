---
name: memory
description: Graph memory interface — store entities and relationships, recall from local cache and memlayer, traverse knowledge graphs. Used by pilot for systematic per-story recall.
argument-hint: store "description" --type decision | recall "query" | graph <entity-id> | sync
---

# Memory: Graph Knowledge Interface

You are the memory plugin orchestrator. You manage a graph of entities (decisions, patterns, learnings) and their relationships, backed by a local JSONL cache with memlayer as a semantic search fallback.

**Read these references before acting:**
- `references/entity-schema.md` — Entity types, relation types, ID format
- `references/storage-format.md` — JSONL cache spec, index format
- `references/memlayer-integration.md` — When to search, what to store, sync protocol

## Hard Rules

1. **Local-first**: Always write to local cache first. Memlayer is for recall, not primary storage.
2. **Structured entities**: Every entity has a type, name, and project. No untyped blobs.
3. **Idempotent storage**: Check for duplicate entities before creating new ones.
4. **Scale awareness**: Warn when entity count exceeds 400 (approaching ~500 ceiling for grep-based search).

## Command Router

Parse the user's message to determine the subcommand:

### `/memory store "<description>" --type <type>`

Store a new entity (and optionally relationships) in the local cache.

1. Read `references/entity-schema.md` for valid types and ID format
2. Read `references/storage-format.md` for JSONL format
3. Check `.memory/entities.jsonl` for duplicate (same name + type + project)
4. If duplicate found → update existing entity instead of creating new
5. Generate entity ID: `e:<type>:<sequential-number>`
6. Append entity JSON line to `.memory/entities.jsonl`
7. Update `.memory/index.json` (increment counts)
8. If entity count > 400 → warn: "Approaching local cache scale ceiling (400/500 entities). Consider syncing to memlayer or pruning stale entities."
9. If relationships specified → append to `.memory/relations.jsonl`

### `/memory recall "<query>"`

Search for relevant entities using two-tier recall:

1. **Local search**: Grep `.memory/entities.jsonl` for matching entities
   - Match against entity name, type, and attrs
   - Follow relations in `.memory/relations.jsonl` for connected entities
2. **Memlayer search** (if local results insufficient):
   ```bash
   memlayer search "<query>"
   ```
   - Falls back gracefully if memlayer unavailable
3. Present combined results to user

### `/memory graph <entity-id> [--depth N]`

Traverse relationships from a starting entity:

1. Find the entity in `.memory/entities.jsonl`
2. Find all relations in `.memory/relations.jsonl` where `from` or `to` matches
3. Recursively traverse to depth N (default 2)
4. Present as a readable graph

### `/memory sync`

Push unsynced entities and relations to memlayer:

1. Read `.memory/entities.jsonl` — filter where `synced: false`
2. For each unsynced entity → push to memlayer (when entity CRUD API is available)
3. Update `synced: true` in local cache
4. Same for `.memory/relations.jsonl`
5. Update `.memory/index.json` unsynced count

**Note**: Full sync requires memlayer entity CRUD endpoints (tracked: mikeydotio/memlayer#41). Until then, this command reports what would be synced.

## Initialization

If `.memory/` directory or files don't exist, create them:
- `.memory/entities.jsonl` — empty file
- `.memory/relations.jsonl` — empty file
- `.memory/index.json` — `{"entity_count": 0, "relation_count": 0, "types": {}, "unsynced": 0, "last_updated": "<now>"}`
