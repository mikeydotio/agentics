#!/usr/bin/env bash
# Tests for hooks/session-start.sh — tier-gated staleness injection.

HOOK="$PLUGIN_ROOT/hooks/session-start.sh"

# Mapped, clean, five-module fixture (one stale doc = 20% = tier 1, so the
# drift test sees a message that names modules rather than tier-3 suppression).
_hook_fixture() {
    local repo d
    repo=$(create_fixture_repo)
    seed_file "$repo" "src/auth/a.txt"
    write_module_doc "$repo" "src-auth" "src/auth" "" src/auth/a.txt
    for d in api models views core; do
        seed_file "$repo" "src/$d/f.txt"
        write_module_doc "$repo" "src-$d" "src/$d" "" "src/$d/f.txt"
    done
    commit_all "$repo"
    run_atlas "$repo" ledger finalize --refresh-hashes
    run_atlas "$repo" index rebuild
    git -C "$repo" add -A
    git -C "$repo" commit -q -m "map"
    echo "$repo"
}

# run_hook <repo> — pipes a SessionStart-style event into the hook with a
# clean environment. Sets OUTPUT and EXIT_CODE.
run_hook() {
    local repo="$1"
    set +e
    OUTPUT=$(printf '{"cwd": "%s"}' "$repo" | \
        env -u CLAUDE_PROJECT_DIR bash "$HOOK" 2>/dev/null)
    EXIT_CODE=$?
    set -e
}

test_hook_silent_when_unmapped() {
    local repo
    repo=$(create_fixture_repo)
    seed_file "$repo" "a.txt"
    commit_all "$repo"

    run_hook "$repo"
    assert_exit_code 0 "$EXIT_CODE" "hook exits 0" || return 1
    assert_eq "" "$OUTPUT" "no output for unmapped repo" || return 1

    cleanup_fixture_repo "$repo"
}

test_hook_silent_at_tier0() {
    local repo
    repo=$(_hook_fixture)

    run_hook "$repo"
    assert_exit_code 0 "$EXIT_CODE" "hook exits 0" || return 1
    assert_eq "" "$OUTPUT" "clean map injects nothing" || return 1

    cleanup_fixture_repo "$repo"
}

test_hook_emits_on_drift() {
    local repo
    repo=$(_hook_fixture)
    echo "// changed" >> "$repo/src/auth/a.txt"

    run_hook "$repo"
    assert_exit_code 0 "$EXIT_CODE" "hook exits 0" || return 1
    local ctx
    ctx=$(echo "$OUTPUT" | jq -r '.additionalContext' 2>/dev/null)
    if [[ -z "$ctx" || "$ctx" == "null" ]]; then
        echo "    FAIL: expected additionalContext JSON, got: $OUTPUT"
        return 1
    fi
    echo "$ctx" | grep -q "Atlas" || { echo "    FAIL: message not atlas-branded"; return 1; }
    echo "$ctx" | grep -q "src-auth" || { echo "    FAIL: stale module not named"; return 1; }

    cleanup_fixture_repo "$repo"
}

test_hook_emits_distrust_at_tier3() {
    local repo
    repo=$(_hook_fixture)
    printf '<<<<<<< HEAD\nx\n>>>>>>> y\n' >> "$repo/docs/atlas/modules/src-auth.md"

    run_hook "$repo"
    local ctx
    ctx=$(echo "$OUTPUT" | jq -r '.additionalContext' 2>/dev/null)
    echo "$ctx" | grep -qi "disregard" \
        || { echo "    FAIL: tier-3 message must tell agents to disregard the map"; return 1; }

    cleanup_fixture_repo "$repo"
}

test_hook_uses_project_dir_env() {
    local repo
    repo=$(_hook_fixture)
    echo "// changed" >> "$repo/src/auth/a.txt"

    set +e
    OUTPUT=$(CLAUDE_PROJECT_DIR="$repo" bash "$HOOK" < /dev/null 2>/dev/null)
    EXIT_CODE=$?
    set -e
    assert_exit_code 0 "$EXIT_CODE" "hook exits 0" || return 1
    echo "$OUTPUT" | jq -e '.additionalContext' > /dev/null 2>&1 \
        || { echo "    FAIL: env-provided project dir not honored"; return 1; }

    cleanup_fixture_repo "$repo"
}
