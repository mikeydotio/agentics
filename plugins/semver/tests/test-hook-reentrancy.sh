#!/usr/bin/env bash
# Tests: Re-entrancy guard blocks nested bumps, guard passed to children

test_reentrancy_blocks_when_guard_set() {
    local repo
    repo=$(create_test_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    create_hook_script "$repo" "pre-bump" "01-check.sh" 'echo "ok"'

    local result
    set +e
    result=$(SEMVER_BUMP_IN_PROGRESS=1 bash "$RUNNER" pre-bump patch v1.0.0 v1.0.1 "$repo")
    local ec=$?
    set -e

    assert_exit_code 2 "$ec" "should exit 2 for re-entrancy" &&
    assert_json_field "$result" '.status' "blocked" "status should be blocked"
}

test_reentrancy_guard_passed_to_children() {
    local repo
    repo=$(create_test_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    create_hook_script "$repo" "pre-bump" "01-check-guard.sh" \
        "echo \"\$SEMVER_BUMP_IN_PROGRESS\" > '$repo/.guard-val'"

    bash "$RUNNER" pre-bump patch v1.0.0 v1.0.1 "$repo" > /dev/null

    local actual
    actual=$(cat "$repo/.guard-val" | tr -d '[:space:]')
    assert_eq "1" "$actual" "child should see SEMVER_BUMP_IN_PROGRESS=1"
}

test_normal_execution_when_guard_unset() {
    local repo
    repo=$(create_test_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    create_hook_script "$repo" "pre-bump" "01-pass.sh" 'echo "ok"'

    local result
    set +e
    result=$(unset SEMVER_BUMP_IN_PROGRESS; bash "$RUNNER" pre-bump patch v1.0.0 v1.0.1 "$repo")
    local ec=$?
    set -e

    assert_exit_code 0 "$ec" "should succeed without guard" &&
    assert_json_field "$result" '.status' "ok" "status should be ok"
}

test_nested_runner_invocation_blocked() {
    local repo
    repo=$(create_test_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    # Hook script that tries to invoke the runner again
    # Must disable set -e to capture exit code of failing nested call
    mkdir -p "$repo/.semver/hooks/pre-bump"
    cat > "$repo/.semver/hooks/pre-bump/01-nested.sh" << SCRIPT
#!/usr/bin/env bash
set +e
bash '$RUNNER' pre-bump patch v1.0.0 v1.0.1 '$repo' > '$repo/.nested-result' 2>&1
echo \$? > '$repo/.nested-exit'
exit 0
SCRIPT
    chmod +x "$repo/.semver/hooks/pre-bump/01-nested.sh"

    bash "$RUNNER" pre-bump patch v1.0.0 v1.0.1 "$repo" > /dev/null

    local nested_exit
    nested_exit=$(cat "$repo/.nested-exit" | tr -d '[:space:]')
    assert_eq "2" "$nested_exit" "nested invocation should be blocked (exit 2)"

    local nested_result
    nested_result=$(cat "$repo/.nested-result")
    local nested_status
    nested_status=$(echo "$nested_result" | jq -r '.status' 2>/dev/null)
    assert_eq "blocked" "$nested_status" "nested invocation should report blocked"
}
