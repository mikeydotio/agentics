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

# mk_complete_repo — build a realistic repo for `complete` tests, echo its path.
# Uses a LOCAL bare origin named fake/repo.git so (a) owner/repo resolves to
# fake/repo -> prefix "rep" (wname "rep-77"), and (b) remote-branch checks and
# `push --delete` run OFFLINE and deterministically. Issue under test is 77; the
# repo holds every guard-rail case:
#   worktree-rep-77   merged local branch                 -> deletable
#   worktree-77       unmerged local branch (own commit)  -> skipped (unmerged)
#   fix/thing-61      merged PR head, pushed to origin     -> deletable local+remote
#   .claude/worktrees/rep-77   clean detached worktree     -> removable
#   .claude/worktrees/77       LOCKED detached worktree    -> skipped (locked)
# Pair with FAKE_GH_CLOSED_BY_PRS='[{"number":61}]' so PR #61 (MERGED, head
# fix/thing-61) is discovered as the issue's closing PR.
mk_complete_repo() {
  local origdir origin repo
  origdir="$(mktemp -d /tmp/issue-origin.XXXXXX)"
  mkdir -p "$origdir/fake"
  origin="$origdir/fake/repo.git"
  git init -q --bare -b main "$origin"
  repo="$(mktemp -d /tmp/issue-complete.XXXXXX)"
  _TMP_REPOS+=("$repo" "$origdir")
  (
    cd "$repo" || exit 1
    git init -q -b main
    git config user.email t@t; git config user.name t
    git remote add origin "$origin"
    echo a > f; git add f; git commit -qm init
    git push -qu origin main
    git remote set-head origin main >/dev/null 2>&1 || true
    git branch worktree-rep-77                         # merged -> deletable
    git branch worktree-77
    git checkout -q worktree-77; echo b > g; git add g; git commit -qm b; git checkout -q main
    git branch fix/thing-61                            # merged PR head
    git push -q origin fix/thing-61
    git worktree add -q --detach "$repo/.claude/worktrees/rep-77"        # clean -> removable
    git worktree add -q --lock --detach "$repo/.claude/worktrees/77"     # locked -> skipped
  ) >/dev/null 2>&1
  printf '%s' "$repo"
}

# mk_stale_base_repo — build a repo reproducing the issue #99 condition and echo
# its path. The issue under test is 88 (owner/repo fake/repo -> prefix "rep" ->
# wname "rep-88"). A worktree branch is merged into origin/main on a SEPARATE
# clone (standing in for the GitHub side) while THIS repo's local main is never
# pulled, so local main permanently LAGS origin/main:
#   worktree-rep-88   own commit, merged only on origin/main, NO upstream
#                     -> pre-fix: mis-skipped `local, unmerged`; post-fix: deletable
#   worktree-88       own commit, never merged -> genuinely unmerged (negative guard)
# Leave FAKE_GH_CLOSED_BY_PRS unset (default []) so only the worktree-branch path
# is exercised. `git branch -d worktree-rep-88` REFUSES here (no upstream + stale
# local main), so the delete depends on the -d->-D escalation.
mk_stale_base_repo() {
  local origdir origin remote repo
  origdir="$(mktemp -d /tmp/issue-stale-origin.XXXXXX)"
  mkdir -p "$origdir/fake"
  origin="$origdir/fake/repo.git"
  git init -q --bare -b main "$origin"
  repo="$(mktemp -d /tmp/issue-stale-local.XXXXXX)"
  remote="$(mktemp -d /tmp/issue-stale-remote.XXXXXX)"
  _TMP_REPOS+=("$repo" "$origdir" "$remote")
  (
    # local clone where `issue complete` runs; its main starts at init
    cd "$repo" || exit 1
    git init -q -b main
    git config user.email t@t; git config user.name t
    git remote add origin "$origin"
    echo a > f; git add f; git commit -qm init
    git push -qu origin main
    git remote set-head origin main >/dev/null 2>&1 || true

    # merged-on-origin worktree branch: own commit, pushed WITHOUT -u (no upstream)
    git checkout -q -b worktree-rep-88 main
    echo w > wfile; git add wfile; git commit -qm "feat: issue 88 work"
    git push -q origin worktree-rep-88
    git checkout -q main

    # genuinely-unmerged worktree branch: own commit, never merged (guard)
    git checkout -q -b worktree-88 main
    echo u > ufile; git add ufile; git commit -qm "wip: issue 88 unmerged"
    git checkout -q main

    # GitHub-side stand-in: a separate clone merges worktree-rep-88 into main and
    # pushes, advancing origin/main. THIS repo never pulls, so its local main lags.
    git clone -q "$origin" "$remote"
    git -C "$remote" config user.email t@t; git -C "$remote" config user.name t
    git -C "$remote" merge -q --no-ff origin/worktree-rep-88 -m "Merge PR #88"
    git -C "$remote" push -q origin main
  ) >/dev/null 2>&1
  printf '%s' "$repo"
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
