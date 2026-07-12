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

# --- issue #79: the overview `docs` scope must not self-invalidate ------------
# A repo whose docs/ holds BOTH a real mapped source (docs/guide.md) AND the
# map's own committed output (docs/atlas/**). The overview scopes on `docs`.
# `ledger finalize` writes the scope sha INTO the overview (which lives under
# docs/atlas/), so every map commit rewrites docs/atlas/** — a raw
# `git rev-parse HEAD:docs` tree OID reads that as a scope change and flags the
# overview stale forever (never converges). The scoped-file digest hashes only
# the SCANNED files under the root (docs/atlas/** excluded), so a clean
# map+commit stays tier 0 while a genuine docs/guide.md change still invalidates.
_status_docs_scope_fixture() {
    local repo
    repo=$(create_fixture_repo)
    seed_file "$repo" "docs/guide.md"
    write_module_doc "$repo" "docs-guide" "docs" "" "docs/guide.md"
    seed_file "$repo" "src/m1/f.txt"
    write_module_doc "$repo" "src-m1" "src/m1" "" "src/m1/f.txt"
    write_overview_doc "$repo" "ARCHITECTURE" "docs" \
        docs/atlas/modules/docs-guide.md \
        docs/atlas/modules/src-m1.md
    commit_all "$repo"
    run_atlas "$repo" ledger finalize --refresh-hashes
    run_atlas "$repo" index rebuild
    git -C "$repo" add -A
    git -C "$repo" commit -q -m "map"
    echo "$repo"
}

# The core regression: pre-fix this fixture reports tier 2 ("ARCHITECTURE …
# stale") on the very first clean map+commit because the map's own output moved
# HEAD:docs. It must be tier 0.
test_status_docs_scope_selfmap_stays_t0() {
    local repo
    repo=$(_status_docs_scope_fixture)

    run_atlas "$repo" status
    assert_json_field "$OUTPUT" '.mapped' "true" "mapped" || return 1
    assert_json_field "$OUTPUT" '.tier' "0" \
        "docs-scope overview stays tier 0 after a clean map+commit (issue #79)" || return 1

    cleanup_fixture_repo "$repo"
}

# No false negative: a real change to the scanned source under the scope MUST
# still invalidate the overview, and specifically via a `docs` scope_changed
# reason — proving the fix narrowed detection to scanned files, not disabled it.
test_status_docs_scope_real_edit_flags_overview() {
    local repo
    repo=$(_status_docs_scope_fixture)
    echo "// behavior change" >> "$repo/docs/guide.md"
    commit_all "$repo" "edit guide"

    run_atlas "$repo" ledger diff
    assert_json_contains "$OUTPUT" '[.stale_docs[].doc]' "overview/ARCHITECTURE.md" \
        "real docs/ source change invalidates the overview" || return 1
    assert_json_contains "$OUTPUT" \
        '[.stale_docs[] | select(.doc=="overview/ARCHITECTURE.md") | .reasons[] | select(.kind=="scope_changed") | .path]' \
        "docs" "invalidation is a docs scope_changed, not a false positive" || return 1

    cleanup_fixture_repo "$repo"
}

# Convergence under real map churn: editing a non-docs source forces a re-map
# whose commit legitimately rewrites docs/atlas/** (module doc + INDEX +
# overview). The `docs` scope must NOT be re-flagged by that churn — the map
# reaches tier 0 again. Pre-fix, docs/atlas moving on every commit meant the
# overview never converged.
test_status_docs_scope_converges_after_remap() {
    local repo
    repo=$(_status_docs_scope_fixture)

    echo "// behavior change" >> "$repo/src/m1/f.txt"
    write_module_doc "$repo" "src-m1" "src/m1" "" "src/m1/f.txt"
    run_atlas "$repo" ledger finalize --refresh-hashes
    assert_exit_code 0 "$EXIT_CODE" "re-finalize ok" || return 1
    run_atlas "$repo" index rebuild
    git -C "$repo" add -A
    git -C "$repo" commit -q -m "map2"

    run_atlas "$repo" status
    assert_json_field "$OUTPUT" '.tier' "0" \
        "docs-scope overview converges to tier 0 after a real re-map commit (issue #79)" || return 1

    cleanup_fixture_repo "$repo"
}
