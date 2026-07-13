#!/usr/bin/env bash
# Shared helpers for the rca plain-bash test suite (reconcile-pr harness pattern).
# Source this at the top of every test-*.sh. Each test runs standalone under
# `bash test-*.sh` and exits non-zero on the first failed assertion.
#
# Temp trees live under /private/tmp — NOT $TMPDIR, which macOS Spotlight indexes
# and which stalls file-intensive git suites (per this Mac's CLAUDE.md).
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
BIN="$PLUGIN_ROOT/bin"
FAKES="$TESTS_DIR/fakes"

SCAFFOLD="$BIN/rca-scaffold.sh"
STATUS="$BIN/rca-status.sh"
STACK="$BIN/rca-stack.sh"
REPRO="$BIN/rca-repro.sh"
WORKTREE="$BIN/rca-worktree.sh"
BISECT="$BIN/rca-bisect.sh"
FORENSICS="$BIN/rca-forensics.sh"
HOTSPOTS="$BIN/rca-hotspots.sh"

_TMP_DIRS=()
_cleanup() {
  local d
  for d in "${_TMP_DIRS[@]:-}"; do
    [ -n "$d" ] && [ -d "$d" ] || continue
    [ -d "$d/.git" ] && git -C "$d" worktree prune >/dev/null 2>&1 || true
    rm -rf "$d" 2>/dev/null || true
  done
}
trap _cleanup EXIT

# git with fixed identity + no signing, so tests never touch the user's config.
_git() { git -c init.defaultBranch=main -c user.email=t@t -c user.name=test -c commit.gpgsign=false "$@"; }

# mktmp — a fresh temp dir under /private/tmp, auto-removed at exit.
mktmp() { local d; d="$(mktemp -d "/private/tmp/rca-tests-$$.XXXXXX")"; _TMP_DIRS+=("$d"); printf '%s' "$d"; }

# make_fixture_repo — echo the path to a fresh git repo with one seed commit.
make_fixture_repo() {
  local r; r="$(mktmp)"
  ( cd "$r" && _git init -q . && printf 'seed\n' > README.md && _git add -A && _git commit -qm "seed" ) >/dev/null 2>&1
  printf '%s' "$r"
}

# plant_regression <repo> — build linear history where a tracked check.sh flips
# from `exit 0` to `exit 1` at one "bad" commit, with good commits before and
# more commits after. Echo "<good_sha> <bad_tip_sha> <planted_sha>".
plant_regression() {
  local r="$1" good bad planted
  (
    cd "$r"
    printf '#!/bin/sh\nexit 0\n' > check.sh; chmod +x check.sh
    _git add -A; _git commit -qm "add check (good)"
    echo a >> data.txt; _git add -A; _git commit -qm "good 1"
    echo b >> data.txt; _git add -A; _git commit -qm "good 2"
  ) >/dev/null 2>&1
  good=$(_git -C "$r" rev-parse HEAD)
  (
    cd "$r"
    printf '#!/bin/sh\nexit 1\n' > check.sh
    echo c >> data.txt; _git add -A; _git commit -qm "BAD: flip check.sh to exit 1"
  ) >/dev/null 2>&1
  planted=$(_git -C "$r" rev-parse HEAD)
  (
    cd "$r"
    echo d >> data.txt; _git add -A; _git commit -qm "after 1"
    echo e >> data.txt; _git add -A; _git commit -qm "after 2"
  ) >/dev/null 2>&1
  bad=$(_git -C "$r" rev-parse HEAD)
  printf '%s %s %s' "$good" "$bad" "$planted"
}

# flaky_cmd_dir — echo a dir with flaky.sh that fails on every 2nd invocation
# (counter file in cwd). Run it with --dir=<that dir> so the counter persists.
flaky_cmd_dir() {
  local d; d="$(mktmp)"
  cat > "$d/flaky.sh" <<'EOF'
#!/usr/bin/env bash
c="$PWD/.flaky-counter"
n=0; [ -f "$c" ] && n=$(cat "$c")
n=$((n + 1)); printf '%s' "$n" > "$c"
if [ $((n % 2)) -eq 0 ]; then echo "fail run $n"; exit 1; else echo "pass run $n"; exit 0; fi
EOF
  chmod +x "$d/flaky.sh"
  printf '%s' "$d"
}

# ---- assertions -------------------------------------------------------------
_FAILED=0
fail_test() { printf 'FAIL: %s\n' "$1" >&2; _FAILED=1; }
assert_eq() { [ "$1" = "$2" ] || fail_test "${3:-assert_eq} — expected [$2], got [$1]"; }
assert_ne() { [ "$1" != "$2" ] || fail_test "${3:-assert_ne} — expected NOT [$2], got [$1]"; }
assert_contains() { case "$1" in *"$2"*) : ;; *) fail_test "${3:-assert_contains} — [$1] lacks [$2]" ;; esac; }
assert_not_contains() { case "$1" in *"$2"*) fail_test "${3:-assert_not_contains} — [$1] unexpectedly has [$2]" ;; *) : ;; esac; }
# assert_json <json> <jq-filter> [msg] — filter must be truthy under `jq -e`.
assert_json() { printf '%s' "$1" | jq -e "$2" >/dev/null 2>&1 || fail_test "${3:-assert_json} — jq -e failed: $2 (on: $(printf '%s' "$1" | head -c 200))"; }
# jqf <json> <filter> — echo the raw jq result.
jqf() { printf '%s' "$1" | jq -r "$2" 2>/dev/null; }

finish() { if [ "$_FAILED" -eq 0 ]; then echo "PASS"; exit 0; else exit 1; fi; }
