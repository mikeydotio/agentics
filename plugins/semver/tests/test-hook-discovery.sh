#!/usr/bin/env bash
# Tests: Hook discovery, graceful degradation, non-executable skipping

test_discovers_pre_bump_scripts() {
    local repo
    repo=$(create_test_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    create_hook_script "$repo" "pre-bump" "01-check.sh" 'echo "ok"'

    local result
    result=$(bash "$RUNNER" pre-bump patch v1.0.0 v1.0.1 "$repo")
    local ec=$?

    assert_exit_code 0 "$ec" "should succeed" &&
    assert_json_field "$result" '.hooks_run' "1" "should find 1 hook"
}

test_discovers_post_bump_scripts() {
    local repo
    repo=$(create_test_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    create_hook_script "$repo" "post-bump" "01-notify.sh" 'echo "notified"'

    local result
    result=$(bash "$RUNNER" post-bump patch v1.0.0 v1.0.1 "$repo")
    local ec=$?

    assert_exit_code 0 "$ec" "should succeed" &&
    assert_json_field "$result" '.hooks_run' "1" "should find 1 hook"
}

test_discovers_multiple_scripts() {
    local repo
    repo=$(create_test_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    create_hook_script "$repo" "pre-bump" "01-a.sh" 'echo "a"'
    create_hook_script "$repo" "pre-bump" "02-b.sh" 'echo "b"'
    create_hook_script "$repo" "pre-bump" "03-c.sh" 'echo "c"'

    local result
    result=$(bash "$RUNNER" pre-bump minor v1.0.0 v1.1.0 "$repo")

    assert_json_field "$result" '.hooks_run' "3" "should find 3 hooks"
}

test_no_hooks_directory() {
    local repo
    repo=$(create_test_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    # No .semver/hooks/ at all
    local result
    result=$(bash "$RUNNER" pre-bump patch v1.0.0 v1.0.1 "$repo")
    local ec=$?

    assert_exit_code 0 "$ec" "should succeed with no hooks dir" &&
    assert_json_field "$result" '.hooks_run' "0" "should report 0 hooks" &&
    assert_json_field "$result" '.prompt_hook' "null" "prompt_hook should be null"
}

test_empty_hooks_directory() {
    local repo
    repo=$(create_test_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    mkdir -p "$repo/.semver/hooks/pre-bump"

    local result
    result=$(bash "$RUNNER" pre-bump patch v1.0.0 v1.0.1 "$repo")
    local ec=$?

    assert_exit_code 0 "$ec" "should succeed with empty dir" &&
    assert_json_field "$result" '.hooks_run' "0" "should report 0 hooks"
}

test_skips_non_executable_sh() {
    local repo
    repo=$(create_test_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    create_hook_script "$repo" "pre-bump" "01-exec.sh" 'echo "runs"'
    # Create non-executable .sh file
    mkdir -p "$repo/.semver/hooks/pre-bump"
    echo '#!/bin/bash' > "$repo/.semver/hooks/pre-bump/02-noexec.sh"
    # Do NOT chmod +x

    local result
    result=$(bash "$RUNNER" pre-bump patch v1.0.0 v1.0.1 "$repo")

    assert_json_field "$result" '.hooks_run' "1" "should only run the executable one"
}

test_skips_non_sh_files() {
    local repo
    repo=$(create_test_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    create_hook_script "$repo" "pre-bump" "01-real.sh" 'echo "runs"'
    # Create non-.sh files
    mkdir -p "$repo/.semver/hooks/pre-bump"
    echo "readme" > "$repo/.semver/hooks/pre-bump/README.md"
    echo "notes" > "$repo/.semver/hooks/pre-bump/notes.txt"
    chmod +x "$repo/.semver/hooks/pre-bump/README.md"
    chmod +x "$repo/.semver/hooks/pre-bump/notes.txt"

    local result
    result=$(bash "$RUNNER" pre-bump patch v1.0.0 v1.0.1 "$repo")

    assert_json_field "$result" '.hooks_run' "1" "should only run .sh files"
}
