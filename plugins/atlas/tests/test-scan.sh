#!/usr/bin/env bash
# Tests for `atlas-cli scan` — mappable file enumeration.

test_scan_lists_tracked_sorted() {
    local repo
    repo=$(create_fixture_repo)
    seed_file "$repo" "b.txt"
    seed_file "$repo" "a.txt"
    seed_file "$repo" "c/d.txt"
    commit_all "$repo"

    run_atlas "$repo" scan
    assert_exit_code 0 "$EXIT_CODE" "scan exits 0" || return 1
    assert_json_field "$OUTPUT" '.ok' "true" "ok is true" || return 1
    assert_json_field "$OUTPUT" '.total_files' "3" "three files" || return 1
    assert_json_field "$OUTPUT" '[.files[].path] | join(",")' "a.txt,b.txt,c/d.txt" \
        "paths sorted" || return 1

    cleanup_fixture_repo "$repo"
}

test_scan_includes_untracked_not_ignored() {
    local repo
    repo=$(create_fixture_repo)
    seed_file "$repo" "a.txt"
    commit_all "$repo"
    seed_file "$repo" "new-untracked.txt"

    run_atlas "$repo" scan
    assert_json_contains "$OUTPUT" '[.files[].path]' "new-untracked.txt" \
        "untracked file included" || return 1

    cleanup_fixture_repo "$repo"
}

test_scan_respects_gitignore() {
    local repo
    repo=$(create_fixture_repo)
    seed_file "$repo" "a.txt"
    echo "secret.txt" > "$repo/.gitignore"
    commit_all "$repo"
    seed_file "$repo" "secret.txt"

    run_atlas "$repo" scan
    assert_json_not_contains "$OUTPUT" '[.files[].path]' "secret.txt" \
        "gitignored file excluded" || return 1
    assert_json_contains "$OUTPUT" '[.files[].path]' ".gitignore" \
        ".gitignore itself is a mappable text file" || return 1

    cleanup_fixture_repo "$repo"
}

test_scan_default_excludes() {
    local repo
    repo=$(create_fixture_repo)
    seed_file "$repo" "src/main.swift"
    seed_file "$repo" "package-lock.json"
    seed_file "$repo" "assets/img.png"
    seed_file "$repo" "dist/app.min.js"
    commit_all "$repo"

    run_atlas "$repo" scan
    assert_json_field "$OUTPUT" '.total_files' "1" "only the source file survives" || return 1
    assert_json_not_contains "$OUTPUT" '[.files[].path]' "package-lock.json" \
        "lockfile excluded" || return 1
    assert_json_not_contains "$OUTPUT" '[.files[].path]' "assets/img.png" \
        "image excluded" || return 1
    assert_json_not_contains "$OUTPUT" '[.files[].path]' "dist/app.min.js" \
        "minified excluded" || return 1

    cleanup_fixture_repo "$repo"
}

test_scan_binary_sniff() {
    local repo
    repo=$(create_fixture_repo)
    seed_file "$repo" "a.txt"
    printf 'ab\0cd' > "$repo/blob.dat"
    commit_all "$repo"

    run_atlas "$repo" scan
    assert_json_not_contains "$OUTPUT" '[.files[].path]' "blob.dat" \
        "NUL-containing file excluded" || return 1

    cleanup_fixture_repo "$repo"
}

test_scan_excludes_atlas_dirs() {
    local repo
    repo=$(create_fixture_repo)
    seed_file "$repo" "a.txt"
    seed_file "$repo" "docs/atlas/INDEX.md"
    seed_file "$repo" ".atlas/drift-cache.json"
    commit_all "$repo"

    run_atlas "$repo" scan
    assert_json_field "$OUTPUT" '.total_files' "1" "atlas dirs never mapped" || return 1

    cleanup_fixture_repo "$repo"
}

test_scan_config_exclude() {
    local repo
    repo=$(create_fixture_repo)
    seed_file "$repo" "src/a.txt"
    seed_file "$repo" "vendor/lib.js"
    write_config "$repo" <<'YAML'
exclude:
  - "vendor/**"
YAML
    commit_all "$repo"

    run_atlas "$repo" scan
    assert_json_not_contains "$OUTPUT" '[.files[].path]' "vendor/lib.js" \
        "config exclude honored" || return 1
    assert_json_contains "$OUTPUT" '[.files[].path]' "src/a.txt" \
        "non-excluded file present" || return 1

    cleanup_fixture_repo "$repo"
}

test_scan_config_include_narrows() {
    local repo
    repo=$(create_fixture_repo)
    seed_file "$repo" "src/a.txt"
    seed_file "$repo" "tools/b.txt"
    write_config "$repo" <<'YAML'
include:
  - "src/**"
YAML
    commit_all "$repo"

    run_atlas "$repo" scan
    assert_json_field "$OUTPUT" '.total_files' "1" "include narrows scope" || return 1
    assert_json_contains "$OUTPUT" '[.files[].path]' "src/a.txt" \
        "included file present" || return 1

    cleanup_fixture_repo "$repo"
}

test_scan_ceiling_exceeded() {
    local repo
    repo=$(create_fixture_repo)
    seed_file "$repo" "a.txt"
    seed_file "$repo" "b.txt"
    seed_file "$repo" "c.txt"
    write_config "$repo" <<'YAML'
max_files: 2
YAML
    commit_all "$repo"

    run_atlas "$repo" scan
    assert_exit_code 1 "$EXIT_CODE" "ceiling refusal exits 1" || return 1
    assert_json_field "$OUTPUT" '.ok' "false" "ok false" || return 1
    assert_json_field "$OUTPUT" '.error' "ceiling_exceeded" "error code" || return 1
    assert_json_field "$OUTPUT" '.total_files' "3" "reports actual count" || return 1

    cleanup_fixture_repo "$repo"
}

test_scan_not_a_git_repo() {
    local dir
    dir=$(mktemp -d "/tmp/atlas-tests-XXXXXX")
    seed_file "$dir" "a.txt"

    run_atlas "$dir" scan
    assert_exit_code 1 "$EXIT_CODE" "non-git exits 1" || return 1
    assert_json_field "$OUTPUT" '.error' "not_a_git_repo" "error code" || return 1

    cleanup_fixture_repo "$dir"
}

test_scan_empty_repo() {
    local repo
    repo=$(create_fixture_repo)

    run_atlas "$repo" scan
    assert_exit_code 0 "$EXIT_CODE" "empty repo scans fine" || return 1
    assert_json_field "$OUTPUT" '.total_files' "0" "zero files" || return 1

    cleanup_fixture_repo "$repo"
}
