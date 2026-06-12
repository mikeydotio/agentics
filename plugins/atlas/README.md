# atlas

Committed markdown codebase maps for agentic coding tools — full mapping plus
git-aware incremental updates.

> **Status: under construction.** The deterministic core and both orchestrated
> flows are built; see `references/design.md` for the design record and roadmap.

## What it does

- `/atlas map` — generate a complete map of the codebase under `docs/atlas/`:
  a token-budgeted always-loaded `INDEX.md`, per-module docs with type/relationship
  insights, and a cross-cutting architecture overview.
- `/atlas update` — regenerate only the map docs whose recorded source inputs
  changed since they were written (blob-SHA ledger), plus ripple-affected docs.
  Pure renames are rewritten mechanically (no LLM); orphaned docs are removed;
  unchanged docs are never touched — byte-identical across updates.
- `/atlas verify` — read-only lint + sampled verification sweep with a report;
  no regeneration, no writes.
- A SessionStart hook injects staleness warnings so agents know how much to trust
  the map.

## Merge conflicts in the map

Map files are regenerated, never hand-merged. After a merge leaves conflict
markers anywhere in `docs/atlas/`, pick either side and update:

```bash
git checkout --ours -- docs/atlas/    # or --theirs; it does not matter
/atlas update
```

The update quarantines anything still corrupted and regenerates it from code.
`INDEX.md` and `atlas-ledger.json` are derived files — resolving them means
rebuilding, and `merge=union` would corrupt them.

See `references/design.md` for the full design record.
