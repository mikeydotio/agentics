#!/usr/bin/env bash
# Shared helpers for storywork tests. Source this at the top of each
# test-*.sh. Mirrors plugins/issue/tests/lib.sh's shape (SCRIPT/FAKE_*
# constants, mk_*_repo fixture builders, assert helpers) -- see that file for
# the house style this one follows.
#
# Provides: SCRIPT (path to story.sh), FAKE_STORY (path to the fake story),
# FAKE_TMUX_DIR (dir containing the fake tmux, for PATH prepending), mk_repo
# (throwaway git repo under /tmp, NOT $TMPDIR -- see issue's lib.sh for the
# macOS Spotlight rationale), mk_dispatch_repo (a repo with a real, fetchable
# local bare origin, for driving REAL non-dry-run dispatch runs), and small
# assert helpers. Each test runs standalone under `bash test-*.sh` and exits
# non-zero on the first failed assertion.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
SCRIPT="$PLUGIN_ROOT/bin/story.sh"
FAKE_STORY="$TESTS_DIR/fakes/story"
FAKE_TMUX_DIR="$TESTS_DIR/fakes"

# Point the helper at the fake story for every test by default.
export STORY_BIN="$FAKE_STORY"
export GIT_TERMINAL_PROMPT=0

_TMP_REPOS=()
_cleanup() { local d; for d in "${_TMP_REPOS[@]:-}"; do [ -n "$d" ] && rm -rf "$d"; done; }
trap _cleanup EXIT

# mk_repo — create a plain temp git repo (no remote), echo its path. Enough
# for tests that never touch a real (non-dry-run) dispatch/complete run.
mk_repo() {
  local dir
  dir="$(mktemp -d /tmp/storywork-test.XXXXXX)"
  _TMP_REPOS+=("$dir")
  (
    cd "$dir" || exit 1
    git init -q -b main
    git config user.email t@t; git config user.name t
  ) >/dev/null 2>&1
  printf '%s' "$dir"
}

# mk_dispatch_repo — build a repo for REAL (non-dry-run) `dispatch`/`complete`
# tests, echo its path. Mirrors plugins/issue/tests/lib.sh's mk_dispatch_repo:
# a LOCAL bare origin with one commit already pushed to main and origin/HEAD
# set, so `origin/main` fetches and `default_branch()` resolves to "main"
# purely offline (no real network).
mk_dispatch_repo() {
  local origdir origin repo
  origdir="$(mktemp -d /tmp/storywork-dispatch-origin.XXXXXX)"
  mkdir -p "$origdir/fake"
  origin="$origdir/fake/repo.git"
  git init -q --bare -b main "$origin"
  repo="$(mktemp -d /tmp/storywork-dispatch.XXXXXX)"
  _TMP_REPOS+=("$repo" "$origdir")
  (
    cd "$repo" || exit 1
    git init -q -b main
    git config user.email t@t; git config user.name t
    git remote add origin "$origin"
    echo a > f; git add f; git commit -qm init
    git push -qu origin main
    git remote set-head origin main >/dev/null 2>&1 || true
  ) >/dev/null 2>&1
  printf '%s' "$repo"
}

# mk_stale_dispatch_repo — build a repo reproducing the issue #107 condition
# (agentics' `issue` plugin sibling defect class) for story.sh `dispatch`
# tests, echo its path: a LOCAL bare origin that a SEPARATE clone advances
# past THIS repo's local main — which is never pulled, so it permanently
# LAGS origin/main. No pre-made worktree-* branches, so a dispatch test is
# free to create its own for any story id without colliding. `dispatch`
# itself does the only fetch this repo ever performs; the caller can
# independently verify staleness via `git ls-remote origin main` (never the
# local tracking ref). Mirrors plugins/issue/tests/lib.sh's
# mk_stale_dispatch_repo byte-for-byte (renamed tmp prefixes only).
mk_stale_dispatch_repo() {
  local origdir origin remote repo
  origdir="$(mktemp -d /tmp/storywork-dispatch-stale-origin.XXXXXX)"
  mkdir -p "$origdir/fake"
  origin="$origdir/fake/repo.git"
  git init -q --bare -b main "$origin"
  repo="$(mktemp -d /tmp/storywork-dispatch-stale-local.XXXXXX)"
  remote="$(mktemp -d /tmp/storywork-dispatch-stale-remote.XXXXXX)"
  _TMP_REPOS+=("$repo" "$origdir" "$remote")
  (
    cd "$repo" || exit 1
    git init -q -b main
    git config user.email t@t; git config user.name t
    git remote add origin "$origin"
    echo a > f; git add f; git commit -qm init
    git push -qu origin main
    git remote set-head origin main >/dev/null 2>&1 || true

    # GitHub-side stand-in: a separate clone advances origin/main with a NEW
    # commit. THIS repo never pulls, so its local main permanently lags.
    git clone -q "$origin" "$remote"
    git -C "$remote" config user.email t@t; git -C "$remote" config user.name t
    echo b > "$remote/g"
    git -C "$remote" add g
    git -C "$remote" commit -qm "advance origin main"
    git -C "$remote" push -q origin main
  ) >/dev/null 2>&1
  printf '%s' "$repo"
}

# mk_stale_base_repo <story-id> — build a repo reproducing the issue #99
# condition for story.sh's `complete`, echo its path: the ONE worktree branch
# story.sh's own complete would look for (worktree-<wname>, wname resolved
# exactly as resolve_wname does) is merged into origin/main ONLY via a
# separate clone (standing in for the GitHub side), while THIS repo's local
# main never pulls, so it permanently LAGS origin/main. `git branch -d`
# refuses here (no upstream + stale local main); the delete depends on the
# freshen_base_ref + branch_is_merged -d->-D escalation story.sh shares with
# issue.sh via session.sh. Unlike issue's own mk_stale_base_repo, no second
# "legacy bare-<n>" sibling branch is needed: story.sh's complete is a
# purpose-built single-target scan (this file's header), not issue.sh's
# multi-branch collect_targets.
mk_stale_base_repo() {
  local id="$1" origdir origin remote repo wname
  origdir="$(mktemp -d /tmp/storywork-stale-origin.XXXXXX)"
  mkdir -p "$origdir/fake"
  origin="$origdir/fake/repo.git"
  git init -q --bare -b main "$origin"
  repo="$(mktemp -d /tmp/storywork-stale-local.XXXXXX)"
  remote="$(mktemp -d /tmp/storywork-stale-remote.XXXXXX)"
  _TMP_REPOS+=("$repo" "$origdir" "$remote")
  wname="$(basename "$repo" | tr -cd '[:alnum:]' | cut -c1-3 | tr '[:upper:]' '[:lower:]')-$id"
  (
    cd "$repo" || exit 1
    git init -q -b main
    git config user.email t@t; git config user.name t
    git remote add origin "$origin"
    echo a > f; git add f; git commit -qm init
    git push -qu origin main
    git remote set-head origin main >/dev/null 2>&1 || true

    # merged-on-origin worktree branch: own commit, pushed WITHOUT -u (no upstream)
    git checkout -q -b "worktree-$wname" main
    echo w > wfile; git add wfile; git commit -qm "feat: $id work"
    git push -q origin "worktree-$wname"
    git checkout -q main

    # GitHub-side stand-in: a separate clone merges the branch into main and
    # pushes, advancing origin/main. THIS repo never pulls, so local main lags.
    git clone -q "$origin" "$remote"
    git -C "$remote" config user.email t@t; git -C "$remote" config user.name t
    git -C "$remote" merge -q --no-ff "origin/worktree-$wname" -m "Merge $id"
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
