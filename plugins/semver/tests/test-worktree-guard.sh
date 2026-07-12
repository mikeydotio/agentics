#!/usr/bin/env bash
# Tests for the linked-worktree guard: mutating semver ops must refuse to run
# inside a git worktree (versioning happens later from the main working tree),
# while read-only reporting stays allowed and SEMVER_ALLOW_WORKTREE=1 overrides.
#
# NOTE: refusal exits the CLI with code 1, and run-tests.sh runs each test under
# `set -e`, so every CLI capture is wrapped in `set +e` … `set -e` (the same
# convention test-set.sh uses for its error cases).

# --- Fixtures ---

# Create a linked worktree of $repo on a fresh branch; echo its path.
# The path matches the /tmp/semver-test-* glob so cleanup_test_repo removes it.
_add_worktree() {
    local repo="$1" wt
    wt=$(mktemp -d "/tmp/semver-test-XXXXXX")
    rm -rf "$wt"
    git -C "$repo" worktree add -q "$wt" -b "wt-$(basename "$wt")" >/dev/null 2>&1
    echo "$wt"
}

# --- Tests ---

test_bump_execute_refused_in_worktree() {
    local repo; repo=$(create_test_repo)
    local wt; wt=$(_add_worktree "$repo")
    trap "cleanup_test_repo '$repo'; cleanup_test_repo '$wt'" RETURN
    add_feature_commit "$repo" "feat: a feature"

    local head_before tags_before
    head_before=$(git -C "$wt" rev-parse HEAD)
    tags_before=$(git -C "$repo" tag | sort | tr '\n' ' ')

    local out
    set +e
    out=$(cd "$wt" && "$CLI" bump execute patch --plugin-root /x 2>&1)
    set -e

    assert_json_field "$out" ".ok" "false" "bump execute refused in worktree" &&
    assert_json_field "$out" ".error" "in_worktree" "error code is in_worktree" &&
    assert_eq "$head_before" "$(git -C "$wt" rev-parse HEAD)" "no commit made in worktree" &&
    assert_eq "$tags_before" "$(git -C "$repo" tag | sort | tr '\n' ' ')" "no tag created"
}

test_bump_run_refused_in_worktree() {
    local repo; repo=$(create_test_repo)
    local wt; wt=$(_add_worktree "$repo")
    trap "cleanup_test_repo '$repo'; cleanup_test_repo '$wt'" RETURN
    add_feature_commit "$repo" "feat: a feature"

    local out
    set +e
    out=$(cd "$wt" && "$CLI" bump run patch --plugin-root /x 2>&1)
    set -e
    assert_json_field "$out" ".ok" "false" "bump run refused in worktree" &&
    assert_json_field "$out" ".error" "in_worktree" "error code is in_worktree"
}

test_set_refused_in_worktree() {
    local repo; repo=$(create_test_repo)
    local wt; wt=$(_add_worktree "$repo")
    trap "cleanup_test_repo '$repo'; cleanup_test_repo '$wt'" RETURN

    local out
    set +e
    out=$(cd "$wt" && "$CLI" set run 2.0.0 --plugin-root /x 2>&1)
    set -e
    assert_json_field "$out" ".ok" "false" "set refused in worktree" &&
    assert_json_field "$out" ".error" "in_worktree" "error code is in_worktree"
}

test_readonly_current_allowed_in_worktree() {
    local repo; repo=$(create_test_repo)
    local wt; wt=$(_add_worktree "$repo")
    trap "cleanup_test_repo '$repo'; cleanup_test_repo '$wt'" RETURN

    local out
    set +e
    out=$(cd "$wt" && "$CLI" current 2>&1)
    set -e
    assert_json_field "$out" ".ok" "true" "current still works in worktree" &&
    assert_json_field "$out" ".version" "v1.0.0" "current reports the version"
}

test_readonly_validate_allowed_in_worktree() {
    local repo; repo=$(create_test_repo)
    local wt; wt=$(_add_worktree "$repo")
    trap "cleanup_test_repo '$repo'; cleanup_test_repo '$wt'" RETURN

    # validate must not be blocked by the worktree guard (error != in_worktree).
    local out
    set +e
    out=$(cd "$wt" && "$CLI" validate 2>&1)
    set -e
    assert_ne "in_worktree" "$(echo "$out" | jq -r '.error // empty')" \
        "validate is not blocked by the worktree guard"
}

test_override_bypasses_worktree_guard() {
    local repo; repo=$(create_test_repo)
    local wt; wt=$(_add_worktree "$repo")
    trap "cleanup_test_repo '$repo'; cleanup_test_repo '$wt'" RETURN
    add_feature_commit "$repo" "feat: a feature"

    # With the override set, the guard is bypassed: the command proceeds past it
    # (it may then hit an unrelated state like wrong_branch, but never in_worktree).
    local out
    set +e
    out=$(cd "$wt" && SEMVER_ALLOW_WORKTREE=1 "$CLI" bump run patch --plugin-root /x 2>&1)
    set -e
    assert_ne "in_worktree" "$(echo "$out" | jq -r '.error // empty')" \
        "SEMVER_ALLOW_WORKTREE=1 bypasses the worktree guard"
}

test_main_tree_bump_not_blocked() {
    local repo; repo=$(create_test_repo)
    trap "cleanup_test_repo '$repo'" RETURN
    add_feature_commit "$repo" "feat: a feature"

    # From the main working tree the guard never fires — a normal bump executes.
    local out
    set +e
    out=$(cd "$repo" && "$CLI" bump run patch --plugin-root /x 2>&1)
    set -e
    assert_ne "in_worktree" "$(echo "$out" | jq -r '.error // empty')" \
        "main working tree is never treated as a worktree" &&
    assert_json_field "$out" ".executed" "true" "bump executes from the main tree"
}
