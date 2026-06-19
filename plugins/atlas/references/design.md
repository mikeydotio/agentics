# Atlas Design Record

Atlas maintains a **committed, multi-file markdown map of a codebase** — modules, type
system, and the relationships between types and functions — structured for
context-efficient consumption by agentic coding tools at session start. It supports a
full mapping (`/atlas map`) and git-aware incremental updates (`/atlas update`) that
only regenerate map docs whose recorded source inputs actually changed.

This file is the onboarding document for contributors. The full implementation plan
(with per-phase deliverables) lives in the repo owner's plan archive; everything a
contributor needs day-to-day is here.

## Locked design decisions

| # | Decision | Choice |
|---|----------|--------|
| 1 | Name / command / plugin dir | **atlas** / `/atlas` / `plugins/atlas/` |
| 2 | Engine | LLM mapper agents (foreground fan-out), grounded by deterministic signals (git file+blob inventory, import-grep graph, symbol fan-in counts) |
| 3 | Language support | Agnostic; depth scales with how typed the language is |
| 4 | Map home | Committed: `docs/atlas/` (INDEX, modules/, overview/, config, derived ledger). Runtime: `.atlas/` fully gitignored (lock, drift cache) |
| 5 | Always-loaded budget | INDEX only; target ~1.5k tokens, hard ceiling 2k — lint-enforced as ≤7,000 chars (warn 6,000), chars/3.5 heuristic |
| 6 | Delivery | Managed CLAUDE.md block (`<!-- atlas:start/end -->`) containing `@docs/atlas/INDEX.md` import + SessionStart hook adding dynamic staleness info |
| 7 | Staleness | Tiered: T0 silent / T1 informational + per-doc `[STALE]` tags / T2 recommend `/atlas update` / T3 suppress trust ("disregard the imported map") |
| 8 | Incremental engine | Blob-SHA dependency ledger in per-doc frontmatter (source of truth) + derived committed reverse index (`atlas-ledger.json`); ripple via `references_modules` reverse edges; hash-gated regeneration |
| 9 | Content scope | Public API surface + load-bearing internals (ranked); relationship insights; **code structure only** — workflow/commands stay in CLAUDE.md |
| 10 | Verification | Mechanical lint always + bounded LLM verify pass on every regenerated doc |
| 11 | Committing | Auto-commit `docs(atlas): …`, pathspec-only staging (`git add -- docs/atlas/`); refuse mid-merge; never `-A` |
| 12 | Conflicts | Regenerate-on-conflict; INDEX + reverse index mechanically rebuildable; never `merge=union` |
| 13 | Concurrency | mkdir-atomic heartbeat lock in `.atlas/lock/`, 10-min staleness takeover, no PIDs (forge `session-locking.md` rationale) |
| 14 | Scale guardrails | Mappable-file ceiling (default 1,500) with refusal + guidance; 3–15 files / ≤120KB per partition; fan-out ≤8; confirm gate before full map |
| 15 | Format | Rigid identical section anchors in every module doc (the "grep API"); tables for inventories; relationship edge lists one-per-line; no Mermaid; alphabetical ordering; no volatile content in bodies |
| 16 | Agents | Shared `cartographer` + `map-verifier` in `plugins/agents/agents/` + `plugins/atlas/agent-overrides/` |
| 17 | SKILL model | `model: inherit` (pinned small-model skills overflow long sessions) |
| 18 | Cartographer model | `cartographer` + overview spawns pinned to `sonnet[1m]` (Sonnet 1M-context) via the SKILL.md Agent-assembly rule — NOT a `model:` on the shared agent (would leak to forge/rca/council and is inert for atlas's by-reference spawn). `map-verifier` stays default. Generator fingerprint left `cartographer/1` (model not recorded → no forced regeneration of the existing map) |
| 19 | Branch isolation | `/atlas map`/`update` run on an `atlas/<op>-<short-sha>` branch via `atlas-cli branch ensure` (idempotent; refuses mid-merge; handles detached/unborn HEAD), with per-wave checkpoint commits. End-of-run stays on the branch with a suggested merge (Option A — atlas never switches/merges for you). Lock + blob-SHA staleness are branch-agnostic by design |
| 20 | Generator `cartographer/2` | Bumped from `/1` when map-format + cartographer-context gained relationship-verb-selection guidance (catch/cast/alias ≠ `conforms-to`; manifests `owns`, not `builds`) and read_when brevity — these change expected cartographer output, so every map fingerprint-stales and regenerates on next `/atlas update` (the deliberate propagation path; decision 18's "left at `/1`" applied only to the model-only change). Paired with mechanical lint L12 (dangling `references_modules`) + L13 (out-of-grammar edge verbs) + L14 (over-length `read_when`/`summary`) + an L7 fix for qualified `Type.member` symbols — all no-bump CLI changes that catch the same defects deterministically |

### Why blob SHAs, not a baseline commit

`git rev-list --count BASE..HEAD` is ancestry-dependent — it produces garbage after a
rebase or squash merge, and the BASE object may not exist at all in shallow clones.
Per-source-file **blob SHAs** (`git ls-tree -r HEAD`, `git hash-object` for dirty
files) are content-addressed: invalidation survives rebases, detects pure renames with
zero heuristics (same blob OID at a new path), and works in depth-1 clones. The
baseline commit is recorded but **advisory only** (the human-facing "N commits behind"
line, shown only when `git merge-base --is-ancestor` passes).

### Why hash-gated regeneration

LLM output is nondeterministic even at temperature 0. A doc whose recorded
`(path, blob)` inputs are unchanged must **never** be sent to an LLM — that is the
only thing keeping unchanged docs byte-stable across updates. Churn on
genuinely-changed docs is acceptable and informative.

### Why the INDEX is derived

Any two branches that both ran `/atlas update` will conflict on INDEX.md. The INDEX is
therefore assembled mechanically from per-doc frontmatter (`summary`, `read_when`)
plus the `<!-- atlas:index-facts -->` block in `overview/ARCHITECTURE.md` — resolving
a conflict means rebuilding, never hand-merging. Same for `atlas-ledger.json`.

### Why cartographers run on Sonnet 1M (and the `[1m]` caveat)

A cartographer ingests a whole module's source plus its role/override/format docs and
must hold it all coherently — the 1M-context window gives big modules headroom, and
Sonnet is the right cost tier for a 30-agent fan-out (Opus would be wasteful, and the
verifier already provides an independent check on a different model). The pin lives on
the `Agent()` spawn (the orchestrator delivers the role by reference, so a `model:` on
the shared `cartographer.md` would be inert and would also bind forge/rca/council). The
`[1m]` suffix is a Claude Code harness routing token, not an API model id; if a build
doesn't honor it the agent still runs on Sonnet, just at the default window — intent
preserved, nothing breaks. The generator fingerprint deliberately stays `cartographer/1`
(model not recorded): recording it would flag every existing doc fingerprint-stale and
force a one-time full remap, which the model change alone does not warrant — the new
model simply applies to future cartographer work (run `/atlas map` to rebuild on it).

### Why mapping runs on a branch

`/atlas map`/`update` write many docs across several waves before the lint-gated final
commit. A crash or re-run mid-flow could clobber already-completed module docs in the
working tree. Running on a dedicated `atlas/<op>-<short-sha>` branch with per-wave
checkpoint commits makes every completed wave recoverable from git and keeps the user's
working branch clean until they choose to merge. Branching is safe for the ledger
precisely because invalidation is content-addressed (blob SHAs), not ancestry-based —
the same reason rebases and shallow clones don't faze it. Atlas stays on the branch and
suggests a merge rather than switching/merging for you (Option A), consistent with the
"CLI owns every git mutation, never surprise the working tree" discipline.

## Target repo layout (what atlas creates in a mapped project)

```
docs/atlas/
├── INDEX.md                 # always-loaded via @import; DERIVED — rebuildable
├── config.yaml              # globs, ceilings, tier thresholds, module overrides
├── atlas-ledger.json        # DERIVED reverse index: path → {blob, doc};
│                            #   module → referenced_by; generator fingerprint;
│                            #   advisory baseline commit
├── modules/<module-id>.md   # per-module docs; frontmatter = ledger source of truth
└── overview/ARCHITECTURE.md # cross-cutting; contains <!-- atlas:index-facts -->
.atlas/                      # gitignored entirely
├── lock/                    # mkdir-atomic heartbeat lock (lock.json inside)
└── drift-cache.json         # status cache keyed by HEAD + dirty-state hash
```

## Module doc frontmatter schema (ledger source of truth)

```yaml
---
module: src/auth                      # partition identity (path or descriptor)
summary: Session + credential management for all entry points   # → INDEX inventory
read_when: Touching authentication, sessions, or credentials    # → INDEX routing
sources:                              # every file this doc draws conclusions from
  - path: src/auth/AuthService.swift
    blob: 9a3f…                       # git blob SHA of the bytes as mapped
references_modules: [src-api, src-models]   # ripple edges
generator: cartographer/2 model=<model-id>  # fingerprint — bump invalidates
baseline: abc1234                     # advisory only, never used for invalidation
verified: true                        # map-verifier verdict
---
```

## Module doc body — rigid anchors (identical in every doc)

```
# Module: <path>
## Purpose                    2–3 sentences of insight, not paraphrase
## Public API                 table: symbol | kind | path:line | contract; alphabetical
## Load-bearing internals     same table + why-it-matters; ranked selection
## Relationships              edge list: `auth.AuthService -> api.Client (calls)`
## Type notes                 ownership, lifecycle, invariants — prose
## External deps              name + one-line role
## Gotchas                    only if grounded in code evidence; omit if none
```

This uniformity is deliberate: `grep -A20 "## Relationships" docs/atlas/modules/*.md`
is a supported query primitive.

## Staleness tiers (computed by `atlas-cli status`)

| Tier | Trigger (any) | Hook behavior |
|------|---------------|---------------|
| T0 | 0 docs affected | Silent |
| T1 | <25% of docs affected, overview/INDEX sources untouched | One-line notice naming stale modules |
| T2 | ≥25% docs, or overview stale, or >50 in-scope files changed, or baseline unresolvable with drift | Notice + "run /atlas update" |
| T3 | ≥50% docs, or lint ERROR, or conflict markers in map | "Map untrustworthy — disregard the imported INDEX; treat as absent" |

Thresholds are config-overridable. A wrong map presented confidently is worse than no
map — T3 suppression is load-bearing, not polish.

## atlas-cli (bin/atlas-cli, python3 stdlib only)

All output is JSON to stdout: `{"ok": true, …}` or
`{"ok": false, "error": "<code>", "message": "<human text>"}`.
Exit codes: 0 success, 1 operation failed, 2 usage error.

| Subcommand | Function | Phase |
|---|---|---|
| `scan` | mappable files (git ls-files ∩ globs), sizes, ceiling check | 1 |
| `partition` | deterministic module partitioning | 1 |
| `ground` | grounding pack per module (blobs, imports, symbol fan-in) | 2+ |
| `ledger finalize` / `ledger diff` | blob ledger build + invalidation classification | 2 |
| `lock acquire\|heartbeat\|release` | concurrency lock | 2 |
| `status [--for-hook]` | tier computation, drift cache | 2 |
| `lint [--fast]` | integrity checks L1–L11 | 3 |
| `index rebuild` | mechanical INDEX assembly + budget enforcement | 3 |
| `commit` | guarded pathspec-scoped map commit | 3+ |
| `doc apply-renames` | mechanical path rewrite for pure renames (no LLM) | 6 |
| `doc remove` | path-guarded doc deletion; echoes module + sources for regen | 6 |
| `diffpack` | per-doc anchored-regen patch file under `.atlas/diffs/` | 6 |

`ledger diff` additionally reports `dirty_paths` (working-tree-divergent map
inputs — hashed as they exist now) and `new_file_assignments` (see below).
`ledger finalize --refresh-hashes` is churn-free: a doc is rewritten only when
its frontmatter values or bytes actually changed, and the advisory `baseline`
moves only with such a change — unchanged docs stay byte-identical, which is
the hash-gating property `/atlas update` proves with `git show --stat`.

### config.yaml (restricted YAML subset)

The CLI parses a deliberate YAML subset: top-level scalars, one level of nested map,
lists of scalars, and `modules:` as a list of `{name, globs}` maps. Comments and blank
lines are skipped. Anything fancier is unsupported on purpose.

```yaml
max_files: 1500          # scan ceiling
partition:
  min_files: 3
  max_files: 15
  max_bytes: 120000
include:                 # default: ["**"]
  - "**"
exclude:                 # appended to built-in excludes (lockfiles, binaries, docs/atlas, .atlas)
  - "vendor/**"
modules:                 # manual partition overrides — first match wins
  - name: auth
    globs:
      - "src/auth/**"
```

### Partitioning algorithm (deterministic — module identity drives doc identity)

1. Config `modules:` overrides claim files first (config order, first match wins).
2. Build a directory tree of remaining files. A subtree that fits the caps
   (≤max_files, ≤max_bytes) becomes one partition, labeled by the deepest common
   directory of its files.
3. Oversized subtrees recurse. After recursion, sibling `dir` partitions smaller than
   min_files coalesce with the parent's direct files into a `<parent> (misc)` bucket.
4. Buckets over caps split: filename-stem clustering first (stem = basename before the
   first `-` or `_`; groups ≥min_files become `<dir>/<stem>*` partitions), then greedy
   alphabetical chunks (`<dir> (chunk N)`).
5. Module ids sanitize paths (`/`→`-`, non-alphanumerics collapsed); collisions get a
   numeric suffix; output sorted by id.

## New-file assignment (`ledger diff`)

Unmapped files get deterministic destinations, strongest signal first:
(1) a module doc already owning sources in the file's directory (majority,
tie → lexicographic doc id); (2) the partition claiming the file — by
module-id match against an existing doc, then by majority owner of the
partition's other files; (3) a new-module proposal named by the claiming
partition. Quarantined docs' files reappear here by construction — the
update flow ignores those entries because quarantine recovery owns them.

## Roadmap

- [x] Phase 1 — Scaffold, design record, scan + partition
- [x] Phase 2 — Ledger, lock, status tiers
- [x] Phase 3 — Lint, INDEX rebuild, router, hook
- [x] Phase 4 — Agents (cartographer, map-verifier) and map format
- [x] Phase 5 — Full-map orchestration + CLAUDE.md injection (dogfooded:
      32-module map of this repo, 32/32 verifier pass, INDEX 5.6k chars)
- [x] Phase 6 — Incremental update + verify flows (update-protocol.md real;
      doc apply-renames/remove + diffpack + churn-free finalize; e2e fixture
      flows incl. hash-gating byte-identity proof; dogfooded on this repo)
- [x] Phase 7 — Hardening, docs, release (full README at the semver
      quality bar incl. linguist-generated guidance; edge-case sweep
      pinning degenerate repos, corrupted maps, and hostile config;
      ground skips .md prose; L6 non-citation path rules; edge-line
      length exemption; `atlas` in the agent-template pipeline enum)

## v2 — the Projection architecture

The map is now a deterministic projection: a script extracts the structure, the
LLM produces only content-addressed *judgment* cells, and a script renders the
docs — so the model is invoked only for the judgment delta and a no-change
rebuild calls no model at all. The full v2 design record (locked decisions 21–28,
the three schemas, the orthogonal-hash judgment-key derivation, the CLI surface,
and the rewritten protocols) lives in **`references/design-v2.md`**, which
extends this record. The mapping/update protocols and the cartographer override
in this plugin describe the v2 flow; this file remains the v1 base they build on.

## Out of scope for v1

Submodules; import-graph-driven partitioning (clustering instability would
destabilize doc identity); custom git merge driver; auto-triggering updates from
hooks (cost surprise + recursion risk); time-based staleness; Mermaid generation;
hierarchical maps for 5k+ file monorepos (ceiling + refusal instead);
sampling-based file reads; freshen integration; exact tokenizer integration.
