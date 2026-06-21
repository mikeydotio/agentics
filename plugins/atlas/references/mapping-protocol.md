# Full-Map Protocol (`/atlas map`) — v2 Projection

The orchestrated procedure for generating a complete codebase map. In v2 the map
is a **deterministic projection**: a script extracts the structure, cartographer
agents annotate it with *judgment cells* (the only LLM step), and a script
renders the committed docs. The orchestrator only routes the CLI, spawns
annotators, and reports — it never writes a doc or a cell itself.

**Step order is load-bearing.** project must run before finalize (docs must
exist to be hashed); finalize must run before index rebuild (the INDEX is built
from finalized frontmatter); `init` must run before finalize when CLAUDE.md or
.gitignore is a mapped source (hashing before mutating leaves the root doc stale
at birth).

## 0 — Preflight

1. `bash ${CLAUDE_PLUGIN_ROOT}/bin/atlas-router.sh status` — if already mapped,
   confirm a full REMAP via AskUserQuestion (the alternative is `/atlas update`).
2. `... lock acquire --holder atlas-map` — on `lock_held`, show the holder and
   stop. Every later abort MUST `lock release` first.
3. `... scan` — on `ceiling_exceeded`, show the message and stop.
4. `... partition` — the module list drives the annotator fan-out.

## 1 — Confirm gate + branch

One AskUserQuestion: report file count, module count, and the judgment-cell count
to fill (from a dry `judge-plan` after step 2, or estimated as ~public-symbols +
5×modules + 3). Note that v2 judges only cells, so the token estimate is a
fraction of v1. Options: proceed / abort.

On proceed: `... branch ensure --op map` — keep the returned `branch`,
`base_branch`, `base_sha`. Every map write lands here.

## 2 — Extract (deterministic, no LLM)

`... extract` — builds the Structure Index under `.atlas/structure/` (gitignored).
This is the entire structural layer: symbols (with the three orthogonal hashes),
resolved/ambiguous call edges, and import-derived deps. No agent runs.

## 3 — Judge-plan

`... judge-plan` — the set of judgment cells the structure requires, split into
`missing` (must be filled this run — all of them on a fresh map) and `present`
(none yet). Group `missing_keys` by their `module` for the fan-out.

## 4 — Judge: annotator fan-out (the only LLM step)

For each module, in waves of **≤8 parallel `Agent()` calls per message** (all
foreground), spawn a cartographer **annotator** on `sonnet[1m]`. Assemble the
prompt role-by-reference:
1. Preamble: "You are a cartographer annotator. The first two files in
   `<files_to_read>` define your role and your atlas v2 cell contract — read them
   first and follow them exactly. Emit a JSON array of cells, never a doc."
2. Assignment: repo root, module id/label, the module's structure rows from
   `... extract --module <id>`, and the `missing_keys` for this module from
   judge-plan (each with its `key`, `kind`, and anchor).
3. `<files_to_read>`: `plugins/agents/agents/cartographer.md`,
   `plugins/atlas/agent-overrides/cartographer-context.md`, then the module's
   source files (absolute paths).

Each annotator returns a JSON array of cells (never doc bytes). Collect each
wave's arrays and pipe them to `... judgment ingest` (stdin). After each wave:
`lock heartbeat`. Do not project or commit mid-fan-out — judging is pure cache
population; the deterministic tail renders once at the end.

The overview cells (`overview.shape/dataflow/index_facts`) are one more annotator
whose `<files_to_read>` are the module source roots' structure plus the
already-ingested module cells — it reasons over the module-granularity graph, not
raw source.

## 5 — Project (deterministic, no LLM)

`... project` — renders every committed doc by joining the Structure Index with
the now-populated Judgment Cache. Check the reported `placeholder_count`: it MUST
be 0. A non-zero count means an annotator skipped a key — re-spawn that module's
annotator once with the still-missing keys (from a fresh `judge-plan`), ingest,
re-project.

## 6 — Verify the prose delta (map-verifier on the high-consequence cells)

Structural claims need NO agent — `... lint` (step 8) verifies them against the
Structure Index for free (L1 skeleton, L7 join, L15 no placeholders, L16
doc==projection). The *judgment prose* a parser can't check gets a bounded,
delta-only sweep of the kinds a downstream agent obeys to its peril:

1. `... judgment verify-set --plan` → the in-scope, not-yet-verified targets
   (`symbol.contract`, `symbol.load_bearing`, `module.gotchas`; a cached `pass`
   under an unchanged key is skipped). On a fresh map this is every such cell.
2. Spawn `map-verifier` over the targets in waves of **≤8 parallel `Agent()`
   calls per message** (foreground); each adversarially refutes its cell's claim
   against the cited source and returns a verdict `{key, verdict, failures[]}`.
   `lock heartbeat` between waves.
3. Collect each wave's verdicts and pipe them to `... judgment verify-set`
   (stdin) — it stamps `verify.verdict` by key. verify-set is a pure verdict
   sink; it never edits a cell.
4. For every `fail`: re-spawn that cell's module **annotator** once with the
   verifier's `failures[]` as correction input, `... judgment ingest` the
   replacement (its verdict resets to `unverified`), `... project`, then re-run
   verify-set on just those keys. A second `fail` is left `verify.verdict: fail`
   and surfaced in the report — never loop. The annotator stays the sole cell
   producer; JUDGE is the only thing that writes a value.

This is automatic, not optional — a wrong `contract`/`load_bearing`/`gotcha`
misleads every future agent. Cost stays delta-bounded: ≤8/wave, and an unchanged
cell (cached `pass`) is never re-verified.

## 7 — Wire

`... init` — CLAUDE.md managed block + `.atlas/` gitignore entry. Runs BEFORE
finalize so the root doc hashes the post-init bytes.

## 8 — Finalize, index, lint (the deterministic tail)

1. `... ledger finalize --refresh-hashes --generator "cartographer/4"` — stamps
   blob hashes + baseline into the projected docs and writes the v2 ledger
   (structure fingerprint + per-doc judgment_keys).
2. `... index rebuild` — assembles INDEX.md from the finalized frontmatter +
   the overview's index-facts. On `index_over_budget`, re-spawn the overview
   annotator to shorten `overview.index_facts`, re-ingest, re-project, rebuild.
3. `... lint` — the gate. ERRORs (L1/L7/L12/L13/L15/L16) → fix the cause
   (re-annotate a module, or re-project) and re-run the tail. A lint-failing map
   is never finalized. WARNs are reported, not auto-fixed.

## 9 — Commit, release, report

1. `... commit --message "docs(atlas): full codebase map (<M> modules,
   cartographer/4)" --also CLAUDE.md --also .gitignore`.
2. `... lock release`.
3. Summary: module count, cells judged, INDEX chars vs budget, lint warnings,
   and the branch handoff (Option A — atlas never merges for you): the map is on
   `<branch>` from `<base_branch>@<base_sha>`; review and merge with
   `git switch <base_branch> && git merge --no-ff <branch>`.

## Failure discipline

- All map work happens on the isolated `atlas/*` branch. Any abort: `lock
  release` first; report the branch name and that it is not merged.
- A lint-failing map is never finalized; the final commit is gated on lint.
- Never `git add -A`; commit only via `atlas-cli commit`. Switch branches only
  via `atlas-cli branch ensure`.
- The orchestrator never writes a doc or a cell — extract/project are the CLI's;
  cells come only from annotators via `judgment ingest`.
