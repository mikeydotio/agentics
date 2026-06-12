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
generator: cartographer/1 model=<model-id>  # fingerprint — bump invalidates
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

## Roadmap

- [x] Phase 1 — Scaffold, design record, scan + partition
- [ ] Phase 2 — Ledger, lock, status tiers
- [ ] Phase 3 — Lint, INDEX rebuild, router, hook
- [ ] Phase 4 — Agents (cartographer, map-verifier) and map format
- [ ] Phase 5 — Full-map orchestration (SKILL.md) + CLAUDE.md injection
- [ ] Phase 6 — Incremental update + verify flows
- [ ] Phase 7 — Hardening, docs, release

## Out of scope for v1

Submodules; import-graph-driven partitioning (clustering instability would
destabilize doc identity); custom git merge driver; auto-triggering updates from
hooks (cost surprise + recursion risk); time-based staleness; Mermaid generation;
hierarchical maps for 5k+ file monorepos (ceiling + refusal instead);
sampling-based file reads; freshen integration; exact tokenizer integration.
