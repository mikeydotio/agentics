#!/usr/bin/env bash
# Tests for `atlas-cli covers` — the per-file coverage/freshness probe over the
# committed ledger (paths + recorded source blobs). Pure read; no LLM, no
# history walk.

test_covers_reports_mapped_and_fresh() {
    local repo
    repo=$(create_fixture_repo)
    seed_file "$repo" "src/a.txt"
    write_module_doc "$repo" "src" "src" "" src/a.txt
    commit_all "$repo"
    run_atlas "$repo" ledger finalize --refresh-hashes

    run_atlas "$repo" covers src/a.txt
    assert_exit_code 0 "$EXIT_CODE" "covers succeeds" || return 1
    assert_json_field "$OUTPUT" '.results[0].mapped' "true" "file is mapped" || return 1
    assert_json_field "$OUTPUT" '.results[0].doc' "docs/atlas/modules/src.md" \
        "reports owning doc" || return 1
    assert_json_field "$OUTPUT" '.results[0].module' "src" "reports module label" || return 1
    assert_json_field "$OUTPUT" '.results[0].fresh' "true" \
        "unchanged file is fresh" || return 1

    cleanup_fixture_repo "$repo"
}

test_covers_reports_stale_after_edit() {
    local repo
    repo=$(create_fixture_repo)
    seed_file "$repo" "src/a.txt"
    write_module_doc "$repo" "src" "src" "" src/a.txt
    commit_all "$repo"
    run_atlas "$repo" ledger finalize --refresh-hashes

    # Change the source in the working tree — its blob now diverges from the
    # blob the ledger recorded, so coverage is stale.
    printf 'a changed line\n' >> "$repo/src/a.txt"

    run_atlas "$repo" covers src/a.txt
    assert_json_field "$OUTPUT" '.results[0].mapped' "true" "still mapped" || return 1
    assert_json_field "$OUTPUT" '.results[0].fresh' "false" \
        "edited file is stale" || return 1

    cleanup_fixture_repo "$repo"
}

test_covers_unmapped_path() {
    local repo
    repo=$(create_fixture_repo)
    seed_file "$repo" "src/a.txt"
    write_module_doc "$repo" "src" "src" "" src/a.txt
    commit_all "$repo"
    run_atlas "$repo" ledger finalize --refresh-hashes

    run_atlas "$repo" covers not/mapped.txt
    assert_exit_code 0 "$EXIT_CODE" "covers succeeds on unmapped path" || return 1
    assert_json_field "$OUTPUT" '.results[0].mapped' "false" "unmapped path" || return 1

    cleanup_fixture_repo "$repo"
}

test_covers_multiple_paths_in_one_call() {
    local repo
    repo=$(create_fixture_repo)
    seed_file "$repo" "src/a.txt"
    seed_file "$repo" "src/b.txt"
    write_module_doc "$repo" "src" "src" "" src/a.txt
    commit_all "$repo"
    run_atlas "$repo" ledger finalize --refresh-hashes

    run_atlas "$repo" covers src/a.txt src/b.txt
    assert_json_field "$OUTPUT" '.results | length' "2" "two results returned" || return 1
    assert_json_field "$OUTPUT" '.results[0].mapped' "true" "first mapped" || return 1
    assert_json_field "$OUTPUT" '.results[1].mapped' "false" \
        "second (unowned) unmapped" || return 1

    cleanup_fixture_repo "$repo"
}

test_covers_path_outside_repo_is_flagged() {
    local repo
    repo=$(create_fixture_repo)
    seed_file "$repo" "src/a.txt"
    write_module_doc "$repo" "src" "src" "" src/a.txt
    commit_all "$repo"
    run_atlas "$repo" ledger finalize --refresh-hashes

    run_atlas "$repo" covers ../escapes.txt
    assert_exit_code 0 "$EXIT_CODE" "covers succeeds" || return 1
    assert_json_field "$OUTPUT" '.results[0].mapped' "false" "outside path unmapped" || return 1
    assert_json_field "$OUTPUT" '.results[0].note' "path is outside the repository" \
        "outside path is noted" || return 1

    cleanup_fixture_repo "$repo"
}

test_covers_fails_without_a_map() {
    local repo
    repo=$(create_fixture_repo)
    seed_file "$repo" "src/a.txt"
    commit_all "$repo"

    run_atlas "$repo" covers src/a.txt
    assert_exit_code 1 "$EXIT_CODE" "covers fails when unmapped repo" || return 1
    assert_json_field "$OUTPUT" '.error' "no_map" "reports no_map error" || return 1

    cleanup_fixture_repo "$repo"
}

test_covers_fails_outside_git_repo() {
    local dir
    dir=$(mktemp -d "/tmp/atlas-tests-notgit-XXXXXX")

    run_atlas "$dir" covers anything.txt
    assert_exit_code 1 "$EXIT_CODE" "covers fails outside a git repo" || return 1
    assert_json_field "$OUTPUT" '.error' "not_a_git_repo" "reports not_a_git_repo" || return 1

    cleanup_fixture_repo "$dir"
}
