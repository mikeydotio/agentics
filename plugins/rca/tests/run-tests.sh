#!/usr/bin/env bash
# rca test runner. Discovers and runs every test-*.sh in this directory, reports
# pass/fail, exits non-zero if any failed. Optional filter: `bash run-tests.sh
# worktree` runs only tests whose filename contains 'worktree'. Plain bash (no
# bats) so it always runs as part of the pre-push `make test` gate.
set -uo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILTER="${1:-}"

command -v jq >/dev/null 2>&1 || { echo "jq is required to run the rca test suite" >&2; exit 1; }

PASS=0
FAIL=0
FAILED=()
LOG="$(mktemp /private/tmp/rca-run.XXXXXX)"
trap 'rm -f "$LOG"' EXIT

for test in "$TESTS_DIR"/test-*.sh; do
  name=$(basename "$test")
  if [ -n "$FILTER" ] && [ "$name" = "${name#*"$FILTER"}" ]; then
    continue
  fi
  printf '  %-32s ' "$name"
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

echo
echo "passed: $PASS  failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo "failed tests:"
  for f in "${FAILED[@]}"; do echo "  - $f"; done
  exit 1
fi
