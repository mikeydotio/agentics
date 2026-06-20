# Incremental Update Protocol (`/atlas update`) — v2 Projection

Refresh a mapped project after source changes. The v2 economics: re-extract is
cheap and deterministic, `judgment diff` names exactly the cells whose content
address moved, only those are re-judged by an annotator, and `project` re-renders
only the docs that actually changed. **A pull with no relevant change judges
nothing and may rewrite nothing** (the zero-LLM case); a pure body edit judges
nothing and at most re-projects line citations.

**Step order is load-bearing** — same as the map protocol: project → finalize →
index rebuild, with `init` before finalize when a managed file is a mapped source.

## 0 — Preflight

1. `... status` — if not mapped, tell the user to run `/atlas map`. Refuse while
   `MERGE_HEAD` exists (a merge is in progress).
2. `... lock acquire --holder atlas-update` — on `lock_held`, stop.

## 1 — Extract + diff (deterministic, no LLM)

1. `... extract` — rebuild the Structure Index at the current working tree.
2. `... judgment diff` — the v2 staleness engine. It reports:
   - `clean: true` → **nothing to do**. Re-projection would be a byte-for-byte
     no-op and no cell is missing. Release the lock and report "map current"
     (this is the zero-LLM fast path; do not spawn anything).
   - `missing_keys` → cells the LLM must (re)judge — grouped by `module`.
   - `orphaned_keys` → cached cells no longer required (a symbol was removed);
     harmless to serve, dropped by `judgment prune` in the deterministic tail
     (step 6) so `judgments.json` never grows monotonically.
   - `stale_docs` → docs whose projection changed even if no cell did (e.g. a
     body edit shifted a `path:line` citation) — pure re-projection, no LLM.

If `missing_count` is large relative to the map (e.g. ≥50% of cells), offer a
full `/atlas map` instead via AskUserQuestion — a sweeping change is often
cheaper to remap wholesale.

## 2 — Branch

`... branch ensure --op update` — keep `branch`, `base_branch`, `base_sha`. All
writes land here.

## 3 — Judge the delta (LLM — only the missing cells)

If `missing_keys` is empty, skip straight to step 4 (pure re-projection).

Otherwise spawn cartographer **annotators** on `sonnet[1m]`, ≤8 parallel per
message, exactly as in the map protocol — but each assignment carries ONLY this
module's `missing_keys` (the delta), not its whole cell set. Every cell not in
the delta is reused verbatim from the committed `judgments.json` — it never
reaches an LLM. Pipe each wave's JSON arrays to `... judgment ingest`;
`lock heartbeat` between waves.

## 4 — Project (deterministic, no LLM)

`... project` — re-renders the affected docs and leaves every unchanged doc
byte-identical (it compares modulo finalize-managed frontmatter). Confirm
`placeholder_count: 0`; a non-zero value means a delta cell was missed —
re-annotate that module once and re-project. The reported `changed` count is the
set of docs that actually moved.

## 5 — Verify the changed prose (map-verifier on the high-consequence delta)

Structure is verified deterministically by `... lint` (step 6). The judgment prose
that changed this update gets the same bounded, delta-only sweep as a fresh map —
here the in-scope set is just the cells re-judged in step 3:

1. `... judgment verify-set --plan` → the in-scope, not-yet-verified targets
   (`symbol.contract`, `symbol.load_bearing`, `module.gotchas` with verdict
   `unverified`). A no-delta pull plans **nothing** ⇒ no agents — the zero-LLM
   fast path survives through verification.
2. Spawn `map-verifier` over the targets, **≤8 parallel `Agent()` per message**
   (foreground); each returns `{key, verdict, failures[]}`. `lock heartbeat`
   between waves.
3. Pipe verdicts to `... judgment verify-set` (stdin) — it stamps `verify.verdict`
   by key (a pure sink; never edits a cell).
4. For every `fail`: re-spawn that cell's annotator once with the verifier's
   `failures[]` as correction input, `... judgment ingest` the replacement (its
   verdict resets to `unverified`), `... project`, then re-verify just those keys.
   A second `fail` is left `verify.verdict: fail` and surfaced — never loop. JUDGE
   stays the sole cell producer.

## 6 — Wire, finalize, index, lint (the deterministic tail)

1. `... judgment prune` — drop the `orphaned_keys` step 1 reported (cells the
   structure no longer requires). A no-op when nothing is orphaned, and
   reversible via git; it keeps `judgments.json` from accreting dead cells across
   updates. Projection consumed only required cells, so this never changes a doc.
2. `... init` (idempotent; before finalize if a managed file is mapped).
3. `... ledger finalize --refresh-hashes --generator "cartographer/3"` — refreshes
   blobs for changed sources, prunes orphaned ledger entries, rewrites the v2
   structure + judgment_keys blocks. Unchanged docs stay byte-identical
   (hash-gated).
4. `... index rebuild` — from the finalized frontmatter.
5. `... lint` — the gate (L1/L7-join/L12/L13/L15/L16). ERRORs → fix the cause and
   re-run the tail; a lint-failing update is never committed.

## 7 — Commit, release, report

1. `... commit --message "docs(atlas): update (<K> docs, <M> cells re-judged)"`
   (plus `--also CLAUDE.md --also .gitignore` if init changed them).
2. `... lock release`.
3. Report the headline: **"<M> cells re-judged, <K> docs re-projected, <P> docs
   unchanged (byte-identical, never reached an LLM)"** — the v2 successor to v1's
   `git show --stat` hash-gating proof, now at symbol granularity. Then the
   branch handoff (Option A).

## Verify and repair flows

`/atlas verify` (read-only): `... extract` then `... lint --fast` and `... lint`,
plus `... judgment diff`. Structural integrity is fully deterministic now (no
agents). Optionally sample judgment cells with `map-verifier` and record findings
for `/atlas repair`. Report; never regenerate.

`/atlas repair` (targeted): re-judge only the specific cells a prior verify
flagged — spawn an annotator with just those `keys`, `judgment ingest`, then
`project` + the deterministic tail. Repair edits *cells*, never a committed doc by
hand; structural drift (a changed source) is deferred to `/atlas update`.

## Failure discipline

- The zero-LLM fast path (step 1 `clean: true`) must not spawn agents or rewrite
  bytes — releasing the lock and reporting "current" is the whole job.
- All writes on the isolated `atlas/*` branch; any abort releases the lock first.
- Never `git add -A`; commit only via `atlas-cli commit`. The orchestrator writes
  no docs and no cells.
