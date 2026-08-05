#!/usr/bin/env bash
# deployit test runner. Discovers and runs all test-*.sh files in this directory,
# reports pass/fail. Optional filter: `bash run-tests.sh backend` runs only
# tests whose filename contains 'backend'.

set -uo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILTER="${1:-}"

# Per-run scratch log. This used to be the fixed path /tmp/deployit-test.log,
# which two concurrent runs interleave into — and concurrent runs are routine
# here (the global pre-push hook runs `make test`, and worktree sessions run
# their own). No assertion reads this file, so a verdict was never wrong because
# of it, but the diagnostic block printed under a FAIL could belong to a
# different run, which is a trap for anyone diagnosing from the output. AGE-21's
# filed root cause was inferred from exactly such a block. `/tmp` rather than
# $TMPDIR is deliberate: Spotlight indexes $TMPDIR (see CLAUDE.md).
LOG=$(mktemp /tmp/deployit-test.XXXXXX) || { echo "cannot create temp log"; exit 1; }
DIAG_DIR=$(mktemp -d /tmp/deployit-diag.XXXXXX) || { echo "cannot create diag dir"; exit 1; }
trap 'rm -f "$LOG"; rm -rf "$DIAG_DIR"' EXIT

# How many lines of a failing test's output to repeat in the trailing summary.
# Bounded on purpose: the whole point is to fit inside a reader's tail window, so
# one verbose failure must not push the others back out of it.
DIAG_LINES=12

PASS=0
FAIL=0
FAILED=()

for test in "$TESTS_DIR"/test-*.sh; do
    name=$(basename "$test")
    if [[ -n "$FILTER" && "$name" != *"$FILTER"* ]]; then
        continue
    fi
    printf '  %-40s ' "$name"
    if bash "$test" >"$LOG" 2>&1; then
        printf 'PASS\n'
        ((PASS++))
    else
        # Record the exit status, not just the fact of failure. 141 is SIGPIPE
        # (128+13) and is the unique signature of an early-exit consumer killing
        # a still-writing producer under `pipefail` — the AGE-21 defect class.
        # Naming it here means a future instance is diagnosed from the log
        # rather than guessed at. Known limit: it only shows when the status
        # propagates to the script's exit, NOT when a caller swallows it with
        # `|| { ... }` — which is precisely how test-cli-rm.sh:119 hid it.
        rc=$?
        printf 'FAIL (exit %d)\n' "$rc"
        sed 's/^/      /' "$LOG"
        FAILED+=("$name (exit $rc)")
        # Keep a bounded copy for the trailing summary. The inline block above is
        # printed where the failure happened, which for a mid-alphabet file sits
        # ~40 lines above the summary — right at the edge of the `tail -40` the
        # pre-push hook shows. Whether a red gate explains itself would otherwise
        # depend on the failing file's ALPHABETICAL POSITION (AGE-35).
        head -n "$DIAG_LINES" "$LOG" > "$DIAG_DIR/$name.diag"
        ((FAIL++))
    fi
done

echo
echo "passed: $PASS  failed: $FAIL"
if (( FAIL > 0 )); then
    echo "failed tests:"
    for f in "${FAILED[@]}"; do echo "  - $f"; done
    echo
    echo "why they failed (first $DIAG_LINES lines each; full output inline above):"
    for f in "${FAILED[@]}"; do
        n="${f%% (exit *}"
        echo "  --- $n"
        if [[ -s "$DIAG_DIR/$n.diag" ]]; then
            sed 's/^/      /' "$DIAG_DIR/$n.diag"
        else
            echo "      (the test produced NO output — it failed without saying why;"
            echo "       that is the AGE-35 defect class, see tests/deployit-capture-diagnostics.sh)"
        fi
    done
    exit 1
fi
