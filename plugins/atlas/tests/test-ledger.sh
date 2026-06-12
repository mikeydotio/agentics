#!/usr/bin/env bash
# Tests for `atlas-cli ledger finalize` and `atlas-cli ledger diff` — the
# blob-SHA dependency ledger that drives incremental invalidation.

# Standard two-module fixture: src-auth (2 files) and src-api (1 file,
# references src-auth for ripple tests).
_ledger_fixture() {
    local repo
    repo=$(create_fixture_repo)
    seed_file "$repo" "src/auth/a.txt"
    seed_file "$repo" "src/auth/b.txt"
    seed_file "$repo" "src/api/c.txt"
    write_module_doc "$repo" "src-auth" "src/auth" "" \
        src/auth/a.txt src/auth/b.txt
    write_module_doc "$repo" "src-api" "src/api" "src-auth" \
        src/api/c.txt
    commit_all "$repo"
    echo "$repo"
}

test_ledger_finalize_fills_blobs() {
    local repo
    repo=$(_ledger_fixture)

    run_atlas "$repo" ledger finalize --refresh-hashes
    assert_exit_code 0 "$EXIT_CODE" "finalize exits 0" || return 1
    assert_json_field "$OUTPUT" '.ok' "true" "ok" || return 1
    assert_json_field "$OUTPUT" '.docs_count' "2" "two docs" || return 1

    local blobs
    blobs=$(grep -cE "blob: [0-9a-f]{40}" "$repo/docs/atlas/modules/src-auth.md")
    assert_eq "2" "$blobs" "both sources got blob hashes" || return 1

    assert_file_exists "$repo/docs/atlas/atlas-ledger.json" "reverse index written" || return 1
    local owner
    owner=$(jq -r '.paths["src/auth/a.txt"]' "$repo/docs/atlas/atlas-ledger.json")
    assert_eq "modules/src-auth.md" "$owner" "reverse index maps path to doc" || return 1
    local refby
    refby=$(jq -r '.referenced_by["src-auth"] | join(",")' "$repo/docs/atlas/atlas-ledger.json")
    assert_eq "modules/src-api.md" "$refby" "ripple reverse edge recorded" || return 1

    cleanup_fixture_repo "$repo"
}

test_ledger_finalize_validates_frontmatter() {
    local repo
    repo=$(create_fixture_repo)
    seed_file "$repo" "src/a.txt"
    mkdir -p "$repo/docs/atlas/modules"
    cat > "$repo/docs/atlas/modules/bad.md" <<'DOC'
---
module: src
sources:
  - path: src/a.txt
generator: cartographer/1 model=test
---
body
DOC
    commit_all "$repo"

    run_atlas "$repo" ledger finalize --refresh-hashes
    assert_exit_code 1 "$EXIT_CODE" "invalid doc fails" || return 1
    assert_json_field "$OUTPUT" '.error' "invalid_frontmatter" "error code" || return 1

    cleanup_fixture_repo "$repo"
}

test_ledger_finalize_rejects_duplicate_ownership() {
    local repo
    repo=$(create_fixture_repo)
    seed_file "$repo" "src/a.txt"
    write_module_doc "$repo" "one" "src" "" src/a.txt
    write_module_doc "$repo" "two" "src" "" src/a.txt
    commit_all "$repo"

    run_atlas "$repo" ledger finalize --refresh-hashes
    assert_exit_code 1 "$EXIT_CODE" "duplicate ownership fails" || return 1
    assert_json_field "$OUTPUT" '.error' "duplicate_source" "error code" || return 1

    cleanup_fixture_repo "$repo"
}

test_ledger_diff_clean() {
    local repo
    repo=$(_ledger_fixture)
    run_atlas "$repo" ledger finalize --refresh-hashes

    run_atlas "$repo" ledger diff
    assert_exit_code 0 "$EXIT_CODE" "diff exits 0" || return 1
    assert_json_field "$OUTPUT" '.summary.affected_docs' "0" "nothing affected" || return 1
    assert_json_field "$OUTPUT" '.unchanged_docs | length' "2" "both docs unchanged" || return 1

    cleanup_fixture_repo "$repo"
}

test_ledger_diff_detects_dirty_edit() {
    local repo
    repo=$(_ledger_fixture)
    run_atlas "$repo" ledger finalize --refresh-hashes
    echo "// changed" >> "$repo/src/auth/a.txt"   # NOT committed

    run_atlas "$repo" ledger diff
    assert_json_contains "$OUTPUT" '[.stale_docs[].doc]' "modules/src-auth.md" \
        "dirty edit detected via working-tree hash" || return 1
    assert_json_not_contains "$OUTPUT" '[.stale_docs[].doc]' "modules/src-api.md" \
        "untouched doc not stale" || return 1

    cleanup_fixture_repo "$repo"
}

test_ledger_diff_detects_committed_edit() {
    local repo
    repo=$(_ledger_fixture)
    run_atlas "$repo" ledger finalize --refresh-hashes
    echo "// changed" >> "$repo/src/auth/a.txt"
    commit_all "$repo" "edit auth"

    run_atlas "$repo" ledger diff
    assert_json_contains "$OUTPUT" '[.stale_docs[].doc]' "modules/src-auth.md" \
        "committed edit detected via ls-tree" || return 1

    cleanup_fixture_repo "$repo"
}

test_ledger_diff_pure_rename() {
    local repo
    repo=$(_ledger_fixture)
    run_atlas "$repo" ledger finalize --refresh-hashes
    git -C "$repo" mv src/auth/a.txt src/auth/renamed.txt
    git -C "$repo" commit -q -m "rename"

    run_atlas "$repo" ledger diff
    assert_json_contains "$OUTPUT" '[.renamed_docs[].doc]' "modules/src-auth.md" \
        "pure rename classified as rename" || return 1
    assert_json_field "$OUTPUT" \
        '.renamed_docs[0].renames[0].from + ">" + .renamed_docs[0].renames[0].to' \
        "src/auth/a.txt>src/auth/renamed.txt" "rename from/to recorded" || return 1
    assert_json_not_contains "$OUTPUT" '[.stale_docs[].doc]' "modules/src-auth.md" \
        "renamed doc is not stale" || return 1

    cleanup_fixture_repo "$repo"
}

test_ledger_diff_orphan() {
    local repo
    repo=$(create_fixture_repo)
    seed_file "$repo" "tmp/x.txt"
    seed_file "$repo" "src/keep.txt"
    write_module_doc "$repo" "tmp" "tmp" "" tmp/x.txt
    write_module_doc "$repo" "src" "src" "" src/keep.txt
    commit_all "$repo"
    run_atlas "$repo" ledger finalize --refresh-hashes
    git -C "$repo" rm -q tmp/x.txt
    git -C "$repo" commit -q -m "delete tmp"

    run_atlas "$repo" ledger diff
    assert_json_contains "$OUTPUT" '[.orphaned_docs[].doc]' "modules/tmp.md" \
        "all-sources-gone doc orphaned" || return 1
    assert_json_not_contains "$OUTPUT" '[.stale_docs[].doc]' "modules/tmp.md" \
        "orphan not double-counted as stale" || return 1

    cleanup_fixture_repo "$repo"
}

test_ledger_diff_new_files() {
    local repo
    repo=$(_ledger_fixture)
    run_atlas "$repo" ledger finalize --refresh-hashes
    seed_file "$repo" "src/newfile.txt"   # untracked

    run_atlas "$repo" ledger diff
    assert_json_contains "$OUTPUT" '.new_files' "src/newfile.txt" \
        "unmapped new file reported" || return 1

    cleanup_fixture_repo "$repo"
}

test_ledger_diff_ripple() {
    local repo
    repo=$(_ledger_fixture)
    run_atlas "$repo" ledger finalize --refresh-hashes
    echo "// changed" >> "$repo/src/auth/a.txt"

    run_atlas "$repo" ledger diff
    assert_json_contains "$OUTPUT" '[.ripple_docs[].doc]' "modules/src-api.md" \
        "doc referencing stale module rippled" || return 1
    assert_json_field "$OUTPUT" '.summary.affected_docs' "2" \
        "stale + ripple both affected" || return 1

    cleanup_fixture_repo "$repo"
}

test_ledger_diff_survives_history_rewrite() {
    local repo
    repo=$(_ledger_fixture)
    run_atlas "$repo" ledger finalize --refresh-hashes
    git -C "$repo" add -A
    git -C "$repo" commit -q -m "map"
    # Rewrite history entirely (simulates a squash merge): an orphan branch
    # gets the same tree in a brand-new root commit, so the recorded baseline
    # commit is no longer an ancestor of HEAD.
    git -C "$repo" checkout -q --orphan rewritten
    git -C "$repo" commit -q -m "squashed history"

    run_atlas "$repo" ledger diff
    assert_exit_code 0 "$EXIT_CODE" "diff works after rewrite" || return 1
    assert_json_field "$OUTPUT" '.summary.affected_docs' "0" \
        "identical content still unchanged" || return 1
    assert_json_field "$OUTPUT" '.baseline.is_ancestor' "false" \
        "baseline no longer ancestor" || return 1
    assert_json_field "$OUTPUT" '.baseline.commits_behind' "null" \
        "no ancestry-based counting after rewrite" || return 1

    # Invalidation still works post-rewrite
    echo "// changed" >> "$repo/src/auth/a.txt"
    run_atlas "$repo" ledger diff
    assert_json_contains "$OUTPUT" '[.stale_docs[].doc]' "modules/src-auth.md" \
        "edit detected after history rewrite" || return 1

    cleanup_fixture_repo "$repo"
}

test_ledger_diff_generator_fingerprint() {
    local repo
    repo=$(_ledger_fixture)
    run_atlas "$repo" ledger finalize --refresh-hashes

    run_atlas "$repo" ledger diff --generator "cartographer/2 model=test"
    assert_json_field "$OUTPUT" '.fingerprint_stale | length' "2" \
        "generator bump invalidates all docs" || return 1

    run_atlas "$repo" ledger diff --generator "cartographer/1 model=test"
    assert_json_field "$OUTPUT" '.fingerprint_stale | length' "0" \
        "matching generator invalidates none" || return 1

    cleanup_fixture_repo "$repo"
}

test_ledger_diff_scope_change() {
    local repo
    repo=$(_ledger_fixture)
    write_overview_doc "$repo" "ARCHITECTURE" "src" \
        docs/atlas/modules/src-auth.md docs/atlas/modules/src-api.md
    commit_all "$repo" "add overview"
    run_atlas "$repo" ledger finalize --refresh-hashes
    seed_file "$repo" "src/auth/brand-new.txt"
    commit_all "$repo" "new file under scope"

    run_atlas "$repo" ledger diff
    assert_json_contains "$OUTPUT" '[.stale_docs[].doc]' "overview/ARCHITECTURE.md" \
        "tree-scope change invalidates overview" || return 1

    cleanup_fixture_repo "$repo"
}

test_ledger_set_verified() {
    local repo
    repo=$(_ledger_fixture)
    run_atlas "$repo" ledger finalize --refresh-hashes

    run_atlas "$repo" ledger set-verified modules/src-auth.md true
    assert_exit_code 0 "$EXIT_CODE" "set-verified succeeds" || return 1
    grep -q "^verified: true$" "$repo/docs/atlas/modules/src-auth.md" \
        || { echo "    FAIL: verified flag not written to frontmatter"; return 1; }
    local in_ledger
    in_ledger=$(jq -r '.docs["modules/src-auth.md"].verified' \
        "$repo/docs/atlas/atlas-ledger.json")
    assert_eq "true" "$in_ledger" "ledger reflects the verdict" || return 1

    run_atlas "$repo" ledger set-verified modules/nope.md true
    assert_exit_code 1 "$EXIT_CODE" "unknown doc fails" || return 1

    cleanup_fixture_repo "$repo"
}

test_ledger_diff_shallow_clone() {
    local repo clone
    repo=$(_ledger_fixture)
    run_atlas "$repo" ledger finalize --refresh-hashes
    git -C "$repo" add -A
    git -C "$repo" commit -q -m "map"
    echo "// changed" >> "$repo/src/auth/a.txt"
    git -C "$repo" add -A
    git -C "$repo" commit -q -m "edit after map"

    clone=$(mktemp -d "/tmp/atlas-tests-XXXXXX")
    rm -rf "$clone"
    git clone -q --depth 1 "file://$repo" "$clone"

    run_atlas "$clone" ledger diff
    assert_exit_code 0 "$EXIT_CODE" "diff works in shallow clone" || return 1
    assert_json_contains "$OUTPUT" '[.stale_docs[].doc]' "modules/src-auth.md" \
        "stale detection needs no baseline object" || return 1

    cleanup_fixture_repo "$repo"
    cleanup_fixture_repo "$clone"
}
