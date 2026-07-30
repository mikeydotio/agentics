# Deterministic Pre-Checks

Objective, scriptable checks that run BEFORE the LLM evaluator — cheaper and more reliable than
LLM judgment for anything mechanically verifiable. Fully implemented by `bin/forge-prechecks.sh`
(this doc used to restate the script's own logic in prose, which silently drifted from the
real implementation; it now only says what the script checks and how to read its output).

## Running it

```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/forge-prechecks.sh --story-id <id> --mapping .forge/plan-mapping.json
```

## What it checks (in order)

1. **Tests** — auto-detects the project's test command (`npm test` / `pytest` / `cargo test` /
   `make test` / `tests/run-tests.sh`, in that priority order); no detected command is a skip, not
   a failure. A failure is re-run once — if it passes on retry it's reported as `passed: true` with
   a `flaky_tests` note, not a failure.
2. **Linter** — auto-detects ESLint / `tsc --noEmit` / ruff / clippy from project files present; no
   detected linter is a skip.
3. **Stub grep** — scans only files touched by the current diff (staged + unstaged) for
   whole-word `TODO`/`FIXME`/`HACK` and a small set of language-specific "intentionally
   unimplemented" idioms (`NotImplementedError`, `unimplemented!`, `throw new Error(...not
   implemented)`, `fatalError(...not implemented)`, `preconditionFailure(...not implemented)`).
   Deliberately **not** bare `stub`/`placeholder`/`XXX` substrings (those false-positived on
   legitimate code, e.g. a form field's `placeholder` prop).
4. **Scope** — compares the diff's touched files against `plan-mapping.json`'s `files_expected`
   for `--story-id`. **Always passes** — `unexpected_modified` is a warning surfaced for the
   evaluator to judge, never an automatic failure (generators sometimes legitimately touch shared
   files).

## Reading the output

```json
{"ok": true, "all_passed": true|false, "checks": [{"check": "tests|linter|stub_grep|scope", "passed": ..., "details": "...", ...}], "display": "..."}
```

- `all_passed: true` → proceed to the evaluator (Step 5 of `references/execution-loop.md`).
- `all_passed: false` → find the failing check(s) in `checks[]`, store its `details` as a storyhook
  comment, and go to retry (`references/execution-loop.md`'s Retry step) — do not invoke the
  evaluator on a failing pre-check.
- A check's own `flaky_tests` (tests) or `unexpected_modified` (scope) fields are informational,
  not failures — they don't block proceeding to the evaluator.
