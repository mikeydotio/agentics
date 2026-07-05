#!/usr/bin/env bash
# handle-issue test runner. Discovers and runs all test-*.sh files in this
# directory, reports pass/fail. Optional filter: `bash run-tests.sh dryrun`
# runs only tests whose filename contains 'dryrun'. Plain bash (no bats).
set -uo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILTER="${1:-}"

PASS=0
FAIL=0
FAILED=()
LOG="$(mktemp /tmp/handle-issue-run.XXXXXX)"

for test in "$TESTS_DIR"/test-*.sh; do
  name=$(basename "$test")
  if [[ -n "$FILTER" && "$name" != *"$FILTER"* ]]; then
    continue
  fi
  printf '  %-36s ' "$name"
  if bash "$test" >"$LOG" 2>&1; then
    printf 'PASS\n'
    PASS=$((PASS + 1))
  else
    printf 'FAIL\n'
    sed 's/^/      /' "$LOG"
    FAILED+=("$name")
    FAIL=$((FAIL + 1))
  fi
done

rm -f "$LOG"
echo
echo "passed: $PASS  failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo "failed tests:"
  for f in "${FAILED[@]}"; do echo "  - $f"; done
  exit 1
fi
