# Incremental Update Protocol (`/atlas update`)

The orchestrated procedure for refreshing an existing map. The point of the
whole design: a doc whose recorded `(path, blob)` inputs are unchanged must
NEVER reach an LLM — hash-gating is what keeps unchanged docs byte-identical
across updates. The orchestrator only routes, spawns, and reports; the CLI
does everything deterministic (including rename rewrites and doc removal);
cartographers write all doc content.

**Step order is load-bearing**, same as the full map plus two update-specific
rules:

- Verification runs BEFORE the overview pass (`ledger set-verified` rewrites
  module-doc frontmatter that the overview's ledger entries hash).
- Stale-doc regeneration (wave A) runs BEFORE ripple regeneration (wave B) —
  ripple agents read the UPDATED docs of the modules they reference.
- Every mutation — doc writes, removals, init repair — precedes the FINAL
  `ledger finalize`, else the ledger correctly reports the map stale at birth.

## 0 — Preflight

1. `bash ${CLAUDE_PLUGIN_ROOT}/bin/atlas-router.sh status` — `mapped: false`
   → there is nothing to update; offer `/atlas map` and stop.
2. `git rev-parse -q --verify MERGE_HEAD` exiting 0 means a merge is in
   progress — stop now ("finish or abort the merge first"); `atlas-cli
   commit` would refuse at the end anyway, so fail fast before spending
   agents.
3. `... lock acquire --holder atlas-update` — on `lock_held`, show the holder
   and stop. Every later abort path MUST `lock release` first.

## 1 — Corruption quarantine

1. `... lint --fast` — collect L2 findings (merge conflict markers).
2. `... ledger diff --generator "cartographer/2"` — an
   `invalid_frontmatter` failure names unparsable docs in its `docs` map.
3. Quarantine set = L2 docs ∪ invalid-frontmatter docs. If non-empty:
   `... doc remove <doc-id>...` — KEEP its output; each removed entry echoes
   the `module` identity and `sources` list that step 5 needs to regenerate
   the doc fresh. Then re-run `ledger diff`. A conflicted doc is regenerated
   from code, never used as an anchor — its content can't be trusted
   (regenerate-on-conflict convention).

Conflicts in `INDEX.md` or `atlas-ledger.json` need no quarantine: both are
derived and mechanically rebuilt in step 8 — never hand-merge them.

## 2 — Plan

Read the diff. If `stale_docs`, `renamed_docs`, `orphaned_docs`,
`fingerprint_stale`, `ripple_docs`, and `new_files` are ALL empty: report the
map current (with the `baseline` garnish when available), `lock release`,
stop.

Otherwise present the plan — every doc that will change and why:

| Class | Action |
|---|---|
| `stale_docs` | anchored regeneration (reasons: edited/deleted/scope paths) |
| `renamed_docs` | mechanical path rewrite, no LLM |
| `orphaned_docs` | doc + INDEX row removed (same commit) |
| `fingerprint_stale` | fresh regeneration (prompt/model changed — an old-format anchor would perpetuate the stale form) |
| `ripple_docs` | anchored regeneration (cross-module claims, `via` modules) |
| `new_files` | per `new_file_assignments`: source additions to existing docs, or new module docs |

Two honesty notes for the plan and the final summary:

- `dirty_paths` non-empty → say plainly that those files are mapped **as they
  exist in the working tree** (hash-what-you-read); if the user later
  discards those changes, the docs go stale again — correctly.
- Files belonging to quarantined docs reappear in `new_files` /
  `new_file_assignments` — ignore those entries; step 1's quarantine output
  owns them.

## 3 — Escalation gate

`summary.affected_pct >= 50` → one AskUserQuestion recommending a full remap
(this much churn regenerates most of the map anyway; a fresh partition is
cheaper and cleaner). Options: full remap / incremental anyway / abort.
Full remap → `lock release`, switch to `mapping-protocol.md`. Abort →
`lock release`, stop.

Below 50%: proceed WITHOUT a gate. The plan presentation is the
transparency; updates must stay low-friction or the map rots.

On any path that will actually write (incremental-anyway, or the below-50%
no-gate path) — but **not** full remap (it hands off to `mapping-protocol.md`,
which branches there) and **not** abort — isolate the run before the first
mutation in step 4: `... branch ensure --op update`. On `ok: false`
(`mid_merge` / `no_commits`; both already ruled out by step 0, so this is
belt-and-suspenders), surface the message, `lock release`, stop. Otherwise keep
`branch` / `base_branch` / `base_sha` for the checkpoints and the report.
Idempotent — a no-op if a prior step already left you on an `atlas/*` branch.

## 4 — Mechanical phase (no LLM)

1. `... doc apply-renames` — rewrites pure-renamed source paths in doc
   frontmatter and bodies (longest-path-first string rewrite). Rewritten
   docs join the VERIFY set (step 6) but not the regen set. Rename entries
   inside stale docs are pre-applied too, so anchors carry correct paths
   before regeneration.
2. `... doc remove <orphaned doc ids>` — the doc vanishes now, its INDEX row
   at the step-8 rebuild, both in the same commit.
3. `... lock heartbeat`.

## 5 — Regeneration waves

Build the regen set, deduplicating docs that appear in several classes
(one regeneration, modes combined). Spawn every cartographer in both waves on
Sonnet's 1M-context model — `Agent()` model `sonnet[1m]` (SKILL.md §Agent
prompt assembly is normative):

- **Anchored** (prior doc is trustworthy): stale docs, ripple docs,
  `to_existing` assignment targets.
- **Fresh** (no anchor): fingerprint-stale docs, `new_modules` proposals,
  quarantine replacements from step 1 (module identity + sources from the
  `doc remove` output).

**Anchored assignment**, per doc:

1. `... diffpack <doc-id> [--add <new-source-path>]...` → writes
   `.atlas/diffs/<doc-id>.patch` (per-source `git diff` from recorded blob to
   working tree, plus deleted/new-source notes) and returns its path. The
   patch stays out of orchestrator context — the agent reads it from disk.
2. Prompt = the standard preamble (see `mapping-protocol.md` §2) + assignment
   block: repo root, module id/label, write target, generator string
   `cartographer/2`, the UPDATED source list (current minus deleted plus
   added), and the anchored-mode line: "Anchored regeneration: edit the prior
   doc minimally — change only statements the patch affects; reproduce every
   other line exactly."
3. `<files_to_read>`: `cartographer.md`, `cartographer-context.md`,
   `map-format.md`, the PRIOR DOC, the patch file, then changed + new source
   files (absolute paths).

**Fresh assignment**: exactly `mapping-protocol.md` §2 (grounding pack via
`... ground <module-id>`, full source list). For quarantine replacements,
`ground` may return `unknown_module` when the current partition no longer
produces that id — proceed without the symbol table and say so in the
assignment.

**Wave order**: wave A (stale + fresh) first, in waves of ≤8 foreground
`Agent()` calls; after each wave `lock heartbeat`, then checkpoint —
`... commit --message "docs(atlas): checkpoint — regen wave A"` (raw doc bytes;
never finalize/index/lint at a checkpoint; this also sweeps up the step-4
mechanical rename/remove mutations). Wave B (ripple) only after wave A
completes, checkpointed the same way
(`docs(atlas): checkpoint — regen wave B`). Ripple assignments are anchored but
get no diffpack — their own sources didn't change. Instead `<files_to_read>` includes the
UPDATED docs of the `via` modules, and the assignment says: update only
statements about those modules; if a referenced module was removed, drop its
edges and remove it from `references_modules`.

## 6 — Finalize + verify changed docs

1. `... ledger finalize --refresh-hashes --generator "cartographer/2"`.
   On `invalid_frontmatter` / `duplicate_source` / `missing_source`:
   re-spawn the offending cartographer(s) ONCE with the error appended.
   A second failure aborts: report, `lock release`, no final commit.
2. Verify wave (≤8, foreground) over every regenerated doc AND every
   apply-renames-rewritten doc — `mapping-protocol.md` §4 rules apply:
   lenient verdict parse (last `{...}` object), `pass: false` → ONE anchored
   regeneration (cartographer on `sonnet[1m]`) with the verdict's `failures`
   array, finalize again, re-verify. Persistent failure → record, move on.
3. `... ledger set-verified <doc-id> true|false` per verified doc, then
   checkpoint: `... commit --message "docs(atlas): checkpoint — verified docs"`.

## 7 — Overview pass

If any module doc was regenerated, added, or removed: regenerate
`overview/ARCHITECTURE.md` — one cartographer on `sonnet[1m]`, anchored (prior
overview + the changed/added module docs in `<files_to_read>`, plus the names
of removed docs). Its `sources` must list ALL current module docs — a removed
module doc would otherwise leave a dead source path that fails the final
finalize. `scopes` stay the mapped top-level directories and NEVER a
directory that contains `docs/atlas` (self-referential staleness); add new
top-level directories introduced by new modules. Then checkpoint:
`... commit --message "docs(atlas): checkpoint — overview"`.

No module doc changed → skip; the overview stays byte-identical.

## 8 — Wire and finalize (canonical order)

1. Init repair, only if needed: managed CLAUDE.md block or `.atlas/`
   gitignore entry missing → `... init` NOW. Mutating mapped files after the
   final finalize leaves the map stale at birth.
2. FINAL `... ledger finalize --refresh-hashes --generator "cartographer/2"`
   — hashes the set-verified stamps and the overview's final bytes.
3. `... index rebuild` — on `index_over_budget`: ask the overview agent once
   to shorten index-facts, and trim over-length `read_when` lines (lint L14
   flags them); rebuild; still over → abort with the breakdown,
   `lock release`, no final commit.
4. `... lint` — ERRORs → regenerate the offending docs ONCE (cartographer on
   `sonnet[1m]`, anchored, with the lint findings as correction input), then
   finalize + index rebuild + lint again, re-verifying anything regenerated
   (step 6 rules). Persistent
   ERRORs → abort: report, `lock release`, no final commit — a lint-failing map
   is never finalized. L5/L6/L7 WARNs go in the summary, unfixed.

## 9 — Commit, release, report

1. `... commit --message "docs(atlas): update map (<N> docs — <short cause>)"`
   — add `--also CLAUDE.md --also .gitignore` only if step 8 ran init. The
   CLI stages by pathspec only, refuses mid-merge, and retries `index.lock`
   contention.
2. `... lock release`, then the summary: per-class counts (regenerated /
   rewritten / removed / added), verification results, INDEX chars vs
   budget, the dirty-files note from step 2 if any, and the hash-gating
   statement: unchanged docs were never touched (`git show --stat` of the
   map commit proves it).
3. Lead with the branch handoff (Option A — atlas never switches your branch or
   merges for you): the update is committed on `<branch>` (from `<base_branch>`
   at `<base_sha>`); merge with
   `git switch <base_branch> && git merge --no-ff <branch>` — or open a PR. Your
   working branch sees the update only after you merge.

## Verify flow (`/atlas verify`)

A read-only diagnostic of the MAP — no lock, no regeneration, no doc rewrites.
It refreshes ONE gitignored state file (`.atlas/verify.json`) so `/atlas repair`
can reuse the findings, exactly as `status` refreshes its drift cache:

1. `... lint` (full) → findings by severity.
2. `... ledger diff` → staleness context. A stale doc failing verification
   is drift, not bad mapping — report it as such.
3. map-verifier sweep over all module docs (waves ≤8, sample 5 claims each),
   verdicts go to the REPORT ONLY. Do NOT run `set-verified` here: stamping
   rewrites module docs, which would stale the overview's hashed sources
   from inside a flow that promised not to rewrite docs. Verdict stamps belong
   to the map and update flows.
4. `... verify-cache write` — pipe the collected verdicts (the JSON array of
   per-doc map-verifier verdicts) on stdin. The CLI recomputes lint, the diff,
   the HEAD and the repo fingerprint itself and persists them alongside the
   verdicts to `.atlas/verify.json`. This is the flow's only write and it
   touches gitignored state, not the map.
5. Report: lint findings, verdict table, staleness coupling, and the
   recommended action (`/atlas repair` for wrong-but-fixable claims, `/atlas
   update` for drift, or `/atlas map` past the 50% line).

## Repair flow (`/atlas repair`)

Verify, then surgically fix what verification flagged — WITHOUT re-deriving whole
docs. Update is driven by the ledger diff (code changed → regenerate the whole
doc); repair is driven by verify FINDINGS (a doc makes specific wrong claims →
correct or delete exactly those). The fixer is the **map-repairer** agent
(Read/Grep/Glob/Edit): it may run a targeted search to resolve one flagged claim,
but never re-surveys a module or adds un-flagged content — that is update's job.

Same load-bearing rules as update — every mutation precedes the FINAL `ledger
finalize`; verification/`set-verified` runs before the index/overview tail — plus
two repair-specific rules:

- A drift doc (its source changed) gets its flagged claims fixed too, but its
  recorded source blobs must NOT advance — it stays flagged for `/atlas update`,
  which alone captures newly-added code. `ledger finalize --except <drift ids>`
  enforces this (R5, the Ledger rule).
- Repair never re-derives: no `diffpack`, no `ground`, no source files in agent
  read-sets, no `doc apply-renames` / `doc remove` (renames/orphans are drift).

### R0 — Preflight
As update §0: `status` (`mapped: false` → offer `/atlas map`, stop); `MERGE_HEAD`
check (stop mid-merge); `... lock acquire --holder atlas-repair` (every abort path
`lock release` first).

### R1 — Acquire findings (reuse or verify)
1. `... verify-cache read`. `valid: true` → reuse `cache.lint`, `cache.diff`,
   `cache.verdicts`; tell the user you are reusing the verification from
   `cache.timestamp`. `valid: false` (`stale_reason` `absent` / `version` /
   `fingerprint`) → say so and re-verify fresh.
2. Re-verify fresh = verify's body inline (`... lint` full, `... ledger diff`,
   map-verifier waves ≤8 sampling 5 claims, on the DEFAULT model), then
   `... verify-cache write` (verdicts on stdin) to persist for next time.
3. If `ledger diff` fails with `invalid_frontmatter`, the map can't be
   classified — a corrupt doc must be regenerated, not repaired. Report "run
   `/atlas update` (it quarantines and regenerates corrupt docs)", `lock
   release`, stop.

### R2 — Plan (fix vs defer)
Partition the findings:

| Bucket | Findings | Repair does |
|---|---|---|
| MECHANICAL | L9/L10 (INDEX), L4/L11 (ledger drift) | `index rebuild` / `ledger finalize` — no agent |
| FIXER | per-doc flagged claims on any doc (clean OR drift): L6/L7/L8/L12/L13/L14, verifier `failures` | one `map-repairer` per doc |
| DEFER | L5 coverage, L2 conflict markers, unparsable frontmatter, any fix needing a section rewrite / re-rank | report "run `/atlas update`" / "`/atlas map`" — repair does NOT fix |

Mark which FIXER docs are **drift** (present in the diff's `stale_docs ∪
renamed_docs ∪ orphaned_docs ∪ fingerprint_stale ∪ ripple_docs`): they are fixed
AND reported for `/atlas update`. Present the plan — per doc, what is fixed and
how, plus the DEFER list. If nothing is FIXER and no MECHANICAL fix would change
anything (clean map, or every finding defers): report and stop — no branch,
`lock release`.

### R3 — Branch + mechanical phase (no LLM)
Only if R2 will write a map file: `... branch ensure --op repair` (→
`atlas/repair-<sha>`; idempotent on an existing `atlas/*` branch). Then, if L9/L10
present, `... index rebuild`; `... lock heartbeat`. No `doc apply-renames` / `doc
remove` — renames and orphans are drift, which repair defers.

### R4 — Fixer waves
One `map-repairer` per FIXER doc, foreground, waves ≤8, on the DEFAULT model
(SKILL.md §Agent prompt assembly). Per-doc prompt = the standard preamble +
assignment:

- repo root; the doc path (read AND write target); whether the doc is drift.
- the doc's findings verbatim — each lint finding (`check`, `message`) and each
  verifier failure (`claim`, `evidence`, `severity`).
- `<files_to_read>`: `map-repairer.md`, `map-repairer-context.md`,
  `map-format.md`, then the doc — and NOTHING else (no diffpack, no ground, no
  source files; the agent greps on demand).

After the wave: `... lock heartbeat`, checkpoint `... commit --message
"docs(atlas): checkpoint — repair fixes"`. Single wave — repair re-derives
nothing, so there is no wave-A/B ripple ordering.

### R5 — Finalize (the Ledger rule)
`... ledger finalize --refresh-hashes --except <drift-doc-ids>`.

- WHY `--except`: a body fix on a drift doc must not advance its recorded source
  blobs, or finalize would mark it current and hide it from `status` / `update`
  despite still needing full re-derivation. Excepted docs keep their stale blobs
  (still flagged); every other doc — clean docs (a no-op re-hash) and the overview
  (which re-hashes the now-changed module-doc bytes, body byte-identical) —
  refreshes, so a repair that touched only clean docs settles to tier 0.
- On `invalid_frontmatter` / `duplicate_source` / `missing_source`: re-spawn the
  offending `map-repairer` ONCE with the error appended; second failure aborts
  (`lock release`, no final commit).

### R6 — Re-verify touched docs
map-verifier waves (≤8) over every doc `map-repairer` edited; lenient verdict
parse. `pass: false` → ONE more `map-repairer` pass with the new failures, then
finalize (same `--except`) and re-verify; persistent failure → `... ledger
set-verified <id> false`, record, move on. `... ledger set-verified <id> true`
for the rest, then checkpoint `... commit --message "docs(atlas): checkpoint —
repair verified"`.

### R7 — Wire and finalize (mirrors update §8)
1. Init repair only if the CLAUDE.md block or `.atlas/` gitignore entry is
   missing → `... init`.
2. FINAL `... ledger finalize --refresh-hashes --except <drift-doc-ids>`.
3. `... index rebuild` — on `index_over_budget`, run ONE `map-repairer` pass on
   `overview/ARCHITECTURE.md` with the over-budget facts framed as an L9 finding
   to shorten them (keeps the no-explore guarantee), rebuild; still over → abort.
4. `... lint` (full) — remaining ERRORs → ONE more `map-repairer` pass on the
   offending docs, finalize + index rebuild + lint again; persistent ERRORs →
   abort (`lock release`, no final commit — a lint-failing map is never
   finalized). Deferred L5/L6/L7 WARNs go in the summary unfixed.

### R8 — Commit, release, report
1. `... commit --message "docs(atlas): repair map (<N> docs — <short cause>)"`
   (`--also CLAUDE.md --also .gitignore` only if R7 ran init).
2. `... lock release`, then the summary: docs repaired by finding type, the DRIFT
   docs fixed-and-still-flagged with "run `/atlas update`", the DEFER list, INDEX
   chars vs budget, and the no-explore statement (repair edited only flagged
   claims; drift was deferred, not papered over).
3. Branch handoff (Option A, as update §9.3): committed on `atlas/repair-<sha>`
   from `<base_branch>`; merge with `git switch <base_branch> && git merge
   --no-ff <branch>` or open a PR. Your working branch sees the repair only after
   you merge.

### Where repair differs from update
- Driven by verify findings, not the ledger diff.
- `map-repairer` (Read/Grep/Glob/Edit, targeted search) instead of cartographer
  (full re-derivation). No diffpack, no ground, no source files in read-sets.
- No `doc apply-renames` / `doc remove`; renames and orphans are drift → defer.
- An R1 reuse-or-verify front phase and an R2 fix-vs-defer partition update lacks.
- `ledger finalize --except` keeps drift docs flagged after a body fix.
- No cascade overview regeneration — the overview's hashes refresh mechanically in
  R5/R7; its prose changes only if it was itself a FIXER target.

## Conflict resolution recipe (for humans)

After a merge leaves conflict markers anywhere in `docs/atlas/`, either side
works — the map is regenerated, not merged:

```bash
git checkout --ours -- docs/atlas/    # or --theirs; it does not matter
/atlas update
```

The update detects remaining drift, quarantines anything still corrupted,
and regenerates from code. `INDEX.md` and `atlas-ledger.json` are derived
files: resolving them means rebuilding (`index rebuild`, `ledger finalize`),
never hand-merging, and never `merge=union`.

## Failure discipline

- All update work happens on the isolated `atlas/*` branch created in step 3.
  Checkpoint commits there are crash-recovery save-points, not validated maps.
- Any abort path: `lock release` first. Checkpointed docs remain committed on
  the `atlas/*` branch — report the branch name and that it is **not** merged.
  Your working branch is untouched, so a crash or re-run cannot clobber a good
  committed map. Inspect the branch, re-run `/atlas update`, or delete it.
- A lint-failing map is never **finalized**: the canonical final commit (step 9)
  and the suggested merge are gated on lint passing (step 8). Checkpoints are
  exempt — disposable branch state.
- Never `git add -A`; commit only via `atlas-cli commit`; switch branches only
  via `atlas-cli branch ensure`.
- Never fabricate or hand-edit map content in the orchestrator — mechanical
  mutations go through `doc apply-renames` / `doc remove`, prose through
  cartographers.
