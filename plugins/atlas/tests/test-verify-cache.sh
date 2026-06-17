#!/usr/bin/env bash
# CLI-level tests for `atlas-cli verify-cache write|read` — the persisted
# findings cache that lets /atlas repair reuse a prior /atlas verify. Reuse is
# gated on drift_cache_key (the same repo-state fingerprint /atlas status
# trusts): valid only while HEAD and the working tree are unchanged, and never
# invalidated by atlas's own .atlas/ runtime churn.

# A minimal but complete two-module + overview map, finalized so lint/diff are
# clean and the cache can round-trip real findings.
_vc_fixture() {
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

# verify-cache write reads verdicts from stdin; run_atlas does not pipe stdin.
_vc_write() {
    local repo="$1" verdicts="$2"
    set +e
    OUTPUT=$(cd "$repo" && printf '%s' "$verdicts" \
        | python3 "$CLI" verify-cache write 2>/dev/null)
    EXIT_CODE=$?
    set -e
}

_VC_VERDICTS='[{"doc":"modules/src-auth.md","pass":true,"claims_checked":5,"failures":[]}]'

test_verify_cache_write_then_read_valid() {
    local repo
    repo=$(_vc_fixture)

    _vc_write "$repo" "$_VC_VERDICTS"
    assert_exit_code 0 "$EXIT_CODE" "write exits 0" || return 1
    assert_json_field "$OUTPUT" '.ok' "true" "write ok" || return 1
    assert_json_field "$OUTPUT" '.verdicts' "1" "write reports verdict count" || return 1
    assert_file_exists "$repo/.atlas/verify.json" "cache file written" || return 1

    run_atlas "$repo" verify-cache read
    assert_json_field "$OUTPUT" '.valid' "true" "read is valid" || return 1
    assert_json_field "$OUTPUT" '.cache.verdicts[0].doc' "modules/src-auth.md" \
        "verdicts round-trip" || return 1
    assert_json_field "$OUTPUT" '.cache.lint.error_count' "0" \
        "lint embedded in cache" || return 1
    assert_json_field "$OUTPUT" '.cache.diff.ok' "true" \
        "diff embedded in cache" || return 1
    assert_json_field "$OUTPUT" '.cache.version' "1" "cache is versioned" || return 1

    cleanup_fixture_repo "$repo"
}

test_verify_cache_invalidated_by_committed_edit() {
    local repo
    repo=$(_vc_fixture)
    _vc_write "$repo" "$_VC_VERDICTS"

    echo "// changed" >> "$repo/src/auth/a.txt"
    commit_all "$repo" "edit a source"

    run_atlas "$repo" verify-cache read
    assert_json_field "$OUTPUT" '.valid' "false" "HEAD move invalidates cache" || return 1
    assert_json_field "$OUTPUT" '.stale_reason' "fingerprint" "stale reason named" || return 1

    cleanup_fixture_repo "$repo"
}

test_verify_cache_invalidated_by_dirty_worktree() {
    local repo
    repo=$(_vc_fixture)
    _vc_write "$repo" "$_VC_VERDICTS"

    # Uncommitted edit — git status changes, so the fingerprint changes.
    echo "// uncommitted" >> "$repo/src/core/d.txt"

    run_atlas "$repo" verify-cache read
    assert_json_field "$OUTPUT" '.valid' "false" "dirty worktree invalidates cache" || return 1
    assert_json_field "$OUTPUT" '.stale_reason' "fingerprint" "stale reason named" || return 1

    cleanup_fixture_repo "$repo"
}

test_verify_cache_ignores_atlas_runtime_churn() {
    local repo
    repo=$(_vc_fixture)
    _vc_write "$repo" "$_VC_VERDICTS"

    # Atlas's own gitignored runtime dir must not invalidate the cache it lives in.
    mkdir -p "$repo/.atlas/diffs"
    echo "patch" > "$repo/.atlas/diffs/some-doc.patch"

    run_atlas "$repo" verify-cache read
    assert_json_field "$OUTPUT" '.valid' "true" ".atlas churn does not invalidate" || return 1

    cleanup_fixture_repo "$repo"
}

test_verify_cache_absent_is_invalid() {
    local repo
    repo=$(_vc_fixture)

    run_atlas "$repo" verify-cache read
    assert_exit_code 0 "$EXIT_CODE" "read of absent cache still exits 0" || return 1
    assert_json_field "$OUTPUT" '.valid' "false" "absent cache is invalid" || return 1
    assert_json_field "$OUTPUT" '.stale_reason' "absent" "absent reason named" || return 1

    cleanup_fixture_repo "$repo"
}

test_verify_cache_version_mismatch_is_invalid() {
    local repo
    repo=$(_vc_fixture)
    _vc_write "$repo" "$_VC_VERDICTS"

    # Bump the stored version but keep the (correct) fingerprint, so the version
    # gate — not the fingerprint gate — is what fails. Forward-compat guard.
    python3 - "$repo/.atlas/verify.json" <<'PY'
import json, sys
p = sys.argv[1]
with open(p) as f:
    c = json.load(f)
c["version"] = 99
with open(p, "w") as f:
    json.dump(c, f)
PY

    run_atlas "$repo" verify-cache read
    assert_json_field "$OUTPUT" '.valid' "false" "unknown version is invalid" || return 1
    assert_json_field "$OUTPUT" '.stale_reason' "version" "version reason named" || return 1

    cleanup_fixture_repo "$repo"
}

test_verify_cache_empty_verdicts() {
    local repo
    repo=$(_vc_fixture)

    _vc_write "$repo" ""
    assert_json_field "$OUTPUT" '.ok' "true" "empty stdin still writes" || return 1
    assert_json_field "$OUTPUT" '.verdicts' "0" "no verdicts recorded" || return 1

    run_atlas "$repo" verify-cache read
    assert_json_field "$OUTPUT" '.valid' "true" "empty cache is still valid" || return 1
    assert_json_field "$OUTPUT" '.cache.verdicts | length' "0" \
        "verdicts is an empty array" || return 1

    cleanup_fixture_repo "$repo"
}
