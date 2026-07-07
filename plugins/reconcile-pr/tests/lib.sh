#!/usr/bin/env bash
# Shared helpers for reconcile-pr tests. Source this at the top of each test-*.sh.
#
# Provides: SCRIPT (path to reconcile-pr.sh), FAKE_GH (path to the fake gh),
# reconcile_fixture (build a local bare-origin repo + a fresh user checkout with
# a rebase-conflicting / clean / already-current PR — all offline, no network),
# rp (run the script with cwd=checkout), and small assert helpers. Temp trees go
# under /tmp — NOT $TMPDIR, which macOS Spotlight indexes and can stall
# file-intensive git tests. Each test runs standalone under `bash test-*.sh` and
# exits non-zero on the first failed assertion.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
SCRIPT="$PLUGIN_ROOT/bin/reconcile-pr.sh"
FAKE_GH="$TESTS_DIR/fakes/gh"

# Every test drives the script against the fake gh by default.
export RECONCILE_PR_GH_BIN="$FAKE_GH"

_TMP_DIRS=()
_cleanup() {
  local d
  for d in "${_TMP_DIRS[@]:-}"; do
    # Detach any leftover worktrees before removing the tree.
    [ -n "$d" ] && [ -d "$d" ] && rm -rf "$d" 2>/dev/null
  done
}
trap _cleanup EXIT

_git() { git -c init.defaultBranch=main -c user.email=t@t -c user.name=test "$@"; }

# reconcile_fixture <conflict|clean|current> — build the fixture and echo the
# path to a fresh user checkout (a clone of the bare origin) to run the script in.
# The PR branch is always `pr-branch` onto base `main`.
reconcile_fixture() {
  local kind="${1:-conflict}" root origin seed
  root="$(mktemp -d /tmp/reconcile-pr-test.XXXXXX)"
  _TMP_DIRS+=("$root")
  origin="$root/origin.git"
  _git init --bare -q --initial-branch=main "$origin"

  seed="$root/seed"
  _git clone -q "$origin" "$seed"
  (
    cd "$seed" || exit 1
    printf 'shared line\nkeep-a\n' > file.txt
    printf 'unrelated\n' > other.txt
    _git add -A; _git commit -qm "seed base"; _git push -q -u origin main

    _git switch -q -c pr-branch
    case "$kind" in
      conflict) printf 'PR value\nkeep-a\n' > file.txt ;;          # same line as main → conflict
      clean)    printf 'pr feature\n' > feature.txt ;;             # disjoint file → clean rebase
      current)  printf 'pr feature\n' > feature.txt ;;             # main won't advance → already current
    esac
    _git add -A; _git commit -qm "pr: change"; _git push -q -u origin pr-branch

    _git switch -q main
    case "$kind" in
      conflict) printf 'MAIN value\nkeep-a\n' > file.txt; _git add -A; _git commit -qm "main: change same line"; _git push -q origin main ;;
      clean)    printf 'shared line\nkeep-a\nmain-added\n' > file.txt; _git add -A; _git commit -qm "main: distinct region"; _git push -q origin main ;;
      current)  : ;;  # leave main at seed → origin/main is an ancestor of origin/pr-branch
    esac
  ) >/dev/null 2>&1

  local checkout="$root/work"
  _git clone -q "$origin" "$checkout"
  ( cd "$checkout" && _git config user.email t@t && _git config user.name test ) >/dev/null 2>&1
  printf '%s' "$checkout"
}

# fixture_origin <checkout> — echo the path to that fixture's bare origin repo.
fixture_origin() { printf '%s' "$(cd "$1/.." && pwd)/origin.git"; }
# fixture_seed <checkout> — echo the path to the seed clone (for out-of-band pushes).
fixture_seed()   { printf '%s' "$(cd "$1/.." && pwd)/seed"; }
# wt_path <checkout> <pr> — echo the reconcile worktree path.
wt_path() { printf '%s/.claude/worktrees/reconcile-pr/%s/worktree' "$1" "$2"; }

# rp <checkout> <args...> — run the script with cwd=checkout, echo stdout.
rp() { local co="$1"; shift; ( cd "$co" && bash "$SCRIPT" "$@" ); }

_FAILED=0
fail_test() { printf 'FAIL: %s\n' "$1" >&2; _FAILED=1; }

assert_eq() { [ "$1" = "$2" ] || fail_test "$3 — expected [$2], got [$1]"; }
assert_ne() { [ "$1" != "$2" ] || fail_test "$3 — expected NOT [$2], got [$1]"; }
assert_contains() {
  case "$1" in *"$2"*) : ;; *) fail_test "$3 — [$1] does not contain [$2]" ;; esac
}
assert_not_contains() {
  case "$1" in *"$2"*) fail_test "$3 — [$1] unexpectedly contains [$2]" ;; *) : ;; esac
}

# jqf <json> <filter> — run a jq filter, echo the raw result.
jqf() { printf '%s' "$1" | jq -r "$2" 2>/dev/null; }

finish() { if [ "$_FAILED" -eq 0 ]; then echo "PASS"; exit 0; else exit 1; fi; }
