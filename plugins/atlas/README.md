# atlas — Committed Codebase Maps

Agentic coding tools start every session blind: they re-discover the same
architecture, the same load-bearing functions, the same gotchas, twenty file
reads at a time. Atlas generates a **committed, multi-file markdown map** of a
codebase — a token-budgeted `INDEX.md` loaded into every session via a
CLAUDE.md `@import`, plus per-module docs with public API tables, ranked
internals, relationship edges, and grounded gotchas — and keeps it current
with **git-aware incremental updates** that only regenerate what actually
changed. Anyone cloning the repo gets the map for free; reading it requires
no plugin.

## Quick start

```
/atlas map        # partition the codebase, spawn mappers, commit on a branch
# ...hack away for a few days...
/atlas update     # regenerate only the docs whose sources changed
```

`map` and `update` run on their own `atlas/<op>-…` branch, committing at
checkpoints as each wave of docs completes and finishing with a scoped final
commit (`docs(atlas): ...`) — gated on lint — that contains the map plus a
managed CLAUDE.md block which `@import`s the INDEX. Atlas leaves you on the
branch with a suggested merge; it never switches branches or merges for you, so
a crash or re-run can't clobber a good map on your working branch. Once merged,
a SessionStart hook warns agents when the map drifts from the code.

## Commands

| Command | Description |
|---------|-------------|
| `/atlas map` | Full map: scan, partition, spawn cartographer agents, verify, lint — on an `atlas/*` branch, checkpointed per wave, final commit gated on lint |
| `/atlas update` | Incremental: regenerate only stale/affected docs; mechanical rename rewrites; orphan removal — same branch + checkpoint flow |
| `/atlas status` | Mapped? How stale? Current tier and which docs drifted |
| `/atlas verify` | Read-only diagnostic: full lint + sampled claim verification, report only — no writes |
| `/atlas init` | (Re)inject the managed CLAUDE.md block and the `.atlas/` gitignore entry |
| `/atlas remove` | Strip the CLAUDE.md block; map files stay on disk until you delete them |

## The map on disk

```
docs/atlas/
├── INDEX.md                 # always-loaded routing table — DERIVED, never hand-edited
├── config.yaml              # your configuration (see below)
├── atlas-ledger.json        # DERIVED reverse index of the per-doc ledgers
├── modules/<module-id>.md   # one doc per module, written by cartographer agents
└── overview/ARCHITECTURE.md # cross-cutting shape, data flow, invariants
.atlas/                      # gitignored runtime state (lock, drift cache, diff packs)
```

The INDEX stays within a hard 7,000-character budget (~2k tokens) so it can be
loaded into every session unconditionally. It carries one routing row per
module — *"when working on X, read docs/atlas/modules/Y.md first"* — plus a
handful of architecture facts. Everything bulky lives in the per-module docs,
which agents read on demand.

Every module doc has identical section anchors (`## Purpose`, `## Public API`,
`## Load-bearing internals`, `## Relationships`, `## Type notes`,
`## External deps`, `## Gotchas`), which makes the map a grep API:
`grep -A20 "## Relationships" docs/atlas/modules/*.md` is a supported query.

## How incremental updates work

Each module doc's frontmatter records every source file it drew conclusions
from, with the **git blob SHA** of the bytes as mapped:

```yaml
sources:
  - path: src/auth/AuthService.swift
    blob: 9a3f…
```

`/atlas update` compares those recorded blobs against the repo now:

- **Changed blob** → the doc is stale → regenerated *anchored*: the agent gets
  the prior doc plus a diff pack and edits only what the change affects.
- **Same blob, new path** (pure rename) → rewritten mechanically. No LLM.
- **All sources deleted** → the doc and its INDEX row are removed.
- **Cross-module ripple** → docs that declare `references_modules: [the-changed-module]`
  are refreshed against the updated doc, so cross-module claims don't rot.
- **New files** → assigned deterministically to an existing doc or proposed as
  a new module.
- **Unchanged** → the doc is never sent to an LLM, so it stays byte-identical.
  This is the core invariant: the update's net branch diff
  (`git diff --stat <base>..atlas/update-…`) lists only docs whose inputs
  actually changed.

Blob SHAs are content-addressed, so invalidation survives rebases, squash
merges, and shallow clones — there is no baseline commit to lose. Uncommitted
changes are fine: dirty files are hashed as they exist in the working tree,
and the update says so.

## Staleness tiers

`atlas-cli status` distills drift into a tier; the SessionStart hook injects
the message so agents know how much to trust the map:

| Tier | Trigger (any) | Session behavior |
|------|---------------|------------------|
| 0 | Nothing affected | Silent |
| 1 | <25% of docs affected | One-line notice naming the stale docs |
| 2 | ≥25%, or overview affected, or >50 in-scope files changed | Notice + "run /atlas update before relying on those docs" |
| 3 | ≥50%, or lint ERROR / conflict markers / invalid frontmatter | "Disregard the imported INDEX, treat the map as absent" |

A wrong map presented confidently is worse than no map — tier 3 actively
suppresses trust rather than hoping for the best.

## Merge conflicts in the map

Map files are regenerated, never hand-merged. After a merge leaves conflict
markers anywhere in `docs/atlas/`, pick either side and update:

```bash
git checkout --ours -- docs/atlas/    # or --theirs; it does not matter
/atlas update
```

The update quarantines anything still corrupted and regenerates it from code.
`INDEX.md` and `atlas-ledger.json` are derived files — resolving them means
rebuilding, and `merge=union` would corrupt them.

## Configuration

`docs/atlas/config.yaml` — all keys optional:

```yaml
max_files: 1500          # scan ceiling; atlas refuses to map past it
include:                 # globs that define "mappable" (default: everything)
  - "src/**"
exclude:                 # appended to built-ins (lockfiles, minified/generated
  - "vendor/**"          #   files, docs/atlas/, .atlas/, binaries by sniff)
partition:
  min_files: 3           # smaller partitions coalesce into a (misc) bucket
  max_files: 15          # per-mapper attention cap
  max_bytes: 120000      # ~30k tokens of source per mapper
modules:                 # manual partition overrides — first match wins
  - name: auth
    globs:
      - "src/auth/**"
thresholds:              # staleness tier tuning (percentages / file count)
  recommend_pct: 25      # tier 2 at this % of docs affected
  untrust_pct: 50        # tier 3 at this % of docs affected
  recommend_files: 50    # tier 2 when this many in-scope files changed
```

The parser is a deliberate stdlib-only YAML subset: top-level scalars, one
level of nesting, lists of scalars, and `modules:` entries as shown. Comments
are fine; anchors, multi-line strings, and deeper nesting are not.

## Collapsing map diffs in PRs

If map churn clutters your pull-request diffs, mark the **generated** map files
as generated — but keep the hand-edited `config.yaml` visible in review:

```gitattributes
docs/atlas/modules/**        linguist-generated=true
docs/atlas/overview/**       linguist-generated=true
docs/atlas/INDEX.md          linguist-generated=true
docs/atlas/atlas-ledger.json linguist-generated=true
```

GitHub then collapses those files in PR views and excludes them from language
stats, while `docs/atlas/config.yaml` — the one file you hand-edit, which
controls what gets mapped — stays reviewable, so a bad exclude can't silently
shrink coverage unnoticed. Atlas suggests this when it fits but never writes
`.gitattributes` on its own.

**Keep regenerations legible.** Commit map regenerations (`/atlas update`) in
their own `docs(atlas): …` commit, never mixed into a code change. A collapsed
map diff is safe to skim *only* when it isn't buried inside a noisy code PR — an
atlas-only diff stays small enough to expand and read, which is the one human
check on a confidently-wrong regeneration the freshness ledger can't catch
(doc and ledger hashes move in lockstep even when the content is wrong).

## Limitations

- **Git submodules are not mapped.** Their files belong to another object
  database; map each submodule in its own repo.
- **~1,500 mappable files is the ceiling** (configurable). Past it, atlas
  refuses with guidance instead of producing a map too large to trust. For
  monorepos, scope `include:` to one package per map, or split with
  `modules:` overrides — a hierarchical map-of-maps is explicitly out of
  scope for v1.
- **Token budgets are estimated** as `chars / 3.5`, not tokenized exactly.
- **One writer at a time**: map and update take a heartbeat lock under
  `.atlas/lock/`; a crashed run's lock is taken over after ~10 minutes.
- **Mid-merge refusal**: atlas never commits — or creates its working branch —
  while `MERGE_HEAD` exists; finish or abort the merge first.
- **Branch handoff is manual**: `map`/`update` leave the finished map committed
  on an `atlas/*` branch and print a suggested merge; atlas never switches your
  branch or merges for you. Merge it (or open a PR) to land the map on your
  working branch.

## FAQ

**Why is the hook telling me docs are stale?**
Source files listed in those docs' ledgers changed (or a referenced module
did). The map is still mostly usable at tier 1–2 — run `/atlas update` to
clear it. At tier 3, stop trusting the map until you update.

**Why did atlas refuse to map?**
The common refusals: not a git repository; more mappable files than
`max_files` (scope with `include:`/`exclude:` or raise the ceiling
deliberately); a merge in progress; another session holding the lock; or a
rebuilt INDEX that would exceed its 7,000-char budget (trim summaries,
`read_when` lines, or index facts — the budget is never raised).

**I ran `/atlas update` and most docs didn't change. Is that right?**
That's the point. A doc regenerates only when its recorded inputs changed;
everything else stays byte-identical — by hash-gating, not by luck.

**Do people reading the map need the plugin?**
No. The map is committed markdown, and the CLAUDE.md import is native Claude
Code syntax. The plugin is only needed to generate and update the map.

**Why can't I edit INDEX.md or atlas-ledger.json?**
Both are derived mechanically from module-doc frontmatter. Hand edits are
overwritten on the next rebuild and flagged by lint (L10) until then. Edit
the module docs (or better: let the cartographers do it) and rebuild.

**What does `verify` do that `update` doesn't?**
Nothing destructive — that's the feature. It lints, reports staleness, and
samples claims from every module doc against the code, writing a report and
changing nothing. Use it to audit a map you didn't generate.

## Requirements

- **git** — invalidation is built on git plumbing (`ls-tree`, `hash-object`)
- **python3** — the deterministic CLI is stdlib-only python3
- **jq** — required by the SessionStart hook

See `references/design.md` for the decision record and
`references/map-format.md` for the normative file format.
