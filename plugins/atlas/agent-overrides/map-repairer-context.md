## Atlas-Specific Map-Repairer Constraints

**Findings source**: your findings come from a prior `/atlas verify` — lint
findings (L1–L14) and map-verifier verdict `failures`. They are handed to you in
the prompt; you do not run lint or the verifier yourself. Resolve each, then the
orchestrator re-verifies your work and re-runs lint before committing.

**Write target**: exactly one file, the doc named in your prompt
(`docs/atlas/modules/<module-id>.md` or `docs/atlas/overview/ARCHITECTURE.md`),
edited in place. The orchestrator diffs the worktree after your run; any other
modified file discards your work.

**Search scope**: targeted and finding-scoped only — grep to confirm a flagged
symbol's real location, a relationship's real direction or existence, or whether
a cited path/dependency still exists. Never re-read the whole module to re-derive
content; that is `/atlas update`'s job and it would defeat the point of repair.

**Frontmatter you may touch**: `summary` (≤120 chars) and `read_when` (≤90 chars)
for L14 length fixes, and `references_modules` to drop a dangling id (L12) along
with its body edge. You NEVER touch `sources` paths, `blob`, `baseline`,
`verified`, or `generator` — the orchestrator owns hashes, and changing the
sources list is re-derivation (defer to update). Adding or removing a source
means the module's coverage changed, which is not a repair.

**Relationship verbs**: every `## Relationships` edge verb MUST be one of
`calls, implements, conforms-to, extends, emits, owns, reads, writes` (lint L13).
When you correct or rewrite an edge, keep it in this grammar; when no verb is
truthful, drop the edge rather than invent one. Every right-hand edge module id
must be a real module id present in `references_modules` (lint L12).

**Drift docs**: your prompt will say if the doc is drift (its source code
changed). Fix the flagged claims you can — including searching out a symbol's new
location — but do NOT try to make the doc complete: code added since the doc was
written is invisible to verify's findings and is out of your scope. The
orchestrator keeps drift docs flagged for `/atlas update` via
`ledger finalize --except`, so note any such gap in your confirmation rather than
guessing at it.

**Incremental discipline**: untouched lines must survive byte-identical — the
hash-gated ledger keeps unchanged docs out of LLM hands precisely so the map's
git history stays reviewable; don't defeat that with cosmetic edits.

**Return contract**: your confirmation (never doc content) is read by the
orchestrator — keep the `## Repair Complete` block format exact.
