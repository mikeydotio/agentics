# CLAUDE.md Managed Block

Atlas wires its map into a project through a managed block in the project's
CLAUDE.md, delimited by HTML comment markers (the semver plugin's proven
pattern). `atlas-cli init` and `atlas-cli remove` own this block — the skill
never edits CLAUDE.md by hand.

## The block

```markdown
<!-- atlas:start -->
## Codebase Map (atlas)

@docs/atlas/INDEX.md

- The imported INDEX above is this project's codebase map. Use its routing
  table: read the listed module doc before working in that area.
- Prefer the map to rediscovery. A module doc already captures its area's
  purpose, API, load-bearing symbols, relationships, and gotchas — the
  orientation you would otherwise rebuild by exploring. Read the routed doc
  first; explore further only for task-specific detail it doesn't cover.
- The map covers code structure only; build/test/workflow guidance lives in
  the rest of this file.
- After committing changes to mapped source files, suggest running
  `/atlas update` — including when exploration surfaced a durable, map-worthy
  fact (a gotcha, a load-bearing symbol) the map was missing.
<!-- atlas:end -->
```

The canonical template lives in `bin/atlas-cli` (`CLAUDE_MD_BLOCK`); this file
documents it. If they ever diverge, the CLI is authoritative.

## Why an @import

`@docs/atlas/INDEX.md` uses Claude Code's native import: the INDEX loads with
CLAUDE.md for **everyone who clones the repo** — teammates and other agentic
tools that honor CLAUDE.md get the map with zero plugin dependency. The atlas
SessionStart hook (installers only) layers the dynamic part on top: staleness
tier notices, and at tier 3 an explicit "disregard the imported INDEX"
override. Delivery is guaranteed by the import; trust is managed by the hook.

## Protocols

**Inject** (`atlas-cli init`): if `<!-- atlas:start -->` exists, replace
everything through `<!-- atlas:end -->` (idempotent update); else append the
block after existing content with a separating blank line; create CLAUDE.md
containing only the block when the file is missing. Also ensures `.gitignore`
contains a `.atlas/` line (runtime state never gets committed).

**Remove** (`atlas-cli remove`): delete the block between markers inclusive
and collapse leftover blank lines. Map files under `docs/atlas/` and the
`.gitignore` entry are left in place — removal is reversible by re-running
init.

**Update the template**: edit `CLAUDE_MD_BLOCK` in `bin/atlas-cli`, then
re-run `/atlas init` in mapped projects — marker replacement makes the update
idempotent.
