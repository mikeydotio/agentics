#!/usr/bin/env bash
# Tests for `atlas-cli init` / `atlas-cli remove` — CLAUDE.md managed block
# and .gitignore wiring.

test_init_creates_claude_md_when_missing() {
    local repo
    repo=$(create_fixture_repo)
    seed_file "$repo" "src/a.txt"
    commit_all "$repo"

    run_atlas "$repo" init
    assert_exit_code 0 "$EXIT_CODE" "init succeeds" || return 1
    assert_json_field "$OUTPUT" '.claude_md' "created" "CLAUDE.md created" || return 1
    grep -q "<!-- atlas:start -->" "$repo/CLAUDE.md" \
        || { echo "    FAIL: start marker missing"; return 1; }
    grep -q "@docs/atlas/INDEX.md" "$repo/CLAUDE.md" \
        || { echo "    FAIL: INDEX import missing"; return 1; }
    grep -q "Prefer the map to rediscovery" "$repo/CLAUDE.md" \
        || { echo "    FAIL: prefer-the-map steering missing"; return 1; }
    grep -q "^\.atlas/$" "$repo/.gitignore" \
        || { echo "    FAIL: .atlas/ gitignore entry missing"; return 1; }

    cleanup_fixture_repo "$repo"
}

test_init_appends_to_existing_claude_md() {
    local repo
    repo=$(create_fixture_repo)
    printf '# My Project\n\nExisting instructions.\n' > "$repo/CLAUDE.md"
    commit_all "$repo"

    run_atlas "$repo" init
    assert_json_field "$OUTPUT" '.claude_md' "appended" "block appended" || return 1
    grep -q "Existing instructions." "$repo/CLAUDE.md" \
        || { echo "    FAIL: existing content lost"; return 1; }
    grep -q "<!-- atlas:end -->" "$repo/CLAUDE.md" \
        || { echo "    FAIL: end marker missing"; return 1; }

    cleanup_fixture_repo "$repo"
}

test_init_is_idempotent() {
    local repo
    repo=$(create_fixture_repo)
    seed_file "$repo" "src/a.txt"
    commit_all "$repo"

    run_atlas "$repo" init
    run_atlas "$repo" init
    assert_json_field "$OUTPUT" '.claude_md' "replaced" "second init replaces" || return 1
    local starts ignores
    starts=$(grep -c "<!-- atlas:start -->" "$repo/CLAUDE.md")
    assert_eq "1" "$starts" "exactly one block" || return 1
    ignores=$(grep -c "^\.atlas/$" "$repo/.gitignore")
    assert_eq "1" "$ignores" "exactly one gitignore entry" || return 1

    cleanup_fixture_repo "$repo"
}

test_remove_deletes_block_only() {
    local repo
    repo=$(create_fixture_repo)
    printf '# My Project\n\nKeep me.\n' > "$repo/CLAUDE.md"
    commit_all "$repo"
    run_atlas "$repo" init

    run_atlas "$repo" remove
    assert_exit_code 0 "$EXIT_CODE" "remove succeeds" || return 1
    assert_json_field "$OUTPUT" '.claude_md' "removed" "block removed" || return 1
    if grep -q "atlas:start" "$repo/CLAUDE.md"; then
        echo "    FAIL: block still present"
        return 1
    fi
    grep -q "Keep me." "$repo/CLAUDE.md" \
        || { echo "    FAIL: unrelated content lost"; return 1; }

    cleanup_fixture_repo "$repo"
}

test_remove_when_absent_is_noop() {
    local repo
    repo=$(create_fixture_repo)
    seed_file "$repo" "src/a.txt"
    commit_all "$repo"

    run_atlas "$repo" remove
    assert_exit_code 0 "$EXIT_CODE" "remove without block is ok" || return 1
    assert_json_field "$OUTPUT" '.claude_md' "absent" "reports absent" || return 1

    cleanup_fixture_repo "$repo"
}
