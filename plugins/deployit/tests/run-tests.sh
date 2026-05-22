#!/usr/bin/env bash
# deployit test runner. Discovers and runs all test-*.sh files in this directory,
# reports pass/fail. Optional filter: `bash run-tests.sh backend` runs only
# tests whose filename contains 'backend'.

set -uo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILTER="${1:-}"

PASS=0
FAIL=0
FAILED=()

for test in "$TESTS_DIR"/test-*.sh; do
    name=$(basename "$test")
    if [[ -n "$FILTER" && "$name" != *"$FILTER"* ]]; then
        continue
    fi
    printf '  %-40s ' "$name"
    if bash "$test" >/tmp/deployit-test.log 2>&1; then
        printf 'PASS\n'
        ((PASS++))
    else
        printf 'FAIL\n'
        sed 's/^/      /' /tmp/deployit-test.log
        FAILED+=("$name")
        ((FAIL++))
    fi
done

echo
echo "passed: $PASS  failed: $FAIL"
if (( FAIL > 0 )); then
    echo "failed tests:"
    for f in "${FAILED[@]}"; do echo "  - $f"; done
    exit 1
fi
