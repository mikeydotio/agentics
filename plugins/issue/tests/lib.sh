#!/usr/bin/env bash
# Shared helpers for issue tests. Source this at the top of each test-*.sh.
#
# Provides: SCRIPT (path to issue.sh), FAKE_GH (path to the fake gh),
# mk_repo (create a throwaway git repo under /tmp — NOT $TMPDIR, which macOS
# Spotlight indexes and can stall file-intensive tests), and small assert
# helpers. Each test runs standalone under `bash test-*.sh` and exits non-zero
# on the first failed assertion.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
SCRIPT="$PLUGIN_ROOT/bin/issue.sh"
FAKE_GH="$TESTS_DIR/fakes/gh"

# Point the helper at the fake gh for every test by default.
export ISSUE_GH_BIN="$FAKE_GH"

_TMP_REPOS=()
_cleanup() { local d; for d in "${_TMP_REPOS[@]:-}"; do [ -n "$d" ] && rm -rf "$d"; done; }
trap _cleanup EXIT

# mk_repo [origin-url] — create a temp git repo (default origin
# https://github.com/fake/repo.git) and echo its path.
mk_repo() {
  local origin="${1:-https://github.com/fake/repo.git}"
  local dir
  dir="$(mktemp -d /tmp/issue-test.XXXXXX)"
  _TMP_REPOS+=("$dir")
  (
    cd "$dir" || exit 1
    git init -q
    [ "$origin" != "-" ] && git remote add origin "$origin"
  ) >/dev/null 2>&1
  printf '%s' "$dir"
}

_FAILED=0
fail_test() { printf 'FAIL: %s\n' "$1" >&2; _FAILED=1; }

# assert_eq <actual> <expected> <label>
assert_eq() {
  if [ "$1" != "$2" ]; then
    fail_test "$3 — expected [$2], got [$1]"
  fi
}

# assert_contains <haystack> <needle> <label>
assert_contains() {
  case "$1" in
    *"$2"*) : ;;
    *) fail_test "$3 — [$1] does not contain [$2]" ;;
  esac
}

# assert_not_contains <haystack> <needle> <label>
assert_not_contains() {
  case "$1" in
    *"$2"*) fail_test "$3 — [$1] unexpectedly contains [$2]" ;;
    *) : ;;
  esac
}

# jqf <json> <filter> — run a jq filter, echo the raw result.
jqf() { printf '%s' "$1" | jq -r "$2"; }

finish() {
  if [ "$_FAILED" -eq 0 ]; then echo "PASS"; exit 0; else exit 1; fi
}
