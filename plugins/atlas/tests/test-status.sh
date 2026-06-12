#!/usr/bin/env bash
# Tests for `atlas-cli status` — staleness tier computation and drift cache.

# Five-module fixture so tier percentage boundaries are easy to hit:
# 1/5 = 20% (T1), 2/5 = 40% (T2), 3/5 = 60% (T3).
_status_fixture() {
    local repo i
    repo=$(create_fixture_repo)
    for i in 1 2 3 4 5; do
        seed_file "$repo" "src/m$i/f.txt"
        write_module_doc "$repo" "src-m$i" "src/m$i" "" "src/m$i/f.txt"
    done
    commit_all "$repo"
    run_atlas "$repo" ledger finalize --refresh-hashes
    run_atlas "$repo" index rebuild
    git -C "$repo" add -A
    git -C "$repo" commit -q -m "map"
    echo "$repo"
}

test_status_unmapped_repo() {
    local repo
    repo=$(create_fixture_repo)
    seed_file "$repo" "a.txt"
    commit_all "$repo"

    run_atlas "$repo" status
    assert_exit_code 0 "$EXIT_CODE" "status exits 0" || return 1
    assert_json_field "$OUTPUT" '.mapped' "false" "not mapped" || return 1
    assert_json_field "$OUTPUT" '.tier' "0" "tier 0" || return 1

    cleanup_fixture_repo "$repo"
}

test_status_t0_clean() {
    local repo
    repo=$(_status_fixture)

    run_atlas "$repo" status
    assert_json_field "$OUTPUT" '.mapped' "true" "mapped" || return 1
    assert_json_field "$OUTPUT" '.tier' "0" "clean map is tier 0" || return 1

    cleanup_fixture_repo "$repo"
}

test_status_t1_one_stale_doc() {
    local repo
    repo=$(_status_fixture)
    echo "// changed" >> "$repo/src/m1/f.txt"

    run_atlas "$repo" status
    assert_json_field "$OUTPUT" '.tier' "1" "20% stale is tier 1" || return 1
    if ! echo "$OUTPUT" | jq -r '.message' | grep -q "src-m1"; then
        echo "    FAIL: message should name the stale module"
        echo "      message: $(echo "$OUTPUT" | jq -r '.message')"
        return 1
    fi

    cleanup_fixture_repo "$repo"
}

test_status_t2_quarter_stale() {
    local repo
    repo=$(_status_fixture)
    echo "// changed" >> "$repo/src/m1/f.txt"
    echo "// changed" >> "$repo/src/m2/f.txt"

    run_atlas "$repo" status
    assert_json_field "$OUTPUT" '.tier' "2" "40% stale is tier 2" || return 1
    if ! echo "$OUTPUT" | jq -r '.message' | grep -q "/atlas update"; then
        echo "    FAIL: tier 2 message should recommend /atlas update"
        return 1
    fi

    cleanup_fixture_repo "$repo"
}

test_status_t3_half_stale() {
    local repo
    repo=$(_status_fixture)
    echo "// changed" >> "$repo/src/m1/f.txt"
    echo "// changed" >> "$repo/src/m2/f.txt"
    echo "// changed" >> "$repo/src/m3/f.txt"

    run_atlas "$repo" status
    assert_json_field "$OUTPUT" '.tier' "3" "60% stale is tier 3" || return 1
    if ! echo "$OUTPUT" | jq -r '.message' | grep -qi "disregard"; then
        echo "    FAIL: tier 3 message should tell agents to disregard the map"
        return 1
    fi

    cleanup_fixture_repo "$repo"
}

test_status_t3_conflict_markers() {
    local repo
    repo=$(_status_fixture)
    printf '<<<<<<< HEAD\nconflict\n=======\nother\n>>>>>>> branch\n' \
        >> "$repo/docs/atlas/modules/src-m1.md"

    run_atlas "$repo" status
    assert_json_field "$OUTPUT" '.tier' "3" "conflict markers force tier 3" || return 1

    cleanup_fixture_repo "$repo"
}

test_status_second_run_cached() {
    local repo
    repo=$(_status_fixture)

    run_atlas "$repo" status
    assert_json_field "$OUTPUT" '.cached' "false" "first run computes" || return 1
    run_atlas "$repo" status
    assert_json_field "$OUTPUT" '.cached' "true" "second run hits drift cache" || return 1
    assert_json_field "$OUTPUT" '.tier' "0" "cached result preserved" || return 1

    cleanup_fixture_repo "$repo"
}

test_status_cache_invalidated_by_edit() {
    local repo
    repo=$(_status_fixture)

    run_atlas "$repo" status
    run_atlas "$repo" status
    assert_json_field "$OUTPUT" '.cached' "true" "cache warm" || return 1
    echo "// changed" >> "$repo/src/m1/f.txt"
    run_atlas "$repo" status
    assert_json_field "$OUTPUT" '.cached' "false" "edit invalidates cache" || return 1
    assert_json_field "$OUTPUT" '.tier' "1" "fresh computation" || return 1

    cleanup_fixture_repo "$repo"
}

test_status_for_hook_is_trimmed() {
    local repo
    repo=$(_status_fixture)
    echo "// changed" >> "$repo/src/m1/f.txt"

    run_atlas "$repo" status --for-hook
    assert_json_field "$OUTPUT" 'has("tier") and has("message") and has("mapped")' "true" \
        "hook shape has tier/message/mapped" || return 1
    assert_json_field "$OUTPUT" 'has("files") or has("stale_docs") or has("summary")' "false" \
        "hook shape is trimmed" || return 1

    cleanup_fixture_repo "$repo"
}
