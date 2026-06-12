# Full-Map Protocol (`/atlas map`)

The orchestrated procedure for generating a complete codebase map. The
orchestrator (the skill) does no mapping itself — cartographer agents write
docs, the CLI does everything deterministic, and the orchestrator only routes,
spawns, and reports.

**Step order is load-bearing.** Verification runs BEFORE the overview pass
because `ledger set-verified` rewrites module-doc frontmatter, and the
overview's ledger entries hash the module docs — verify-after-overview would
immediately stale the overview.

## 0 — Preflight

1. `bash ${CLAUDE_PLUGIN_ROOT}/bin/atlas-router.sh status` — if already mapped
   (`mapped: true`), tell the user a map exists and confirm a full REMAP via
   AskUserQuestion before continuing (the alternative is `/atlas update`).
2. `... lock acquire --holder atlas-map` — on `lock_held`, show the holder and
   stop. Every later step that aborts MUST `lock release` first.
3. `... scan` — on `ceiling_exceeded`, show the message (it explains the
   config remedies) and stop.
4. `... partition` — keep the module list; it drives the fan-out.

## 1 — Confirm gate

One AskUserQuestion: report file count, module count, agents to spawn
(modules + 1 overview + verifiers), and a rough token estimate
(`total_bytes / 3.5` input tokens per pass, ~3 passes: map, verify, overview).
Options: proceed / abort. On abort: `lock release`, stop.

## 2 — Cartographer fan-out

For each module, in waves of **at most 8 parallel `Agent()` calls per
message** (all foreground; never `run_in_background`):

Assemble the prompt in this order (role-by-reference — embedding 30 role
bodies inline would bloat the orchestrator's own context):
1. A two-sentence preamble: "You are a cartographer agent. The first three
   files in `<files_to_read>` define your role, your atlas pipeline
   constraints, and the normative output format — read them first and follow
   them exactly."
2. The assignment block:
   - repo root, module id, module label
   - write target: `docs/atlas/modules/<module-id>.md`
   - generator string: `cartographer/1` (bump the version when prompts change)
   - the module's source file list
   - the ranked symbol table from `... ground <module-id>` — top ~15 entries
     as `name (kind, defined_at, fan_in)` lines, not the full JSON (blobs and
     import lines stay with the CLI; the agent reads the files anyway)
   - module-id conventions for cross-module edges (derive ids the way
     `partition` does: second path segment, slashes→dashes)
3. A `<files_to_read>` block, in this order:
   `plugins/agents/agents/cartographer.md`,
   `plugins/atlas/agent-overrides/cartographer-context.md`,
   `plugins/atlas/references/map-format.md`,
   then every source file of the module.
   (Use absolute paths — agents resolve `<files_to_read>` literally.)

Verifier prompts follow the same shape: preamble + assignment (doc path,
claims to sample) + `<files_to_read>` = map-verifier.md, its override, the
doc under verification.

Mappers write docs directly and return only confirmations — never ingest doc
content into the orchestrator. After each wave: `lock heartbeat`.

## 3 — Finalize

`... ledger finalize --refresh-hashes --generator "cartographer/1"`.
On `invalid_frontmatter` / `duplicate_source` / `missing_source`: re-spawn the
offending cartographer(s) ONCE with the error message appended to their
assignment. A second failure aborts: report, `lock release`, no commit.

## 4 — Verify wave

For each module doc, spawn `map-verifier` (waves ≤8, foreground): prompt =
agent `<role>` + `plugins/atlas/agent-overrides/map-verifier-context.md` +
assignment (doc path, claims to sample: 5). Parse the verdict **leniently —
take the last `{...}` JSON object in the reply** (verifiers sometimes preface
prose despite instructions).

- `pass: true` → record.
- `pass: false` → regenerate that doc ONCE: cartographer in anchored mode
  (prior doc + the verdict's `failures` array as correction input), then
  `ledger finalize --refresh-hashes --generator "cartographer/1"` and
  re-verify the regenerated doc.
- Persistent failure → leave it, record for the report.

Then stamp results: `... ledger set-verified <doc-id> true|false` per doc.

## 5 — Overview pass

One cartographer for `docs/atlas/overview/ARCHITECTURE.md`. Its sources are
the MODULE DOCS (not source files); its `scopes` are the mapped root
directories (from the partition labels' top-level dirs). `<files_to_read>` =
map-format.md + every module doc. Provide the import-line sections from the
grounding packs as the cross-module signal. Remind it: index-facts block is
mandatory, 8–15 bullets, ≤100 chars each.

Then `... ledger finalize --refresh-hashes --generator "cartographer/1"`
again (hashes the overview's sources — the now-final module docs).

## 6 — INDEX + lint

1. `... index rebuild` — on `index_over_budget`: ask the overview agent once
   to shorten index-facts (and report which module summaries are longest);
   rebuild again; still over → abort with the breakdown, `lock release`.
2. `... lint` — ERRORs → regenerate the offending docs once (cartographer,
   anchored, with the lint findings), re-run finalize + index rebuild + lint,
   and re-verify any regenerated doc (step 4 rules). Persistent ERRORs →
   abort: report, `lock release`, NO commit — a map that fails lint is never
   committed.
   L5/L6/L7 WARNs are reported in the summary, not fixed automatically.

## 7 — Wire and commit

1. `... init` — CLAUDE.md managed block + `.atlas/` gitignore entry.
2. `... commit --message "docs(atlas): full codebase map (<M> modules)"
   --also CLAUDE.md --also .gitignore`
   (the CLI stages by pathspec only and refuses mid-merge).

## 8 — Release and report

`... lock release`, then the final summary: module count, verified/failed
docs, INDEX chars vs budget, lint warning counts by check, token-estimate vs
actual agent count, and the standing advice that `/atlas update` keeps the map
fresh incrementally.

## Failure discipline

- Any abort path: `lock release` first, partial docs LEFT ON DISK uncommitted
  (the user can inspect; status will show tier 3 until fixed or removed).
- Never `git add -A`, never commit outside `atlas-cli commit`.
- Never fabricate map content in the orchestrator — only cartographers write
  docs.
