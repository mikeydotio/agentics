#!/usr/bin/env bash
# Tests for `atlas-cli partition` — deterministic module partitioning.
#
# Default caps under test: min_files=3, max_files=15, max_bytes=120000.
# seed_file defaults to 100 bytes, so file-count caps dominate unless a test
# seeds large files explicitly.

test_partition_single_module_small_repo() {
    local repo
    repo=$(create_fixture_repo)
    for f in a b c d e; do seed_file "$repo" "src/$f.txt"; done
    commit_all "$repo"

    run_atlas "$repo" partition
    assert_exit_code 0 "$EXIT_CODE" "partition exits 0" || return 1
    assert_json_field "$OUTPUT" '.module_count' "1" "one module" || return 1
    assert_json_field "$OUTPUT" '.modules[0].id' "src" "labeled by deepest common dir" || return 1
    assert_json_field "$OUTPUT" '.modules[0].strategy' "dir" "dir strategy" || return 1
    assert_json_field "$OUTPUT" '.modules[0].files' "5" "five files" || return 1

    cleanup_fixture_repo "$repo"
}

test_partition_per_directory() {
    local repo
    repo=$(create_fixture_repo)
    for d in auth api models; do
        for f in a b c d e f; do seed_file "$repo" "src/$d/$f.txt"; done
    done
    commit_all "$repo"

    run_atlas "$repo" partition
    assert_json_field "$OUTPUT" '.module_count' "3" "three modules" || return 1
    assert_json_field "$OUTPUT" '[.modules[].id] | join(",")' "src-api,src-auth,src-models" \
        "sorted module ids" || return 1
    assert_json_field "$OUTPUT" '.modules[0].files' "6" "six files each" || return 1

    cleanup_fixture_repo "$repo"
}

test_partition_coalesce_small_siblings() {
    local repo
    repo=$(create_fixture_repo)
    for i in 01 02 03 04 05 06 07 08 09 10 11 12 13 14; do
        seed_file "$repo" "src/core/f$i.txt"
    done
    seed_file "$repo" "src/a/only.txt"
    seed_file "$repo" "src/b/only.txt"
    seed_file "$repo" "src/c/only.txt"
    commit_all "$repo"

    run_atlas "$repo" partition
    assert_json_field "$OUTPUT" '.module_count' "2" "core + coalesced misc" || return 1
    assert_json_field "$OUTPUT" '[.modules[].id] | join(",")' "src-core,src-misc" \
        "module ids" || return 1
    assert_json_field "$OUTPUT" \
        '.modules[] | select(.id == "src-misc") | .strategy' "coalesced" \
        "misc bucket strategy" || return 1
    assert_json_field "$OUTPUT" \
        '.modules[] | select(.id == "src-misc") | .files' "3" \
        "three coalesced files" || return 1

    cleanup_fixture_repo "$repo"
}

test_partition_flat_dir_stems() {
    local repo
    repo=$(create_fixture_repo)
    for f in a b c d e f; do seed_file "$repo" "src/user_$f.py"; done
    for f in a b c d e f; do seed_file "$repo" "src/auth_$f.py"; done
    for f in one two three four five; do seed_file "$repo" "src/$f.py"; done
    commit_all "$repo"

    run_atlas "$repo" partition
    assert_json_field "$OUTPUT" '.module_count' "3" "two stems + one chunk" || return 1
    assert_json_field "$OUTPUT" '[.modules[].id] | join(",")' "src-auth,src-chunk-1,src-user" \
        "stem and chunk ids" || return 1
    assert_json_field "$OUTPUT" \
        '.modules[] | select(.id == "src-user") | .strategy' "stem" \
        "stem strategy" || return 1
    assert_json_field "$OUTPUT" \
        '.modules[] | select(.id == "src-user") | .label' "src/user*" \
        "stem label" || return 1
    assert_json_field "$OUTPUT" \
        '.modules[] | select(.id == "src-chunk-1") | .files' "5" \
        "leftovers chunked" || return 1

    cleanup_fixture_repo "$repo"
}

test_partition_byte_cap_splits() {
    local repo
    repo=$(create_fixture_repo)
    seed_file "$repo" "big/alpha.txt" 70000
    seed_file "$repo" "big/beta.txt" 70000
    commit_all "$repo"

    run_atlas "$repo" partition
    assert_json_field "$OUTPUT" '.module_count' "2" "byte cap forces split" || return 1
    assert_json_field "$OUTPUT" '[.modules[].id] | join(",")' "big-chunk-1,big-chunk-2" \
        "alphabetical chunks" || return 1

    cleanup_fixture_repo "$repo"
}

test_partition_override_wins() {
    local repo
    repo=$(create_fixture_repo)
    for d in auth api models; do
        for f in a b c d e f; do seed_file "$repo" "src/$d/$f.txt"; done
    done
    write_config "$repo" <<'YAML'
modules:
  - name: authy
    globs:
      - "src/auth/**"
YAML
    commit_all "$repo"

    run_atlas "$repo" partition
    assert_json_field "$OUTPUT" '.module_count' "2" "override + remainder" || return 1
    assert_json_field "$OUTPUT" \
        '.modules[] | select(.id == "authy") | .strategy' "override" \
        "override strategy" || return 1
    assert_json_field "$OUTPUT" \
        '.modules[] | select(.id == "authy") | .files' "6" \
        "override claims auth files" || return 1
    assert_json_field "$OUTPUT" \
        '.modules[] | select(.id == "src") | .files' "12" \
        "remainder fits one module" || return 1

    cleanup_fixture_repo "$repo"
}

test_partition_root_files() {
    local repo
    repo=$(create_fixture_repo)
    for f in a b c d; do seed_file "$repo" "$f.txt"; done
    commit_all "$repo"

    run_atlas "$repo" partition
    assert_json_field "$OUTPUT" '.module_count' "1" "one root module" || return 1
    assert_json_field "$OUTPUT" '.modules[0].id' "root" "root id" || return 1

    cleanup_fixture_repo "$repo"
}

test_partition_deterministic() {
    local repo
    repo=$(create_fixture_repo)
    for d in auth api models; do
        for f in a b c d e f; do seed_file "$repo" "src/$d/$f.txt"; done
    done
    commit_all "$repo"

    run_atlas "$repo" partition
    local first="$OUTPUT"
    run_atlas "$repo" partition
    assert_eq "$first" "$OUTPUT" "byte-identical across runs" || return 1

    cleanup_fixture_repo "$repo"
}

test_partition_empty_repo() {
    local repo
    repo=$(create_fixture_repo)

    run_atlas "$repo" partition
    assert_exit_code 0 "$EXIT_CODE" "empty repo partitions fine" || return 1
    assert_json_field "$OUTPUT" '.module_count' "0" "zero modules" || return 1

    cleanup_fixture_repo "$repo"
}

test_partition_unassigned_invariant() {
    local repo
    repo=$(create_fixture_repo)
    for d in auth api; do
        for f in a b c d e f g h; do seed_file "$repo" "src/$d/$f.txt"; done
    done
    seed_file "$repo" "README.md"
    commit_all "$repo"

    run_atlas "$repo" partition
    assert_json_field "$OUTPUT" '.unassigned | length' "0" \
        "every scanned file lands in a module" || return 1
    # Cross-check: total files across modules == scan total
    local scan_total part_total
    run_atlas "$repo" scan
    scan_total=$(echo "$OUTPUT" | jq -r '.total_files')
    run_atlas "$repo" partition
    part_total=$(echo "$OUTPUT" | jq -r '[.modules[].files] | add')
    assert_eq "$scan_total" "$part_total" "module files sum to scan total" || return 1

    cleanup_fixture_repo "$repo"
}
