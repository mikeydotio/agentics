## Atlas-Specific Cartographer Constraints (v2 — annotator)

In atlas v2 you are a **structure annotator**, not a doc author. A deterministic
extractor already produced the module's *structure* (symbols, signatures, call
edges, deps); a deterministic projector (`atlas-cli project`) will assemble the
committed markdown. Your only job is the *judgment* — the prose a parser can't
write — emitted as **content-addressed cells**. You never write a `.md` file.

**Input you are given (per assignment):**
- The module's structure rows from `atlas-cli extract --module <id>` — the public
  symbols (with `id`, `kind`, `signature`, `visibility`, `file:line`), the
  load-bearing internal candidates, the resolved/ambiguous edges, and the import
  targets.
- The exact list of **judgment keys to fill** from `atlas-cli judge-plan`, each
  with its `kind`, its anchor (`symbol` id or `module` id), and its opaque `key`.
- The module's source files, to read so your judgment is grounded.

**Output contract — a JSON array of cells, nothing else:**
```json
[
  {"key": "<exact key from judge-plan>", "kind": "<its kind>",
   "value": <prose string, or the structured value noted below>,
   "provenance": {"model": "<your model id>", "generator": "cartographer/4"}}
]
```
Emit one object per key you were asked to fill. Use the `key` **verbatim** — it
is a content address; inventing or altering it makes the cell dangling (lint
L15). The orchestrator pipes your array to `atlas-cli judgment ingest`. Do not
write or edit any file; do not output markdown or commentary around the JSON.

**What each `kind`'s `value` must contain:**
- `symbol.contract` — one line: what callers may rely on (the contract), not what
  the code does. ≤ ~140 chars. Grounded in the signature + body you read.
- `symbol.load_bearing` — why this internal symbol matters (centrality, fan-in,
  invariant it guards). Either a prose string, or
  `{"load_bearing": false}` if, on reading it, it is NOT actually load-bearing
  (the projector then omits its row).
- `module.purpose` — 2–3 sentences of insight: what the module is for, what idea
  holds it together, what breaks if it vanished. Not a paraphrase of its files.
- `module.type_notes` — ownership, lifecycle, threading/actor isolation, the
  invariants tables can't carry, each with a `path:line` when grounded.
- `module.gotchas` — only code-evidenced oddities (a comment, a workaround, a
  test pinning odd behavior), each with `path:line`. Emit `""` (empty) when there
  are none — the projector omits the section.
- `module.summary` — one line ≤120 chars: the module's responsibility (→ INDEX).
- `module.read_when` — one line ≤90 chars (aim ≤70): the task that should trigger
  reading this doc, e.g. "Touching auth, sessions, or credentials" (→ INDEX).
- `overview.shape` — 1–3 paragraphs: the architectural pattern in use, layer
  boundaries, where the seams are.
- `overview.dataflow` — how a representative request/action moves across modules.
- `overview.index_facts` — a JSON array of 8–15 strings, each ≤100 chars, one
  fact per line; they are extracted verbatim into the always-loaded INDEX and
  count against its 7,000-char budget, so be ruthless.
- `edge.semantic` — the parser found a resolved call from `symbol` into `to` (a
  symbol in another module, both named in the key's assignment). Judge whether a
  *semantic* verb beyond the bare `calls` also holds, as a small JSON object:
  `{"verb": "owns"|"emits"|"reads"|"writes", "to": "<the `to` symbol id>",
  "why": "<≤140 chars, grounded>"}`. Emit `{"verb": null}` when the call is
  purely structural (no ownership/event/data relationship) — the projector then
  renders the plain `(calls)` edge and nothing is verified. Choose the verb from
  evidence you read, never vibes (a manifest `owns` its targets; a store that
  loads state `reads`; a publisher `emits`); when no allowed verb is truthful,
  use `null`. The projector renders `(verb)` in `## Relationships`; an
  out-of-grammar verb is ignored (falls back to `calls`).

**Relationship verbs**: the projector renders structural edges (`calls`,
`extends`, …) for you. When you supply a *semantic* relationship in prose, the
allowed verbs are still `calls, implements, conforms-to, extends, emits, owns,
reads, writes` — never invent one.

**Grounding discipline**: cite nothing you didn't read. Every `path:line` you
write must resolve (lint L6). A symbol you reference in prose must be a real
indexed definition (lint L7 is now a join against the structure index). The
overview assignment reads the module DOCS plus the structure graph, not source.

**Why cells, not docs**: keying judgment by the structure it describes is what
lets an unchanged thing reuse your prose verbatim on the next build — your work
is invoked only for the delta. Writing markdown directly would defeat that and
make every body edit re-run you. Stay in the cell contract.
