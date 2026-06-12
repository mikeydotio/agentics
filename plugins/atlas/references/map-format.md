# Atlas Map Format (normative)

This document defines the exact format of every file atlas writes. Cartographer
agents follow it when writing docs; lint enforces the mechanical parts (L1
skeleton, L9/L10 INDEX rules); map-verifier checks the semantic parts. When this
document and an agent's instinct disagree, this document wins.

## File layout in a mapped project

```
docs/atlas/
├── INDEX.md                 # DERIVED — never hand-written (see below)
├── config.yaml              # human-edited configuration
├── atlas-ledger.json        # DERIVED — rebuilt by `ledger finalize`
├── modules/<module-id>.md   # one per module, written by cartographers
└── overview/ARCHITECTURE.md # cross-cutting, written by the overview cartographer
.atlas/                      # gitignored runtime state (lock, drift cache)
```

`<module-id>` is the partition id from `atlas-cli partition` (e.g. `src-auth`).

## Module doc

### Frontmatter

```yaml
---
module: src/auth                      # partition label (path or descriptor)
summary: Session + credential management for all entry points
read_when: Touching authentication, sessions, or credentials
sources:                              # EVERY file this doc drew conclusions from
  - path: src/auth/AuthService.swift
references_modules: [src-api, src-models]
generator: cartographer/1 model=<model-id>
---
```

**Division of labor** — the cartographer writes: `module`, `summary`,
`read_when`, `sources` (paths only), `references_modules`. The orchestrator's
`ledger finalize --refresh-hashes` adds: `blob` per source, `baseline`,
`verified`, and normalizes `generator`. Cartographers never write hashes.

- `summary` — one line, ≤120 chars. Becomes this module's row in the INDEX
  inventory table. State the module's responsibility, not its contents.
- `read_when` — one line, ≤90 chars. Becomes the INDEX routing row. Phrase as
  the task that should trigger reading this doc ("Touching X, Y, or Z").
- `sources` — every file **within this module's partition** you drew
  conclusions from (normally all of them). Complete or the ledger rots
  silently: an unlisted file will never invalidate this doc when it changes.
  Files from OTHER modules never go in `sources` — each source path is owned
  by exactly one module doc. Cross-module evidence is recorded as a
  Relationships edge plus the module id in `references_modules`; when that
  module's content changes, ripple invalidation regenerates this doc.
- `references_modules` — every module id that appears on the right-hand side
  of a Relationships edge below. This drives ripple invalidation.

### Body skeleton (rigid — lint L1 enforces presence and order)

```markdown
# Module: <module path>

## Purpose

## Public API

## Load-bearing internals

## Relationships

## Type notes

## External deps

## Gotchas        ← optional; OMIT the section entirely when empty
```

Identical anchors in every module doc are a feature:
`grep -A20 "## Relationships" docs/atlas/modules/*.md` is a supported query
primitive. Never rename, reorder, or add sections.

### Section rules

**Purpose** — 2–3 sentences of *insight*, not paraphrase. What the module is
for, what design idea holds it together, what would break if it vanished.

**Public API** — a table of the exported/public surface only:

```markdown
| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `AuthService` | class | `src/auth/AuthService.swift:18` | Owns session lifecycle; all login flows enter here |
```

- Alphabetical by symbol. Symbol and Location backticked, code-exact.
- Location is `path:line` of the definition. Lint greps the symbol at that
  path (L7) and checks the path exists (L6) — a wrong row is a lint finding.
- Contract is one line: what callers may rely on, not what the code does.

**Load-bearing internals** — same table shape with `Why it matters` instead of
`Contract`. This is a *ranked selection*, not an inventory. Include an internal
symbol when it scores high on:

- fan-in: referenced from several files (dampen large counts — 100 refs is not
  10× more important than 10)
- centrality: other symbols in this module are built around it
- exported-adjacent: public API behavior is defined by it
- descriptive name (≥8 chars, word-separated) that other code reaches for

Penalize: ubiquitous names (`run`, `get`, `init` — defined in many files),
private one-off helpers, generated code. Omit freely; an empty table is valid.

**Relationships** — an edge list, one edge per line, no prose:

```markdown
- `src-auth.AuthService -> src-api.APIClient (calls)`
- `src-auth.Session -> src-models.User (owns)`
- `src-auth.TokenStore -> src-auth.Keychain (reads)`
```

Grammar: `` `<module-id>.<Symbol> -> <module-id>.<Symbol> (<verb>)` `` with
verbs from: `calls`, `implements`, `conforms-to`, `extends`, `emits`, `owns`,
`reads`, `writes`. Prefer cross-module edges; include intra-module edges only
when load-bearing. Every edge must be grounded in an import, call site, or
declaration you actually located — cite nothing you didn't grep. Every
right-hand module id must appear in `references_modules`.

**Type notes** — short prose on the semantics tables can't carry: ownership
(who creates/destroys what), lifecycle, threading/actor isolation, invariants
("a `Session` always has a valid `User`; enforced at `src/auth/Session.swift:42`").

**External deps** — third-party packages/frameworks this module touches:

```markdown
- KeychainAccess — wraps all keychain reads/writes
- Combine — publishers for session state changes
```

One line each. This section exists so agents don't hallucinate APIs for
dependencies the map is silent about. Internal modules do NOT go here.

**Gotchas** — only claims grounded in code evidence (a comment, a workaround,
a test pinning odd behavior), each with `path:line`. No speculation. Omit the
section when there are none.

### Content rules (all sections)

- One fact per line. A fact split across lines is invisible to grep.
- Lines ≤100 chars except table rows.
- Code-exact, fully-qualified names — an agent greps the literal identifier
  from a stack trace; the map must match on it.
- Every path citation is repo-root-relative, everywhere — tables AND prose.
  Never module-relative shorthand (`hooks/on-stop.sh:34`); lint L6 flags
  shorthand as a dead path because it cannot resolve from the repo root.
- No volatile content: no dates, no commit SHAs, no counts ("17 functions"),
  no "currently/recently/new". Frontmatter carries freshness; bodies must
  stay stable so unchanged docs never churn.
- Target ~2,500–6,000 chars per module doc. Past that, you are inventorying,
  not mapping — cut internals before cutting relationships.

## Overview doc (`overview/ARCHITECTURE.md`)

### Frontmatter

```yaml
---
module: overview/ARCHITECTURE
summary: System architecture and cross-module relationships
sources:                              # the module DOCS, not source files
  - path: docs/atlas/modules/src-auth.md
scopes:                               # mapped roots — tree-SHA invalidation
  - tree: src
generator: cartographer/1 model=<model-id>
---
```

The overview is written from the module docs plus the import graph — NOT by
re-reading source. Its `sources` are the module doc files (so it regenerates
whenever any module doc changed); `scopes` are the mapped root directories
(so committed structural changes invalidate it even when no listed file did).

### Body

```markdown
# Architecture

## System shape

## Module relationships

## Data flow

## Key invariants

<!-- atlas:index-facts -->
- <fact 1>
- <fact 2>
<!-- /atlas:index-facts -->
```

- **System shape** — 1–3 paragraphs: the architectural pattern actually in
  use, layer boundaries, where the seams are.
- **Module relationships** — module-granularity edge list, same grammar as
  module docs but `` `src-auth -> src-api (calls)` ``.
- **Data flow** — how a representative request/action moves through modules.
- **Key invariants** — cross-module rules ("nothing imports the driver except
  `core/repo`"), each with the evidence location.
- **index-facts block** — 8–15 bullets, each ≤100 chars, one fact per line.
  These are extracted verbatim into the always-loaded INDEX: write them as
  the facts an agent would otherwise spend twenty file-reads discovering.
  The block counts against the INDEX's 7,000-char budget — be ruthless.

## INDEX.md (derived — never write or edit by hand)

`atlas-cli index rebuild` assembles INDEX.md from doc frontmatter and the
index-facts block: header + freshness line, routing table (from `read_when`),
module inventory (from `summary`), key facts, footer reminders. Hard budget
7,000 chars (≈2k tokens), warning at 6,000. If a rebuild refuses on budget,
trim module `summary` lines and index facts — never raise the budget.

Merge conflicts on INDEX.md or atlas-ledger.json are resolved by REBUILDING
(`index rebuild`, `ledger finalize`), never by hand-merging. `merge=union` is
forbidden for map files — it silently corrupts structured markdown.

## Generator fingerprint

`generator: cartographer/<prompt-version> model=<model-id>` — recorded per
doc. Bumping the cartographer prompt version or changing models marks every
doc fingerprint-stale on the next `ledger diff`, so prompt improvements
propagate instead of freezing old output in place. The current prompt version
is `1`; bump it whenever cartographer.md or this format doc changes the
expected output.
