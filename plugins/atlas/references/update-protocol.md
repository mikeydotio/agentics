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

A read-only diagnostic — no lock, no writes, no regeneration:

1. `... lint` (full) → findings by severity.
2. `... ledger diff` → staleness context. A stale doc failing verification
   is drift, not bad mapping — report it as such.
3. map-verifier sweep over all module docs (waves ≤8, sample 5 claims each),
   verdicts go to the REPORT ONLY. Do NOT run `set-verified` here: stamping
   rewrites module docs, which would stale the overview's hashed sources
   from inside a flow that promised not to write. Verdict stamps belong to
   the map and update flows.
4. Report: lint findings, verdict table, staleness coupling, and the
   recommended action (`/atlas update`, or `/atlas map` past the 50% line).

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
