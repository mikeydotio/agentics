# atlas

Committed markdown codebase maps for agentic coding tools — full mapping plus
git-aware incremental updates.

> **Status: under construction.** The deterministic core is being built phase by
> phase; see `references/design.md` for the design record and roadmap.

## What it will do

- `/atlas map` — generate a complete map of the codebase under `docs/atlas/`:
  a token-budgeted always-loaded `INDEX.md`, per-module docs with type/relationship
  insights, and a cross-cutting architecture overview.
- `/atlas update` — regenerate only the map docs whose recorded source inputs
  changed since they were written (blob-SHA ledger), plus ripple-affected docs.
- A SessionStart hook injects staleness warnings so agents know how much to trust
  the map.

See `references/design.md` for the full design record.
