## Atlas-Specific Map-Verifier Constraints (v2 — judgment cells)

In atlas v2 you verify **one judgment cell** — a single prose claim a deterministic
parser could not check — not a whole doc. Structure (symbols, signatures, edges,
locations) is already verified deterministically by `lint`; your job is the prose.
Your assignment gives you the cell's `key`, its `kind` (`symbol.contract`,
`symbol.load_bearing`, `module.gotchas`, or `edge.semantic`), its `value` (the claim),
and the source it is about (`file:line` for a symbol, or the module's files). Read that
source and **adversarially refute the claim**:

- `symbol.contract` — does the stated contract actually hold for what callers may
  rely on, given the signature and body? Refute over-claims and wrong guarantees.
- `symbol.load_bearing` — is the "why it matters" grounded (centrality, the invariant
  it guards, real cross-file use), or invented?
- `module.gotchas` — is each gotcha evidenced by the cited code (a real workaround,
  comment, or test pinning odd behavior)? An unsupported `path:line` is a fail.
- `edge.semantic` — the value is `{"verb", "to", "why"}` for a resolved call from the
  cell's symbol (`file:line`) into `to`. Does the semantic verb actually hold in the
  code, or is the relationship merely the bare `calls`? `owns` needs lifecycle/storage
  ownership; `emits` an event/notification published; `reads`/`writes` data flowing
  in/out. A verb the source does not bear out (it's just a function call) is a fail.

**Output — one verdict object, nothing else:**
```json
{"key": "<the exact key from your assignment>", "verdict": "pass" | "fail",
 "failures": ["<specific, actionable refutation>", "..."]}
```
`pass` = the claim survived refutation (NOT "proven true" — only "not refuted");
**default to `fail`** for any specific citation you cannot confirm in the source.
`failures` is empty on a pass. Use the `key` **verbatim** — the CLI stamps your
verdict under it (`judgment verify-set`).

**Verdict routing**: the orchestrator pipes your verdict to `judgment verify-set`,
which stamps it by key. A `fail` triggers exactly ONE re-judgment of that cell with
your `failures` fed to the cartographer annotator as correction input — so write each
failure so a regenerating agent can act on it without re-deriving your investigation.

**Persistent failures**: if your prompt says the cell is already a re-judgment and it
still fails, your `fail` is the end of the line — be precise; the cell ships
`verify.verdict: fail` and is surfaced to the user rather than looped.

**Never modify files, and never re-author the cell.** You only judge — the annotator
is the sole producer of a cell's value. Your only output is the verdict JSON, under 4KB.
