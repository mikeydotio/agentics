#!/usr/bin/env bash
# Tests for `atlas-cli diffpack` — per-doc anchored-regeneration input packs.
# A diffpack is a .atlas/diffs/*.patch file holding `git diff $OLD $NEW` for
# every changed source plus deleted/new-source notes, so cartographers read
# change context from disk instead of the orchestrator pasting it inline.

_diffpack_fixture() {
    local repo
    repo=$(create_fixture_repo)
    seed_file "$repo" "src/a.txt"
    seed_file "$repo" "src/b.txt"
    write_module_doc "$repo" "src" "src" "" src/a.txt src/b.txt
    commit_all "$repo"
    run_atlas "$repo" ledger finalize --refresh-hashes
    commit_all "$repo" "map"
    echo "$repo"
}

test_diffpack_edited_source() {
    local repo
    repo=$(_diffpack_fixture)
    # Leading \n: seed_file content has no trailing newline, and the marker
    # must land on its own line for the +line assertion below.
    printf '\nDIFFPACK_MARKER_LINE\n' >> "$repo/src/a.txt"

    run_atlas "$repo" diffpack modules/src.md
    assert_exit_code 0 "$EXIT_CODE" "diffpack exits 0" || return 1
    assert_json_field "$OUTPUT" '.patch' ".atlas/diffs/modules-src.patch" \
        "patch path is doc-derived" || return 1
    assert_json_field "$OUTPUT" '.sources_changed' "1" "one changed source" || return 1

    local patch="$repo/.atlas/diffs/modules-src.patch"
    assert_file_exists "$patch" "patch file written" || return 1
    grep -q "### src/a.txt (edited)" "$patch" \
        || { echo "    FAIL: changed-source header missing"; return 1; }
    grep -q "^+DIFFPACK_MARKER_LINE" "$patch" \
        || { echo "    FAIL: added line missing from blob diff"; return 1; }
    if grep -q "src/b.txt" "$patch"; then
        echo "    FAIL: unchanged source leaked into the patch"
        return 1
    fi

    cleanup_fixture_repo "$repo"
}

test_diffpack_deleted_and_added_sources() {
    local repo
    repo=$(_diffpack_fixture)
    git -C "$repo" rm -q src/b.txt
    git -C "$repo" commit -q -m "delete b"
    seed_file "$repo" "src/new1.txt"

    run_atlas "$repo" diffpack modules/src.md --add src/new1.txt
    assert_exit_code 0 "$EXIT_CODE" "diffpack exits 0" || return 1
    assert_json_field "$OUTPUT" '.sources_deleted' "1" "deletion counted" || return 1
    assert_json_field "$OUTPUT" '.sources_added' "1" "addition counted" || return 1

    local patch="$repo/.atlas/diffs/modules-src.patch"
    grep -q "### src/b.txt (deleted)" "$patch" \
        || { echo "    FAIL: deleted-source note missing"; return 1; }
    grep -q "### src/new1.txt (new source)" "$patch" \
        || { echo "    FAIL: new-source note missing"; return 1; }

    cleanup_fixture_repo "$repo"
}

test_diffpack_no_changes() {
    local repo
    repo=$(_diffpack_fixture)

    run_atlas "$repo" diffpack modules/src.md
    assert_exit_code 0 "$EXIT_CODE" "noop exits 0" || return 1
    assert_json_field "$OUTPUT" '.patch' "null" "no patch when nothing changed" || return 1
    assert_json_field "$OUTPUT" '.sources_changed' "0" "zero changes" || return 1

    cleanup_fixture_repo "$repo"
}

test_diffpack_unknown_doc() {
    local repo
    repo=$(_diffpack_fixture)

    run_atlas "$repo" diffpack modules/nope.md
    assert_exit_code 1 "$EXIT_CODE" "unknown doc fails" || return 1
    assert_json_field "$OUTPUT" '.error' "unknown_doc" "error code" || return 1

    cleanup_fixture_repo "$repo"
}
