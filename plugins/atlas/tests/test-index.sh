#!/usr/bin/env bash
# Tests for `atlas-cli index rebuild` — deterministic derived INDEX assembly.

test_index_rebuild_creates_index() {
    local repo
    repo=$(create_fixture_repo)
    seed_file "$repo" "src/auth/a.txt"
    seed_file "$repo" "src/api/b.txt"
    write_module_doc "$repo" "src-auth" "src/auth" "" src/auth/a.txt
    write_module_doc "$repo" "src-api" "src/api" "" src/api/b.txt
    commit_all "$repo"
    run_atlas "$repo" ledger finalize --refresh-hashes

    run_atlas "$repo" index rebuild
    assert_exit_code 0 "$EXIT_CODE" "rebuild succeeds" || return 1
    assert_json_field "$OUTPUT" '.modules' "2" "two modules" || return 1
    assert_file_exists "$repo/docs/atlas/INDEX.md" "INDEX written" || return 1

    local index
    index=$(cat "$repo/docs/atlas/INDEX.md")
    echo "$index" | grep -q "## Routing" || { echo "    FAIL: no Routing section"; return 1; }
    echo "$index" | grep -q "docs/atlas/modules/src-auth.md" \
        || { echo "    FAIL: routing row missing"; return 1; }
    echo "$index" | grep -q "## Modules" || { echo "    FAIL: no Modules section"; return 1; }

    cleanup_fixture_repo "$repo"
}

test_index_rebuild_is_deterministic() {
    local repo
    repo=$(create_fixture_repo)
    seed_file "$repo" "src/a.txt"
    write_module_doc "$repo" "src" "src" "" src/a.txt
    commit_all "$repo"
    run_atlas "$repo" ledger finalize --refresh-hashes

    run_atlas "$repo" index rebuild
    local first
    first=$(cat "$repo/docs/atlas/INDEX.md")
    run_atlas "$repo" index rebuild
    assert_eq "$first" "$(cat "$repo/docs/atlas/INDEX.md")" \
        "byte-identical across rebuilds" || return 1

    cleanup_fixture_repo "$repo"
}

test_index_includes_overview_facts() {
    local repo
    repo=$(create_fixture_repo)
    seed_file "$repo" "src/a.txt"
    write_module_doc "$repo" "src" "src" "" src/a.txt
    write_overview_doc "$repo" "ARCHITECTURE" "src" docs/atlas/modules/src.md
    commit_all "$repo"
    run_atlas "$repo" ledger finalize --refresh-hashes

    run_atlas "$repo" index rebuild
    local index
    index=$(cat "$repo/docs/atlas/INDEX.md")
    echo "$index" | grep -q "## Key facts" \
        || { echo "    FAIL: no Key facts section"; return 1; }
    echo "$index" | grep -q "Fixture fact: everything flows through" \
        || { echo "    FAIL: fact line not extracted"; return 1; }
    echo "$index" | grep -q "docs/atlas/overview/ARCHITECTURE.md" \
        || { echo "    FAIL: overview routing row missing"; return 1; }

    cleanup_fixture_repo "$repo"
}

test_index_over_budget_refused() {
    local repo i
    repo=$(create_fixture_repo)
    local long_summary
    long_summary=$(python3 -c "print('A very long module summary sentence. ' * 12)")
    for i in $(seq -w 1 25); do
        seed_file "$repo" "src/m$i/f.txt"
        ATLAS_TEST_SUMMARY="$long_summary" \
            write_module_doc "$repo" "src-m$i" "src/m$i" "" "src/m$i/f.txt"
    done
    commit_all "$repo"
    run_atlas "$repo" ledger finalize --refresh-hashes

    run_atlas "$repo" index rebuild
    assert_exit_code 1 "$EXIT_CODE" "over-budget rebuild refused" || return 1
    assert_json_field "$OUTPUT" '.error' "index_over_budget" "error code" || return 1

    cleanup_fixture_repo "$repo"
}

test_index_no_docs_refused() {
    local repo
    repo=$(create_fixture_repo)
    seed_file "$repo" "a.txt"
    commit_all "$repo"

    run_atlas "$repo" index rebuild
    assert_exit_code 1 "$EXIT_CODE" "no docs refused" || return 1
    assert_json_field "$OUTPUT" '.error' "no_docs" "error code" || return 1

    cleanup_fixture_repo "$repo"
}
