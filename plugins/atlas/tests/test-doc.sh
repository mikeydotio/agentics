#!/usr/bin/env bash
# Tests for `atlas-cli doc apply-renames` and `atlas-cli doc remove` — the
# mechanical (no-LLM) map-doc mutations used by the incremental update flow.

# Two-module fixture with a body path reference in src-auth so rename
# rewrites have body text to rewrite, not just frontmatter.
_doc_fixture() {
    local repo
    repo=$(create_fixture_repo)
    seed_file "$repo" "src/auth/a.txt"
    seed_file "$repo" "src/auth/b.txt"
    seed_file "$repo" "src/api/c.txt"
    write_module_doc "$repo" "src-auth" "src/auth" "" \
        src/auth/a.txt src/auth/b.txt
    {
        echo ""
        echo "Defined in \`src/auth/a.txt:1\` and used everywhere."
    } >> "$repo/docs/atlas/modules/src-auth.md"
    write_module_doc "$repo" "src-api" "src/api" "src-auth" \
        src/api/c.txt
    commit_all "$repo"
    run_atlas "$repo" ledger finalize --refresh-hashes
    commit_all "$repo" "map"
    echo "$repo"
}

test_doc_apply_renames_pure_rename() {
    local repo
    repo=$(_doc_fixture)
    git -C "$repo" mv src/auth/a.txt src/auth/alpha.txt
    git -C "$repo" commit -q -m "rename"

    run_atlas "$repo" doc apply-renames
    assert_exit_code 0 "$EXIT_CODE" "apply-renames exits 0" || return 1
    assert_json_field "$OUTPUT" '.rewritten[0].doc' "modules/src-auth.md" \
        "renamed doc rewritten" || return 1
    assert_json_field "$OUTPUT" \
        '.rewritten[0].renames[0].from + ">" + .rewritten[0].renames[0].to' \
        "src/auth/a.txt>src/auth/alpha.txt" "rename pair reported" || return 1

    grep -q "path: src/auth/alpha.txt" "$repo/docs/atlas/modules/src-auth.md" \
        || { echo "    FAIL: frontmatter source path not rewritten"; return 1; }
    if grep -q "src/auth/a.txt" "$repo/docs/atlas/modules/src-auth.md"; then
        echo "    FAIL: old path still present in the doc"
        return 1
    fi
    grep -q "\`src/auth/alpha.txt:1\`" "$repo/docs/atlas/modules/src-auth.md" \
        || { echo "    FAIL: body path reference not rewritten"; return 1; }

    # After the mechanical rewrite + finalize, the map is clean again.
    run_atlas "$repo" ledger finalize --refresh-hashes
    run_atlas "$repo" ledger diff
    assert_json_field "$OUTPUT" '.summary.affected_docs' "0" \
        "rewrite resolves the rename without an LLM" || return 1

    cleanup_fixture_repo "$repo"
}

test_doc_apply_renames_inside_stale_doc() {
    local repo
    repo=$(_doc_fixture)
    git -C "$repo" mv src/auth/a.txt src/auth/alpha.txt
    echo "// edit" >> "$repo/src/auth/b.txt"
    git -C "$repo" add -A
    git -C "$repo" commit -q -m "rename + edit"

    run_atlas "$repo" doc apply-renames
    assert_exit_code 0 "$EXIT_CODE" "apply-renames exits 0" || return 1
    assert_json_field "$OUTPUT" '.rewritten[0].doc' "modules/src-auth.md" \
        "stale doc with renames rewritten too" || return 1
    grep -q "path: src/auth/alpha.txt" "$repo/docs/atlas/modules/src-auth.md" \
        || { echo "    FAIL: rename inside stale doc not rewritten"; return 1; }

    # Still stale (b.txt edit needs a cartographer), but no renames remain.
    run_atlas "$repo" ledger diff
    assert_json_contains "$OUTPUT" '[.stale_docs[].doc]' "modules/src-auth.md" \
        "doc remains stale for the content edit" || return 1
    assert_json_field "$OUTPUT" '.stale_docs[0].renames | length' "0" \
        "no unapplied renames remain" || return 1

    cleanup_fixture_repo "$repo"
}

test_doc_apply_renames_noop() {
    local repo
    repo=$(_doc_fixture)
    run_atlas "$repo" doc apply-renames
    assert_exit_code 0 "$EXIT_CODE" "noop exits 0" || return 1
    assert_json_field "$OUTPUT" '.rewritten | length' "0" \
        "nothing rewritten on a clean map" || return 1

    cleanup_fixture_repo "$repo"
}

test_doc_remove_deletes_and_reports_sources() {
    local repo
    repo=$(_doc_fixture)

    run_atlas "$repo" doc remove modules/src-api.md
    assert_exit_code 0 "$EXIT_CODE" "remove exits 0" || return 1
    assert_json_field "$OUTPUT" '.removed[0].doc' "modules/src-api.md" \
        "removed doc reported" || return 1
    assert_json_field "$OUTPUT" '.removed[0].module' "src/api" \
        "module identity echoed for regeneration" || return 1
    assert_json_contains "$OUTPUT" '.removed[0].sources' "src/api/c.txt" \
        "sources echoed for regeneration" || return 1
    if [ -f "$repo/docs/atlas/modules/src-api.md" ]; then
        echo "    FAIL: doc file still exists"
        return 1
    fi

    cleanup_fixture_repo "$repo"
}

test_doc_remove_handles_overview_docs() {
    local repo
    repo=$(_doc_fixture)
    write_overview_doc "$repo" "ARCHITECTURE" "src" \
        docs/atlas/modules/src-auth.md
    commit_all "$repo" "overview"

    run_atlas "$repo" doc remove overview/ARCHITECTURE.md
    assert_exit_code 0 "$EXIT_CODE" "overview removal exits 0" || return 1
    if [ -f "$repo/docs/atlas/overview/ARCHITECTURE.md" ]; then
        echo "    FAIL: overview doc still exists"
        return 1
    fi

    cleanup_fixture_repo "$repo"
}

test_doc_remove_is_all_or_nothing() {
    local repo
    repo=$(_doc_fixture)

    run_atlas "$repo" doc remove modules/src-api.md modules/nope.md
    assert_exit_code 1 "$EXIT_CODE" "unknown doc fails the batch" || return 1
    assert_json_field "$OUTPUT" '.error' "unknown_doc" "error code" || return 1
    assert_file_exists "$repo/docs/atlas/modules/src-api.md" \
        "valid doc untouched when the batch fails" || return 1

    cleanup_fixture_repo "$repo"
}

test_doc_remove_refuses_non_map_paths() {
    local repo
    repo=$(_doc_fixture)
    run_atlas "$repo" index rebuild

    run_atlas "$repo" doc remove INDEX.md
    assert_exit_code 1 "$EXIT_CODE" "INDEX refusal" || return 1
    assert_json_field "$OUTPUT" '.error' "invalid_doc_id" "error code" || return 1

    run_atlas "$repo" doc remove "modules/../../README.md"
    assert_exit_code 1 "$EXIT_CODE" "path-escape refusal" || return 1
    assert_json_field "$OUTPUT" '.error' "invalid_doc_id" "error code" || return 1

    cleanup_fixture_repo "$repo"
}
