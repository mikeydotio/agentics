#!/usr/bin/env bash
# CLI-level tests for the /atlas repair flow's deterministic surface. Repair is
# orchestrated by the skill (verify → map-repairer fixer waves → finalize), so
# the agent edits are SIMULATED by rewriting docs with fixtures (as
# test-update-flow.sh does). What is mechanically testable — and pinned here —
# is the machinery the flow depends on:
#   * branch ensure --op repair          (R3 branch naming)
#   * ledger finalize --except <drift>   (R5 Ledger rule: keep drift flagged)
#   * the partition signals (ledger diff / lint) that drive R2 fix-vs-defer
#   * the lint gate that blocks finalizing a lint-failing map

# Two modules + overview, finalized so the map starts clean.
#   src-auth (src/auth/a.txt)   src-core (src/core/d.txt)
_rep_fixture() {
    local repo
    repo=$(create_fixture_repo)
    seed_file "$repo" "src/auth/a.txt"
    seed_file "$repo" "src/core/d.txt"
    write_full_module_doc "$repo" "src-auth" "src/auth" "AuthThing" src/auth/a.txt
    write_full_module_doc "$repo" "src-core" "src/core" "CoreThing" src/core/d.txt
    write_overview_doc "$repo" "ARCHITECTURE" "src" \
        docs/atlas/modules/src-auth.md docs/atlas/modules/src-core.md
    commit_all "$repo"
    run_atlas "$repo" ledger finalize --refresh-hashes
    run_atlas "$repo" index rebuild
    commit_all "$repo" "map"
    echo "$repo"
}

# _rep_blob <repo> <doc-id> <source-path> — the source's recorded blob in the ledger.
_rep_blob() {
    jq -r --arg d "$2" --arg s "$3" '.docs[$d].sources[$s]' \
        "$1/docs/atlas/atlas-ledger.json"
}

_rep_doc_hash() {
    git -C "$1" hash-object "$2"
}

test_repair_branch_op_value() {
    local repo
    repo=$(_rep_fixture)

    run_atlas "$repo" branch ensure --op repair
    assert_exit_code 0 "$EXIT_CODE" "branch ensure --op repair ok" || return 1
    assert_json_field "$OUTPUT" '.branch | startswith("atlas/repair-")' "true" \
        "branch named atlas/repair-<sha>" || return 1
    assert_json_field "$OUTPUT" '.created' "true" "branch created" || return 1

    # Idempotent: already on an atlas/* branch → no new branch.
    run_atlas "$repo" branch ensure --op repair
    assert_json_field "$OUTPUT" '.created' "false" "re-run is idempotent" || return 1

    cleanup_fixture_repo "$repo"
}

# The core Ledger rule: a body fix on a DRIFT doc must not advance its recorded
# source blobs (so it stays flagged for /atlas update), while the overview still
# refreshes (so it is not spuriously left stale).
test_repair_except_preserves_drift_blob_and_refreshes_overview() {
    local repo before after
    repo=$(_rep_fixture)
    before=$(_rep_blob "$repo" "modules/src-auth.md" "src/auth/a.txt")

    # Drift: the source changes and is committed → src-auth is now stale.
    echo "// behavior change" >> "$repo/src/auth/a.txt"
    commit_all "$repo" "edit auth source"
    run_atlas "$repo" ledger diff
    assert_json_contains "$OUTPUT" '[.stale_docs[].doc]' "modules/src-auth.md" \
        "drift doc is stale before repair" || return 1

    # Simulate map-repairer fixing a flagged CLAIM in the body (frontmatter,
    # including the recorded blobs, is left intact).
    sed -i.bak 's/Does fixture things/Does repaired things/' \
        "$repo/docs/atlas/modules/src-auth.md"
    rm -f "$repo/docs/atlas/modules/src-auth.md.bak"

    run_atlas "$repo" ledger finalize --refresh-hashes --except modules/src-auth.md
    assert_exit_code 0 "$EXIT_CODE" "except-finalize ok" || return 1

    after=$(_rep_blob "$repo" "modules/src-auth.md" "src/auth/a.txt")
    assert_eq "$before" "$after" "excepted drift doc keeps its stale blob" || return 1
    grep -q "Does repaired things" "$repo/docs/atlas/modules/src-auth.md" \
        || { echo "    FAIL: body fix did not land"; return 1; }

    run_atlas "$repo" ledger diff
    assert_json_contains "$OUTPUT" '[.stale_docs[].doc]' "modules/src-auth.md" \
        "drift doc STAYS flagged for /atlas update after the body fix" || return 1
    assert_json_not_contains "$OUTPUT" '[.stale_docs[].doc]' "overview/ARCHITECTURE.md" \
        "overview refreshed, not left stale" || return 1

    cleanup_fixture_repo "$repo"
}

# Contrast that pins WHY --except exists: without it, the same finalize advances
# the drift doc's blob and the doc silently looks current.
test_repair_finalize_without_except_advances_blob() {
    local repo before after
    repo=$(_rep_fixture)
    before=$(_rep_blob "$repo" "modules/src-auth.md" "src/auth/a.txt")

    echo "// behavior change" >> "$repo/src/auth/a.txt"
    commit_all "$repo" "edit auth source"
    sed -i.bak 's/Does fixture things/Does repaired things/' \
        "$repo/docs/atlas/modules/src-auth.md"
    rm -f "$repo/docs/atlas/modules/src-auth.md.bak"

    run_atlas "$repo" ledger finalize --refresh-hashes
    after=$(_rep_blob "$repo" "modules/src-auth.md" "src/auth/a.txt")
    if [ "$before" = "$after" ]; then
        echo "    FAIL: blank finalize should have advanced the blob"
        return 1
    fi
    run_atlas "$repo" ledger diff
    assert_json_not_contains "$OUTPUT" '[.stale_docs[].doc]' "modules/src-auth.md" \
        "without --except the drift doc looks current (the bug --except prevents)" || return 1

    cleanup_fixture_repo "$repo"
}

# Repair's domain: a doc that is WRONG about UNCHANGED code. ledger diff (blob)
# says it is not an update target; lint says it has a real defect.
test_repair_blob_clean_lint_break_is_repair_target() {
    local repo
    repo=$(_rep_fixture)

    # Break a relationship verb (L13) by editing only the doc body — the source
    # is untouched, so the doc is blob-clean.
    sed -i.bak 's/(calls)/(builds)/' "$repo/docs/atlas/modules/src-auth.md"
    rm -f "$repo/docs/atlas/modules/src-auth.md.bak"

    run_atlas "$repo" ledger diff
    assert_json_contains "$OUTPUT" '.unchanged_docs' "modules/src-auth.md" \
        "blob-clean doc is NOT an update target" || return 1
    assert_json_not_contains "$OUTPUT" '[.stale_docs[].doc]' "modules/src-auth.md" \
        "blob-clean doc is not stale" || return 1

    run_atlas "$repo" lint
    assert_exit_code 1 "$EXIT_CODE" "lint flags the broken map" || return 1
    assert_json_contains "$OUTPUT" '[.errors[].check]' "L13" \
        "the defect is a real lint ERROR repair can fix" || return 1

    cleanup_fixture_repo "$repo"
}

# A purely global/derived defect (L10 INDEX out of sync) is mechanical: index
# rebuild fixes it and touches no module doc.
test_repair_index_only_is_mechanical() {
    local repo before_auth before_core
    repo=$(_rep_fixture)
    before_auth=$(_rep_doc_hash "$repo" docs/atlas/modules/src-auth.md)
    before_core=$(_rep_doc_hash "$repo" docs/atlas/modules/src-core.md)

    echo "stray line" >> "$repo/docs/atlas/INDEX.md"
    run_atlas "$repo" lint
    assert_json_contains "$OUTPUT" '[.errors[].check]' "L10" "INDEX drift flagged" || return 1

    run_atlas "$repo" index rebuild
    assert_exit_code 0 "$EXIT_CODE" "index rebuild ok" || return 1
    run_atlas "$repo" lint
    assert_exit_code 0 "$EXIT_CODE" "lint clean after mechanical rebuild" || return 1

    assert_eq "$before_auth" "$(_rep_doc_hash "$repo" docs/atlas/modules/src-auth.md)" \
        "module docs untouched by mechanical INDEX repair" || return 1
    assert_eq "$before_core" "$(_rep_doc_hash "$repo" docs/atlas/modules/src-core.md)" \
        "module docs untouched by mechanical INDEX repair" || return 1

    cleanup_fixture_repo "$repo"
}

# Corruption is update's quarantine job, not repair's: ledger diff cannot even
# classify the map, which is repair's R1 defer precondition.
test_repair_corrupt_frontmatter_defers() {
    local repo
    repo=$(_rep_fixture)
    sed -i.bak '/^summary:/d' "$repo/docs/atlas/modules/src-core.md"
    rm -f "$repo/docs/atlas/modules/src-core.md.bak"

    run_atlas "$repo" ledger diff
    assert_exit_code 1 "$EXIT_CODE" "diff refuses an unparsable map" || return 1
    assert_json_field "$OUTPUT" '.error' "invalid_frontmatter" \
        "repair defers corruption to /atlas update" || return 1

    cleanup_fixture_repo "$repo"
}

# A coverage gap needs a NEW module doc (re-derivation), which repair defers.
test_repair_coverage_gap_defers() {
    local repo
    repo=$(_rep_fixture)
    seed_file "$repo" "src/extra/e.txt"
    commit_all "$repo" "add an uncovered file"

    run_atlas "$repo" lint
    assert_json_contains "$OUTPUT" '[.warnings[].check]' "L5" \
        "uncovered file flagged as a coverage WARN" || return 1
    run_atlas "$repo" ledger diff
    assert_json_contains "$OUTPUT" '.new_files' "src/extra/e.txt" \
        "uncovered file surfaces as new_files (update's job, not repair's)" || return 1

    cleanup_fixture_repo "$repo"
}

# The commit gate: a residual lint ERROR (a fix that did not land) makes lint
# exit non-zero, which the flow treats as "do not finalize/commit".
test_repair_lint_gate_blocks_on_residual_error() {
    local repo
    repo=$(_rep_fixture)
    sed -i.bak 's/(calls)/(depends-on)/' "$repo/docs/atlas/modules/src-core.md"
    rm -f "$repo/docs/atlas/modules/src-core.md.bak"

    run_atlas "$repo" lint
    assert_exit_code 1 "$EXIT_CODE" "lint-failing map blocks the final commit" || return 1
    assert_json_field "$OUTPUT" '.ok' "false" "lint reports failure" || return 1

    cleanup_fixture_repo "$repo"
}
