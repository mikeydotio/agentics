# Entity Schema

## Entity Types

| Type | Description | Common Attributes |
|------|-------------|-------------------|
| `project` | A project or repository | `repo`, `language`, `framework` |
| `decision` | An architectural or design decision | `context`, `alternatives`, `rationale` |
| `pattern` | A recurring code or design pattern | `description`, `examples`, `when_to_use` |
| `story` | A completed story/task | `acceptance_criteria`, `wave`, `story_id` |
| `error` | A notable error or failure | `error_type`, `root_cause`, `fix` |
| `learning` | A lesson learned | `context`, `insight`, `applies_to` |
| `tool` | A tool or library used | `version`, `purpose`, `config` |
| `concept` | A domain concept | `definition`, `related_terms` |

## Relation Types

| Relation | Meaning | Example |
|----------|---------|---------|
| `made-during` | Decision made during a project | decision → project |
| `implements` | Code implements a decision/pattern | story → decision |
| `part-of` | Entity belongs to a larger entity | story → project |
| `depends-on` | Entity requires another | story → story |
| `resolved-by` | Error was fixed by a decision | error → decision |
| `supersedes` | New decision replaces old one | decision → decision |
| `related-to` | General relationship | any → any |
| `caused-by` | Error caused by a pattern/decision | error → pattern |
| `learned-from` | Learning derived from experience | learning → error |

## ID Format

Entity IDs follow the pattern: `e:<type>:<sequential-number>`

Examples:
- `e:decision:001`
- `e:pattern:015`
- `e:project:agentic-workflows`

For project entities, the project name can be used instead of a number.

Sequential numbers are zero-padded to 3 digits. When count exceeds 999, use 4 digits.

## Entity Structure

```json
{
  "id": "e:decision:001",
  "type": "decision",
  "name": "Use JSONL for memory cache",
  "project": "agentic-workflows",
  "created": "2026-03-28T12:00:00Z",
  "synced": false,
  "attrs": {
    "context": "Need local persistence before memlayer upgrade",
    "alternatives": ["SQLite", "JSON file"],
    "rationale": "Simple, appendable, line-oriented for grep search"
  }
}
```

## Relation Structure

```json
{
  "from": "e:decision:001",
  "rel": "made-during",
  "to": "e:project:agentic-workflows",
  "created": "2026-03-28T12:00:00Z",
  "synced": false
}
```
