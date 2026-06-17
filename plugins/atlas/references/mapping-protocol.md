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
(modules + 1 overview + verifiers), a rough token estimate
(`total_bytes / 3.5` input tokens per pass, ~3 passes: map, verify, overview),
and that the map is built on its own `atlas/map-…` branch.
Options: proceed / abort. On abort: `lock release`, stop.

On proceed, isolate the run **before any doc is written**:
`... branch ensure --op map` — on `ok: false` (`mid_merge` / `no_commits`),
surface the message, `lock release`, stop. Otherwise keep the returned
`branch`, `base_branch`, and `base_sha` for the checkpoint commits and the
final report. Every map write from here lands on this branch, so a crash or
re-run cannot clobber committed map work on your working branch. (Placed here,
after the abort gate, so a declined map never leaves a stray branch behind; the
lock is already held from step 0, so the branch is created under it.)

## 2 — Cartographer fan-out

For each module, in waves of **at most 8 parallel `Agent()` calls per
message** (all foreground; never `run_in_background`). Spawn each cartographer
on Sonnet's 1M-context model — set the `Agent()` model to `sonnet[1m]`
(SKILL.md §Agent prompt assembly is normative):

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
content into the orchestrator. After each wave: `lock heartbeat`, then
checkpoint the completed docs —
`... commit --message "docs(atlas): checkpoint — module docs wave <k>"`.
Commit raw doc bytes; do **not** run `ledger finalize`, `index rebuild`, or
`lint` at a checkpoint (those belong to the load-bearing tail; running them
mid-flow is churn). Checkpoints are crash-recovery save-points on the `atlas/*`
branch, not validated maps — a wave that wrote nothing makes `commit` a clean
no-op.

## 3 — Finalize

`... ledger finalize --refresh-hashes --generator "cartographer/1"`.
On `invalid_frontmatter` / `duplicate_source` / `missing_source`: re-spawn the
offending cartographer(s) ONCE with the error message appended to their
assignment. A second failure aborts: report, `lock release`, no final commit
(any checkpoints stay on the branch).

## 4 — Verify wave

For each module doc, spawn `map-verifier` (waves ≤8, foreground): prompt =
agent `<role>` + `plugins/atlas/agent-overrides/map-verifier-context.md` +
assignment (doc path, claims to sample: 5). Parse the verdict **leniently —
take the last `{...}` JSON object in the reply** (verifiers sometimes preface
prose despite instructions).

- `pass: true` → record.
- `pass: false` → regenerate that doc ONCE: cartographer in anchored mode
  (prior doc + the verdict's `failures` array as correction input; spawn it on
  `sonnet[1m]`), then
  `ledger finalize --refresh-hashes --generator "cartographer/1"` and
  re-verify the regenerated doc.
- Persistent failure → leave it, record for the report.

Then stamp results: `... ledger set-verified <doc-id> true|false` per doc, and
checkpoint: `... commit --message "docs(atlas): checkpoint — verified docs"`.

## 5 — Overview pass

One cartographer (spawned on `sonnet[1m]`) for
`docs/atlas/overview/ARCHITECTURE.md`. Its sources are
the MODULE DOCS (not source files); its `scopes` are the mapped root
directories (from the partition labels' top-level dirs) — but NEVER a
directory that contains `docs/atlas` itself, or every map commit would
re-invalidate the overview forever (self-referential staleness). `<files_to_read>` =
map-format.md + every module doc. Provide the import-line sections from the
grounding packs as the cross-module signal. Remind it: index-facts block is
mandatory, 8–15 bullets, ≤100 chars each.

Then `... ledger finalize --refresh-hashes --generator "cartographer/1"`
again (hashes the overview's sources — the now-final module docs), and
checkpoint: `... commit --message "docs(atlas): checkpoint — overview"`.

## 6 — INDEX + lint

1. `... index rebuild` — on `index_over_budget`: ask the overview agent once
   to shorten index-facts (and report which module summaries are longest);
   rebuild again; still over → abort with the breakdown, `lock release`.
2. `... lint` — ERRORs → regenerate the offending docs once (cartographer on
   `sonnet[1m]`, anchored, with the lint findings), re-run finalize + index
   rebuild + lint,
   and re-verify any regenerated doc (step 4 rules). Persistent ERRORs →
   abort: report, `lock release`, no final commit — a lint-failing map is never
   finalized (branch checkpoints are exempt).
   L5/L6/L7 WARNs are reported in the summary, not fixed automatically.

## 7 — Wire and commit

1. `... init` — CLAUDE.md managed block + `.atlas/` gitignore entry.
   **Init must run BEFORE the final `ledger finalize`** of step 5/6 when
   CLAUDE.md or .gitignore is a mapped source (root module): init mutates
   both files, and hashing before mutating leaves the root doc stale at
   birth. Canonical order: verify → set-verified → overview → **init** →
   finalize → index rebuild → lint → commit.
2. `... commit --message "docs(atlas): full codebase map (<M> modules)"
   --also CLAUDE.md --also .gitignore`
   (the CLI stages by pathspec only and refuses mid-merge).

## 8 — Release and report

`... lock release`, then the final summary: module count, verified/failed
docs, INDEX chars vs budget, lint warning counts by check, token-estimate vs
actual agent count, and the standing advice that `/atlas update` keeps the map
fresh incrementally.

Lead the summary with the branch handoff (Option A — atlas never switches your
branch or merges for you): the map is committed on `<branch>` (from
`<base_branch>` at `<base_sha>`); review it, then merge with
`git switch <base_branch> && git merge --no-ff <branch>` — or open a PR. Note
that your working branch sees the map only after you merge.

If `.gitattributes` does not already cover the map, append the optional
suggestion: `docs/atlas/** linguist-generated=true` collapses map churn in PR
diffs (README §Collapsing map diffs). Suggest only — atlas NEVER writes
`.gitattributes` itself.

## Failure discipline

- All map work happens on the isolated `atlas/*` branch created in step 1.
  Checkpoint commits there are crash-recovery save-points, not validated maps.
- Any abort path: `lock release` first. Checkpointed docs remain committed on
  the `atlas/*` branch — report the branch name and that it is **not** merged.
  Your working branch is untouched, so a crash or re-run cannot clobber a good
  committed map. Inspect the branch, finish it with `/atlas update`, or delete
  it.
- A lint-failing map is never **finalized**: the canonical final commit (step 7)
  and the suggested merge are gated on lint passing (step 6). Checkpoints are
  exempt — they are disposable branch state.
- Never `git add -A`; commit only via `atlas-cli commit` (pathspec-scoped to
  `docs/atlas/`, refuses mid-merge); switch branches only via
  `atlas-cli branch ensure`.
- Never fabricate map content in the orchestrator — only cartographers write
  docs.
