#!/usr/bin/env bash
# The worktree guard: `deploy` and `bump` must refuse to run inside a linked git
# worktree (deploys/version bumps happen later from the main working tree), while
# DEPLOYIT_ALLOW_WORKTREE=1 overrides. The guard fires before any xcodebuild /
# semver work, so a bare git repo + worktree is enough to exercise it.
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
CLI="$PLUGIN_ROOT/bin/deployit-cli"

REPO=$(mktemp -d)
STATE=$(mktemp -d)
WT=$(mktemp -d); rm -rf "$WT"
trap 'rm -rf "$REPO" "$STATE" "$WT"' EXIT

cd "$REPO"
git init -q
git config user.email "t@t"; git config user.name "t"
git commit --allow-empty -q -m "init"
git branch -M main

# Linked worktree on its own branch.
git worktree add -q "$WT" -b wt-guard-test

run() {  # run the CLI from a given dir; never abort on non-zero (we assert on JSON)
    local dir="$1"; shift
    ( cd "$dir" && DEPLOYIT_STATE_DIR="$STATE" DEPLOYIT_SKIP_INDEX_PULL=1 \
        python3 "$CLI" --plugin-root "$PLUGIN_ROOT" "$@" 2>&1 ) || true
}

assert_field() {  # $1=json $2=jqpath $3=expected $4=label
    local got; got=$(echo "$1" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("'"$2"'",""))' 2>/dev/null || true)
    [[ "$got" == "$3" ]] || { echo "FAIL: $4 (expected $2=$3, got '$got')"; echo "$1"; exit 1; }
}
refute_in_worktree() {  # $1=json $2=label — assert error is not "in_worktree"
    echo "$1" | grep -q '"error": "in_worktree"' && { echo "FAIL: $2 (unexpected in_worktree)"; echo "$1"; exit 1; } || true
}

# --- deploy from a worktree is refused ---
out=$(run "$WT" deploy --platform ios)
assert_field "$out" ok False "deploy refused in worktree (ok:false)"
assert_field "$out" error in_worktree "deploy refused in worktree (error code)"

# --- bump from a worktree is refused (before the semver-active check) ---
out=$(run "$WT" bump --component patch)
assert_field "$out" ok False "bump refused in worktree (ok:false)"
assert_field "$out" error in_worktree "bump refused in worktree (error code)"

# --- override bypasses the guard: bump proceeds past it (then fails on
#     'semver not active', which is NOT the worktree error) ---
out=$( cd "$WT" && DEPLOYIT_ALLOW_WORKTREE=1 DEPLOYIT_STATE_DIR="$STATE" \
       DEPLOYIT_SKIP_INDEX_PULL=1 python3 "$CLI" --plugin-root "$PLUGIN_ROOT" \
       bump --component patch 2>&1 || true )
refute_in_worktree "$out" "DEPLOYIT_ALLOW_WORKTREE=1 bypasses the guard"

# --- from the main working tree the guard never fires (bump reaches the
#     semver-active check, not the worktree refusal) ---
out=$(run "$REPO" bump --component patch)
refute_in_worktree "$out" "main working tree is not treated as a worktree"

echo "PASS"
