# atlas-ts-helper

The optional **parser ceiling** for atlas's hybrid structure extraction
(design-v2 decision 22). atlas bundles no tree-sitter and is fully functional on
its built-in **regex floor** (any language, zero dependencies). Installing this
helper raises *edge precision*: it does real scope resolution and emits a
`to` target per call site, which collapses a corpus-ambiguous callee name to a
**`resolved`** cross-module edge — a relationship the regex backend can only mark
`ambiguous`.

It currently parses **Swift**.

## Why it's separate

The atlas CLI keeps a hard **stdlib-only, zero-new-runtime-deps** invariant
(`bin/atlas-cli` is one file). tree-sitter is a compiled dependency, so the
parser ceiling lives here as its own installable that atlas discovers and
shells out to. If it is absent — or fails for any reason — atlas silently falls
back to regex. The degradation path is a tested, first-class mode.

## Install

```bash
# pipx (recommended — isolated, puts `atlas-ts-helper` on PATH)
pipx install ./plugins/atlas/helpers/ts-helper

# or a plain venv
python3 -m venv ~/.atlas-ts-helper
~/.atlas-ts-helper/bin/pip install ./plugins/atlas/helpers/ts-helper
```

atlas finds the helper by probing, in order:

1. `$ATLAS_TS_HELPER` — an explicit path to the executable (point it at the venv's
   `bin/atlas-ts-helper` if it isn't on `PATH`);
2. `atlas-ts-helper` on `PATH`;
3. `tree-sitter` on `PATH`.

Confirm it is wired up:

```bash
atlas-cli extract --backend treesitter   # backend.swift == "tree-sitter", degraded == false
```

## Contract

`atlas-ts-helper extract --root <repo-root>` reads a NUL-free, newline-delimited
list of repo-relative paths on **stdin** and emits, on **stdout**:

```jsonc
{"version": 1, "files": {"<path>": {
  "symbols": [{"name","kind","start_line","end_line","signature","visibility","qualified_name"}],
  "calls":   [{"callee","line","to": {"file","start_line"}?}]   // `to` only when scope-resolved
}}}
```

`start_line`/`end_line` are 1-indexed, end inclusive. The helper answers for the
files it can parse and omits the rest (atlas falls back to regex for those).

## Scope resolution

Without type inference, tree-sitter alone cannot resolve every method call (that
is LSP territory and explicitly out of scope). The helper does the high-value,
reliable subset:

- `receiver.method()` where `receiver` is a locally-typed variable
  (`let x = Type()` or `let x: Type`) → resolves to `Type.method`;
- `Type.method()` (static) → resolves to `Type.method`;
- bare `func()` → resolves to the unique corpus-wide free function of that name.

Anything it cannot confidently resolve is emitted **without** `to`, and atlas
resolves it by name — but only to a **type** (unique type name → `resolved`);
a bare func/method name is dropped rather than guessed (it can shadow an unseen
stdlib member), and a name with several definitions is `ambiguous`. The helper
never guesses.

## Pinned grammar (important)

`pyproject.toml` pins `tree-sitter-language-pack==0.9.1` (which bundles
`tree-sitter==0.23.2` and the Swift grammar) **exactly**. atlas computes
`span_hash` from the file bytes between the helper's `start_line`/`end_line`, so
a grammar upgrade that shifts a declaration's span boundaries would re-hash those
symbols and re-judge their cells. Treat a grammar bump like a
generator-fingerprint bump: deliberate, recorded, rolled out in lockstep.

## Versioning

The contract `version` is `1`. atlas silently rejects any other version and
falls back to regex, so atlas and every deployed helper must upgrade the contract
version together.

## Tests

`tests/test-ts-helper.sh` drives the real helper against Swift fixtures (the
resolved-edge win, symbol-id parity with regex, the backend stamp). It **skips**
when the helper/tree-sitter is not importable, so the core suite stays fast and
offline. To run it, install the helper (above) or expose a tree-sitter-capable
Python via `ATLAS_TS_HELPER_PYTHON=/path/to/python`.
