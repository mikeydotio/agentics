#!/usr/bin/env bash
# Tests: Pre-bump failure aborts, post-bump failure warns, chain halting

test_pre_bump_failure_returns_exit_1() {
    local repo
    repo=$(create_test_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    create_hook_script "$repo" "pre-bump" "01-fail.sh" 'exit 1'

    local result
    set +e
    result=$(bash "$RUNNER" pre-bump patch v1.0.0 v1.0.1 "$repo")
    local ec=$?
    set -e

    assert_exit_code 1 "$ec" "should exit 1 on pre-bump failure" &&
    assert_json_field "$result" '.status' "failed" "status should be failed"
}

test_pre_bump_failure_reports_script_name() {
    local repo
    repo=$(create_test_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    create_hook_script "$repo" "pre-bump" "01-validate-deps.sh" 'echo "deps missing"; exit 1'

    local result
    set +e
    result=$(bash "$RUNNER" pre-bump patch v1.0.0 v1.0.1 "$repo")
    set -e

    assert_json_field "$result" '.failed_hook' "01-validate-deps.sh" "should report failing script name" &&
    assert_json_field "$result" '.exit_code' "1" "should report exit code"
}

test_pre_bump_failure_halts_chain() {
    local repo
    repo=$(create_test_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    create_hook_script "$repo" "pre-bump" "01-fail.sh" 'exit 1'
    create_hook_script "$repo" "pre-bump" "02-should-not-run.sh" \
        "touch '$repo/.second-ran'"

    set +e
    bash "$RUNNER" pre-bump patch v1.0.0 v1.0.1 "$repo" > /dev/null
    set -e

    assert_file_not_exists "$repo/.second-ran" "second script should not have run"
}

test_pre_bump_first_script_passes_second_fails() {
    local repo
    repo=$(create_test_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    create_hook_script "$repo" "pre-bump" "01-pass.sh" "touch '$repo/.first-ran'"
    create_hook_script "$repo" "pre-bump" "02-fail.sh" 'exit 1'
    create_hook_script "$repo" "pre-bump" "03-should-not-run.sh" \
        "touch '$repo/.third-ran'"

    local result
    set +e
    result=$(bash "$RUNNER" pre-bump patch v1.0.0 v1.0.1 "$repo")
    local ec=$?
    set -e

    assert_exit_code 1 "$ec" "should fail" &&
    assert_file_exists "$repo/.first-ran" "first script should have run" &&
    assert_file_not_exists "$repo/.third-ran" "third script should not have run" &&
    assert_json_field "$result" '.hooks_run' "2" "should have run 2 hooks before stopping"
}

test_post_bump_failure_returns_exit_0() {
    local repo
    repo=$(create_test_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    create_hook_script "$repo" "post-bump" "01-fail.sh" 'echo "failed"; exit 1'

    local result
    set +e
    result=$(bash "$RUNNER" post-bump patch v1.0.0 v1.0.1 "$repo")
    local ec=$?
    set -e

    assert_exit_code 0 "$ec" "post-bump should exit 0 even on failure" &&
    assert_json_field "$result" '.status' "ok" "status should be ok"
}

test_post_bump_failure_includes_warning() {
    local repo
    repo=$(create_test_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    create_hook_script "$repo" "post-bump" "01-fail.sh" 'echo "deploy failed"; exit 1'

    local result
    result=$(bash "$RUNNER" post-bump patch v1.0.0 v1.0.1 "$repo")

    local warn_count
    warn_count=$(echo "$result" | jq '.warnings | length')
    assert_eq "1" "$warn_count" "should have 1 warning" &&

    local warn_hook
    warn_hook=$(echo "$result" | jq -r '.warnings[0].hook')
    assert_eq "01-fail.sh" "$warn_hook" "warning should name the failing hook"
}

test_post_bump_failure_continues_chain() {
    local repo
    repo=$(create_test_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    create_hook_script "$repo" "post-bump" "01-fail.sh" 'exit 1'
    create_hook_script "$repo" "post-bump" "02-should-run.sh" \
        "touch '$repo/.second-ran'"

    bash "$RUNNER" post-bump patch v1.0.0 v1.0.1 "$repo" > /dev/null

    assert_file_exists "$repo/.second-ran" "second script should still run after first fails"
}

test_post_bump_multiple_failures_collected() {
    local repo
    repo=$(create_test_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    create_hook_script "$repo" "post-bump" "01-fail-a.sh" 'exit 1'
    create_hook_script "$repo" "post-bump" "02-fail-b.sh" 'exit 2'

    local result
    result=$(bash "$RUNNER" post-bump patch v1.0.0 v1.0.1 "$repo")

    local warn_count
    warn_count=$(echo "$result" | jq '.warnings | length')
    assert_eq "2" "$warn_count" "should collect 2 warnings" &&
    assert_json_field "$result" '.hooks_run' "2" "both hooks should have run"
}
