# Deterministic Pre-Checks

Pre-check layer that runs BEFORE the LLM evaluator. More reliable and cheaper than LLM judgment for objective checks.

## Check Order

1. **Test suite**
2. **Linter / type checker**
3. **Stub grep**
4. **Generator scope check**

## 1. Test Suite

Run the project's test command (auto-detected or from config):

```bash
# Auto-detect: check for package.json scripts, Makefile, pytest, cargo test, etc.
npm test          # Node.js
pytest            # Python
cargo test        # Rust
make test         # Makefile
./tests/run-tests.sh  # Custom
```

### Flaky Test Handling

If a test fails:
1. Re-run the specific failing test ONCE
2. If it passes on re-run → flag as **potentially flaky**
   - Record test name in handoff.md
   - Proceed to next check (do NOT count as failure)
3. If it fails again → **genuine failure**
   - Store failure details as storyhook comment
   - Go to retry

## 2. Linter / Type Checker

Run project-appropriate linting:

```bash
# Auto-detect based on project files
npx eslint --no-warn .   # Node.js with ESLint
npx tsc --noEmit          # TypeScript
ruff check .              # Python
cargo clippy              # Rust
```

If linter fails → store feedback as storyhook comment → go to retry.

## 3. Stub Grep

Scan for incomplete implementations:

```bash
# Search for common stub patterns in modified files only
git diff --name-only | xargs grep -n \
  -e 'TODO' -e 'FIXME' -e 'HACK' -e 'XXX' \
  -e 'not implemented' -e 'stub' -e 'placeholder' \
  -e 'throw new Error.*not implemented' \
  -e 'pass  # TODO' \
  -e 'unimplemented!' \
  2>/dev/null
```

If stubs found → store as storyhook comment → go to retry.

**Note**: Only scan files in the current `git diff`, not the entire codebase. Existing TODOs in unmodified files are not the generator's responsibility.

## 4. Generator Scope Check

Compare modified files against expected files:

```bash
git diff --name-only
```

Compare against `plan-mapping.json`'s `files_expected` for the current story.

- **Expected files modified**: Good — generator stayed in scope
- **Unexpected files modified**: Log warning in handoff.md with the unexpected file list
  - **Warning only, not automatic failure** — generators sometimes need to touch shared files (imports, exports, type definitions)
  - The evaluator will review whether unexpected modifications are appropriate

## Check Results

Each check produces a structured result:

```json
{
  "check": "tests|linter|stub_grep|scope",
  "passed": true|false,
  "details": "Description of what failed",
  "flaky_tests": ["test_name"]  // only for test check
}
```

All checks must pass before invoking the evaluator. Any failure short-circuits to retry (except flaky tests, which are flagged and allowed to proceed).
