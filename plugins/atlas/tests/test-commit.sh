#!/usr/bin/env bash
# Tests for `atlas-cli commit` — guarded, pathspec-scoped map commits.

_commit_fixture() {
    local repo
    repo=$(create_fixture_repo)
    seed_file "$repo" "src/a.txt"
    write_module_doc "$repo" "src" "src" "" src/a.txt
    commit_all "$repo"
    run_atlas "$repo" ledger finalize --refresh-hashes
    run_atlas "$repo" index rebuild
    echo "$repo"
}

test_commit_scopes_to_map_paths() {
    local repo
    repo=$(_commit_fixture)
    # The user has unrelated staged work that atlas must never swallow.
    seed_file "$repo" "src/user-wip.txt"
    git -C "$repo" add src/user-wip.txt

    run_atlas "$repo" commit --message "docs(atlas): test map commit"
    assert_exit_code 0 "$EXIT_CODE" "commit succeeds" || return 1
    assert_json_field "$OUTPUT" '.committed' "true" "committed" || return 1

    local committed_paths
    committed_paths=$(git -C "$repo" show --name-only --format="" HEAD)
    if echo "$committed_paths" | grep -q "user-wip"; then
        echo "    FAIL: atlas commit swallowed the user's staged work"
        return 1
    fi
    echo "$committed_paths" | grep -q "docs/atlas/INDEX.md" \
        || { echo "    FAIL: map files not in the commit"; return 1; }
    # User's staged file is still staged, untouched.
    git -C "$repo" diff --cached --name-only | grep -q "user-wip" \
        || { echo "    FAIL: user's staged file lost from the index"; return 1; }

    cleanup_fixture_repo "$repo"
}

test_commit_refuses_mid_merge() {
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
    mkdir -p "$repo/docs/atlas"
    echo "x" > "$repo/docs/atlas/INDEX.md"

    run_atlas "$repo" commit --message "docs(atlas): should refuse"
    assert_exit_code 1 "$EXIT_CODE" "mid-merge commit refused" || return 1
    assert_json_field "$OUTPUT" '.error' "mid_merge" "error code" || return 1

    cleanup_fixture_repo "$repo"
}

test_commit_nothing_to_commit() {
    local repo
    repo=$(_commit_fixture)
    run_atlas "$repo" commit --message "docs(atlas): first"
    run_atlas "$repo" commit --message "docs(atlas): second"
    assert_exit_code 0 "$EXIT_CODE" "no-op commit is ok" || return 1
    assert_json_field "$OUTPUT" '.committed' "false" "nothing committed" || return 1

    cleanup_fixture_repo "$repo"
}

test_commit_also_paths() {
    local repo
    repo=$(_commit_fixture)
    echo "# CLAUDE" > "$repo/CLAUDE.md"

    run_atlas "$repo" commit --message "docs(atlas): with claude-md" --also CLAUDE.md
    assert_json_field "$OUTPUT" '.committed' "true" "committed" || return 1
    git -C "$repo" show --name-only --format="" HEAD | grep -q "CLAUDE.md" \
        || { echo "    FAIL: --also path not committed"; return 1; }

    cleanup_fixture_repo "$repo"
}
