#!/usr/bin/env bash
# Test runner for semver user-defined hooks
# Creates throwaway git repos in /tmp, exercises hook behaviors
#
# Usage: bash tests/run-tests.sh [test-file-pattern]
#   e.g., bash tests/run-tests.sh discovery    # runs only test-hook-discovery.sh
#         bash tests/run-tests.sh              # runs all tests

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load helpers
source "$TESTS_DIR/helpers/setup.sh"

# --- State ---
TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_SKIP=0
ALL_FAILURES=()

FILTER="${1:-}"

# --- Runner ---

run_test_file() {
    local test_file="$1"
    local file_name
    file_name=$(basename "$test_file")
    local file_pass=0
    local file_fail=0

    echo ""
    echo "=== $file_name ==="

    # Source the test file to load test functions
    source "$test_file"

    # Discover test functions (test_*)
    local funcs
    funcs=$(declare -F | awk '{print $3}' | grep '^test_' | sort)

    for func in $funcs; do
        # Run each test in a subshell to isolate state
        local output
        set +e
        output=$( set -e; "$func" 2>&1 )
        local ec=$?
        set -e

        if [ $ec -eq 0 ]; then
            echo "  PASS  $func"
            file_pass=$((file_pass + 1))
        else
            echo "  FAIL  $func"
            if [ -n "$output" ]; then
                echo "$output" | sed 's/^/        /'
            fi
            file_fail=$((file_fail + 1))
            ALL_FAILURES+=("${file_name}::${func}")
        fi
    done

    # Unset test functions to prevent cross-file contamination
    for func in $funcs; do
        unset -f "$func" 2>/dev/null || true
    done

    TOTAL_PASS=$((TOTAL_PASS + file_pass))
    TOTAL_FAIL=$((TOTAL_FAIL + file_fail))
}

# --- Main ---

echo "semver hook tests"
echo "=================="

# Check prerequisites
if ! command -v jq &>/dev/null; then
    echo "ERROR: jq is required but not installed"
    exit 1
fi

if ! command -v git &>/dev/null; then
    echo "ERROR: git is required but not installed"
    exit 1
fi

# Find and run test files
for test_file in "$TESTS_DIR"/test-*.sh; do
    [ -f "$test_file" ] || continue

    if [ -n "$FILTER" ]; then
        if [[ "$test_file" != *"$FILTER"* ]]; then
            TOTAL_SKIP=$((TOTAL_SKIP + 1))
            continue
        fi
    fi

    run_test_file "$test_file"
done

# --- Report ---

echo ""
echo "=================="
echo "Results: $TOTAL_PASS passed, $TOTAL_FAIL failed"
if [ $TOTAL_SKIP -gt 0 ]; then
    echo "  ($TOTAL_SKIP test files skipped by filter)"
fi

if [ ${#ALL_FAILURES[@]} -gt 0 ]; then
    echo ""
    echo "Failures:"
    for f in "${ALL_FAILURES[@]}"; do
        echo "  - $f"
    done
fi

echo ""
exit $TOTAL_FAIL
