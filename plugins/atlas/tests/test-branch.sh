#!/usr/bin/env bash
# Tests for `atlas-cli branch ensure` — isolating map work on an atlas/* branch.

test_branch_ensure_creates_atlas_branch() {
    local repo
    repo=$(create_fixture_repo)
    seed_file "$repo" "src/a.txt"
    commit_all "$repo" "base"
    local base_branch head_sha
    base_branch=$(git -C "$repo" symbolic-ref --short HEAD)
    head_sha=$(git -C "$repo" rev-parse HEAD)

    run_atlas "$repo" branch ensure --op map
    assert_exit_code 0 "$EXIT_CODE" "branch ensure succeeds" || return 1
    assert_json_field "$OUTPUT" '.ok' "true" "ok" || return 1
    assert_json_field "$OUTPUT" '.created' "true" "created" || return 1
    assert_json_field "$OUTPUT" '.base_branch' "$base_branch" "base_branch" || return 1
    assert_json_field "$OUTPUT" '.base_sha' "$head_sha" "base_sha" || return 1
    assert_json_field "$OUTPUT" '.detached' "false" "detached" || return 1

    local branch
    branch=$(echo "$OUTPUT" | jq -r '.branch')
    case "$branch" in
        atlas/map-*) ;;
        *) echo "    FAIL: branch '$branch' is not atlas/map-*"; return 1 ;;
    esac
    # HEAD actually moved onto the new branch.
    assert_eq "$branch" "$(git -C "$repo" symbolic-ref --short HEAD)" \
        "HEAD on new branch" || return 1

    cleanup_fixture_repo "$repo"
}

test_branch_ensure_idempotent_on_atlas_branch() {
    local repo
    repo=$(create_fixture_repo)
    seed_file "$repo" "src/a.txt"
    commit_all "$repo" "base"

    run_atlas "$repo" branch ensure --op map
    local first
    first=$(echo "$OUTPUT" | jq -r '.branch')

    # Already on the atlas branch → no-op, same branch, no -2 suffix.
    run_atlas "$repo" branch ensure --op map
    assert_exit_code 0 "$EXIT_CODE" "second ensure ok" || return 1
    assert_json_field "$OUTPUT" '.created' "false" "created false on re-entry" || return 1
    assert_json_field "$OUTPUT" '.branch' "$first" "same branch" || return 1

    cleanup_fixture_repo "$repo"
}

test_branch_ensure_collision_suffix() {
    local repo
    repo=$(create_fixture_repo)
    seed_file "$repo" "src/a.txt"
    commit_all "$repo" "base"
    # Squat the natural name (matches the CLI's 7-char sha prefix exactly).
    local short
    short=$(git -C "$repo" rev-parse HEAD | cut -c1-7)
    git -C "$repo" branch "atlas/map-$short"

    run_atlas "$repo" branch ensure --op map
    assert_exit_code 0 "$EXIT_CODE" "ensure ok" || return 1
    assert_json_field "$OUTPUT" '.created' "true" "created" || return 1
    assert_json_field "$OUTPUT" '.branch' "atlas/map-$short-2" "suffixed branch" || return 1

    cleanup_fixture_repo "$repo"
}

test_branch_ensure_detached_head() {
    local repo
    repo=$(create_fixture_repo)
    seed_file "$repo" "src/a.txt"
    commit_all "$repo" "base"
    git -C "$repo" checkout -q --detach

    run_atlas "$repo" branch ensure --op update
    assert_exit_code 0 "$EXIT_CODE" "ensure ok from detached HEAD" || return 1
    assert_json_field "$OUTPUT" '.created' "true" "created" || return 1
    assert_json_field "$OUTPUT" '.detached' "true" "detached" || return 1
    assert_json_field "$OUTPUT" '.base_branch' "null" "base_branch null" || return 1

    local branch
    branch=$(echo "$OUTPUT" | jq -r '.branch')
    case "$branch" in
        atlas/update-*) ;;
        *) echo "    FAIL: branch '$branch' is not atlas/update-*"; return 1 ;;
    esac
    assert_eq "$branch" "$(git -C "$repo" symbolic-ref --short HEAD)" \
        "HEAD on new branch" || return 1

    cleanup_fixture_repo "$repo"
}

test_branch_ensure_refuses_mid_merge() {
    local repo
    repo=$(create_fixture_repo)
    seed_file "$repo" "f.txt"
    commit_all "$repo" "base"
    git -C "$repo" checkout -q -b feature
    echo "feature change" > "$repo/f.txt"
    git -C "$repo" add -A && git -C "$repo" commit -q -m "feature"
    git -C "$repo" checkout -q -
    echo "main change" > "$repo/f.txt"
    git -C "$repo" add -A && git -C "$repo" commit -q -m "main"
    set +e
    git -C "$repo" merge feature -q > /dev/null 2>&1   # conflicts; MERGE_HEAD exists
    set -e

    run_atlas "$repo" branch ensure --op map
    assert_exit_code 1 "$EXIT_CODE" "mid-merge branch refused" || return 1
    assert_json_field "$OUTPUT" '.error' "mid_merge" "error code" || return 1

    cleanup_fixture_repo "$repo"
}

test_branch_ensure_no_commits() {
    local repo
    repo=$(create_fixture_repo)   # git init, but no commit yet

    run_atlas "$repo" branch ensure --op map
    assert_exit_code 1 "$EXIT_CODE" "unborn HEAD refused" || return 1
    assert_json_field "$OUTPUT" '.error' "no_commits" "error code" || return 1

    cleanup_fixture_repo "$repo"
}

test_branch_ensure_carries_dirty_tree() {
    local repo
    repo=$(create_fixture_repo)
    seed_file "$repo" "src/a.txt"
    commit_all "$repo" "base"
    # Uncommitted work the user (or the about-to-run mappers) has in flight.
    echo "wip" > "$repo/wip.txt"

    run_atlas "$repo" branch ensure --op map
    assert_exit_code 0 "$EXIT_CODE" "ensure ok with dirty tree" || return 1
    # The untracked file survives onto the new branch.
    assert_file_exists "$repo/wip.txt" "dirty file carried over" || return 1
    git -C "$repo" status --porcelain | grep -q "wip.txt" \
        || { echo "    FAIL: dirty file lost after branch switch"; return 1; }

    cleanup_fixture_repo "$repo"
}

test_branch_router_passthrough() {
    local repo
    repo=$(create_fixture_repo)
    seed_file "$repo" "src/a.txt"
    commit_all "$repo" "base"

    # The router (what /atlas calls) must reach the new subcommand.
    local out
    out=$(cd "$repo" && bash "$PLUGIN_ROOT/bin/atlas-router.sh" branch ensure --op map 2>/dev/null)
    assert_json_field "$out" '.ok' "true" "router ok" || return 1
    assert_json_field "$out" '.created' "true" "router created" || return 1

    cleanup_fixture_repo "$repo"
}
