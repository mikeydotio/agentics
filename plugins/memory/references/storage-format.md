# Storage Format

## Local Cache Location

All local cache files live in `.memory/` at the project root (gitignored).

## Files

### `.memory/entities.jsonl`

One entity per line, JSON format. Append-only (new entities added at end).

```jsonl
{"id":"e:decision:001","type":"decision","name":"Use JSONL for memory cache","project":"agentic-workflows","created":"2026-03-28T12:00:00Z","synced":false,"attrs":{"context":"Need local persistence","alternatives":["SQLite"]}}
{"id":"e:pattern:001","type":"pattern","name":"Wave-based execution","project":"agentic-workflows","created":"2026-03-28T13:00:00Z","synced":false,"attrs":{"description":"Execute tasks in dependency waves"}}
```

### `.memory/relations.jsonl`

One relationship per line, JSON format. Append-only.

```jsonl
{"from":"e:decision:001","rel":"made-during","to":"e:project:agentic-workflows","created":"2026-03-28T12:00:00Z","synced":false}
{"from":"e:pattern:001","rel":"part-of","to":"e:project:agentic-workflows","created":"2026-03-28T13:00:00Z","synced":false}
```

### `.memory/index.json`

Lightweight summary, updated on each write operation:

```json
{
  "entity_count": 47,
  "relation_count": 83,
  "types": {
    "decision": 12,
    "pattern": 8,
    "story": 20,
    "error": 3,
    "learning": 4
  },
  "unsynced": 5,
  "last_updated": "2026-03-28T14:00:00Z"
}
```

## Scale Ceiling

The grep-based local search degrades noticeably beyond ~500 entities (linear scan).

- At 400 entities: `/memory store` emits a warning
- At 500+ entities: Prioritize memlayer backend (Phase B) or prune stale entities

## Sync Tracking

The `synced` field on each entity and relation tracks memlayer sync status:
- `false` — written locally, not yet pushed to memlayer
- `true` — confirmed synced to memlayer

`index.json`'s `unsynced` count reflects total unsynced entities + relations.

## Deduplication

Before creating a new entity, check for existing entities with the same:
- `name` (case-insensitive)
- `type`
- `project`

If a match is found, update the existing entity's `attrs` rather than creating a duplicate.
