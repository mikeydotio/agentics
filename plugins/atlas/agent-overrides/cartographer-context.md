## Atlas-Specific Cartographer Constraints

**Write target**: exactly one file, `docs/atlas/modules/<module-id>.md` (or
`docs/atlas/overview/ARCHITECTURE.md` for the overview assignment), as named in
your prompt. The orchestrator diffs the worktree after your run; any other
modified file discards your work.

**Frontmatter contract**: you write `module`, `summary`, `read_when`, `sources`
(paths only, repo-root-relative), and `references_modules`. You never write
`blob`, `sha`, `baseline`, or `verified` — `atlas-cli ledger finalize` computes
those after your run. A `generator:` line must be present; use the exact string
given in your prompt.

**Overview assignment differences**: sources are the module DOC files
(`docs/atlas/modules/*.md`) — you map from the module docs plus the provided
import graph, you do NOT re-read source files. Include a `scopes:` list naming
the mapped root directories, and the `<!-- atlas:index-facts -->` block (8–15
bullets, each ≤100 chars; they are extracted verbatim into the always-loaded
INDEX and count against its 7,000-char budget).

**Incremental assignments** include the prior doc and per-file diffs. Edit
minimally: untouched lines must survive byte-identical — the hash-gated ledger
keeps unchanged docs out of LLM hands precisely so the map's git history stays
reviewable; don't defeat that inside a doc.

**Budget**: keep module docs in the 2,500–6,000 char band. `summary` ≤120
chars and `read_when` ≤90 chars (aim ≤~70 in practice — long module ids
already consume the INDEX routing row, and over-length lines blow its budget);
they are copied into the budget-capped INDEX.

**Relationship verbs**: every `## Relationships` edge verb MUST be one of
`calls, implements, conforms-to, extends, emits, owns, reads, writes` — lint
L13 rejects anything else. Pick from evidence: catching/casting an error type
or aliasing a type is NOT `conforms-to` (use `reads`, or omit the edge); a
package manifest `owns` the targets it declares (not `builds`/`depends-on`).
When no verb is truthful, drop the edge and note it in Type notes rather than
inventing one. Every right-hand edge module id must be a real module id that
also appears in `references_modules` (lint L12 rejects dangling ids).

**Return contract**: your confirmation (never doc content) is parsed by the
orchestrator — keep the `## Mapping Complete` block format exact.
