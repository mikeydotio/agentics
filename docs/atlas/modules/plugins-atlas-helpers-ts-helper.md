---
module: plugins/atlas/helpers/ts-helper
summary: "Standalone tree-sitter Swift extractor — atlas's optional resolved-edge parser ceiling over its regex floor."
read_when: "Changing the tree-sitter Swift extractor or its stdout JSON contract"
sources:
  - path: plugins/atlas/helpers/ts-helper/README.md
    blob: 510c6654b7aeec889822f3dd4b512de6f30a7f31
  - path: plugins/atlas/helpers/ts-helper/atlas_ts_helper.py
    blob: c59bc22a16028ef22993c9eadfecd26ee8d0aa85
  - path: plugins/atlas/helpers/ts-helper/pyproject.toml
    blob: 0cb6343334d59ae18c94e50501788a1a20a60be9
generator: cartographer/4
baseline: cb09ceb006e3fb4759a91d64d9e6655e67d04bf7
---

# Module: plugins/atlas/helpers/ts-helper

## Purpose

This package is atlas's optional "parser ceiling": a standalone, pipx-installable tree-sitter Swift extractor that atlas-cli shells out to in place of its zero-dependency regex floor. It exists as its own installable — rather than a dependency folded into atlas-cli — because atlas-cli keeps a hard stdlib-only, zero-new-runtime-deps invariant and tree-sitter is a compiled dependency. Its sole job is emitting atlas's versioned structure-JSON contract with real scope-resolved call edges (`to`), letting atlas mark a call `resolved` instead of `ambiguous`; if this module vanished, atlas would keep working unchanged on regex alone, just with lower cross-module edge precision.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `extract` | def | `plugins/atlas/helpers/ts-helper/atlas_ts_helper.py:307` | Two-pass corpus scan of `paths`; returns the {version, files} contract dict with per-file symbols/calls; silently skips unparseable files. |
| `main` | def | `plugins/atlas/helpers/ts-helper/atlas_ts_helper.py:351` | CLI entry: reads newline-delimited stdin paths, prints extract()'s JSON + trailing newline to stdout; returns 2 on a bad subcommand. |
| `visit` | def | `plugins/atlas/helpers/ts-helper/atlas_ts_helper.py:154` | Recursive closure in _collect_symbols walking the AST, appending type/func declarations it finds to `result.symbols`. |
| `visit` | def | `plugins/atlas/helpers/ts-helper/atlas_ts_helper.py:222` | Recursive closure in _local_var_types walking one function body, building the local `var -> TypeName` map it returns. |
| `visit` | def | `plugins/atlas/helpers/ts-helper/atlas_ts_helper.py:293` | Recursive closure in _collect_calls walking the AST, invoking _emit_call per call_expression while threading local var types. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `_line` | def | `plugins/atlas/helpers/ts-helper/atlas_ts_helper.py:82` | Single funnel for the 1-indexed declaration line: feeds symbol start_line (plugins/atlas/helpers/ts-helper/atlas_ts_helper.py:163,172), the type_members/free_funcs resolution tables (plugins/atlas/helpers/ts-helper/atlas_ts_helper.py:177,180), and call-site line (plugins/atlas/helpers/ts-helper/atlas_ts_helper.py:277). The docstring at plugins/atlas/helpers/ts-helper/atlas_ts_helper.py:150-153 states these must agree so atlas's loc_to_id join lands even when a leading attribute/modifier sits on its own line — every call site routing through this one function is what keeps that invariant true. |

## Relationships

## Type notes

`_FileResult` (plugins/atlas/helpers/ts-helper/atlas_ts_helper.py:134) is a plain `__slots__` accumulator for one file's symbols/calls; `extract()` allocates one per parseable path and mutates it in place across both passes (plugins/atlas/helpers/ts-helper/atlas_ts_helper.py:324-335).
`extract()` (plugins/atlas/helpers/ts-helper/atlas_ts_helper.py:295) runs two full passes over `paths`: pass 1 parses every file and builds the corpus-wide `type_members`/`free_funcs` tables before pass 2 resolves any call, so call resolution depends on the whole requested corpus, not just the calling file (plugins/atlas/helpers/ts-helper/atlas_ts_helper.py:326-335).
No state persists across invocations: each `main()` run is a single stdin-to-stdout batch (plugins/atlas/helpers/ts-helper/atlas_ts_helper.py:342-358).

## External deps

- argparse — imported
- json — imported
- os — imported
- sys — imported
- tree_sitter_language_pack — imported

## Gotchas

- `_constructor_type`'s callee-is-a-bare-identifier heuristic can misclassify an ordinary function call as a type constructor, but the docstring notes this is deliberate: downstream resolution only matches real type tables, so the false positive costs nothing (plugins/atlas/helpers/ts-helper/atlas_ts_helper.py:193-196).
- The tree-sitter grammar is pinned to an exact version (`tree-sitter-language-pack==0.9.1`) because atlas re-hashes each symbol's span from raw file bytes; a grammar upgrade that shifts declaration boundaries silently re-hashes and re-judges every affected cell, so a bump must be deliberate and rolled out in lockstep (plugins/atlas/helpers/ts-helper/pyproject.toml:11-18, plugins/atlas/helpers/ts-helper/README.md:75-82).
- The contract `version` must stay `1` in lockstep with atlas: a mismatched version is silently rejected (atlas falls back to regex rather than erroring) (plugins/atlas/helpers/ts-helper/atlas_ts_helper.py:22-24).
