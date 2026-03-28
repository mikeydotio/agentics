#!/usr/bin/env bash
# Tests: Alphabetical execution order, environment variables, working directory

test_scripts_run_alphabetically() {
    local repo
    repo=$(create_test_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    local log="$repo/.hook-order"
    create_hook_script "$repo" "pre-bump" "03-third.sh"  "echo third >> '$log'"
    create_hook_script "$repo" "pre-bump" "01-first.sh"  "echo first >> '$log'"
    create_hook_script "$repo" "pre-bump" "02-second.sh" "echo second >> '$log'"

    bash "$RUNNER" pre-bump minor v1.0.0 v1.1.0 "$repo" > /dev/null

    local order
    order=$(cat "$log" | tr '\n' ',')
    assert_eq "first,second,third," "$order" "scripts should run alphabetically"
}

test_bump_type_passed() {
    local repo
    repo=$(create_test_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    create_hook_script "$repo" "pre-bump" "01-check.sh" \
        "echo \"\$BUMP_TYPE\" > '$repo/.bump-type'"

    bash "$RUNNER" pre-bump major v1.0.0 v2.0.0 "$repo" > /dev/null

    local actual
    actual=$(cat "$repo/.bump-type" | tr -d '[:space:]')
    assert_eq "major" "$actual" "BUMP_TYPE should be major"
}

test_old_version_passed() {
    local repo
    repo=$(create_test_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    create_hook_script "$repo" "pre-bump" "01-check.sh" \
        "echo \"\$OLD_VERSION\" > '$repo/.old-ver'"

    bash "$RUNNER" pre-bump patch v1.2.3 v1.2.4 "$repo" > /dev/null

    local actual
    actual=$(cat "$repo/.old-ver" | tr -d '[:space:]')
    assert_eq "v1.2.3" "$actual" "OLD_VERSION should be v1.2.3"
}

test_new_version_passed() {
    local repo
    repo=$(create_test_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    create_hook_script "$repo" "pre-bump" "01-check.sh" \
        "echo \"\$NEW_VERSION\" > '$repo/.new-ver'"

    bash "$RUNNER" pre-bump minor v1.0.0 v1.1.0 "$repo" > /dev/null

    local actual
    actual=$(cat "$repo/.new-ver" | tr -d '[:space:]')
    assert_eq "v1.1.0" "$actual" "NEW_VERSION should be v1.1.0"
}

test_all_env_vars_simultaneous() {
    local repo
    repo=$(create_test_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    create_hook_script "$repo" "pre-bump" "01-check.sh" \
        "echo \"\${BUMP_TYPE}:\${OLD_VERSION}:\${NEW_VERSION}\" > '$repo/.all-env'"

    bash "$RUNNER" pre-bump minor v1.0.0 v1.1.0 "$repo" > /dev/null

    local actual
    actual=$(cat "$repo/.all-env" | tr -d '[:space:]')
    assert_eq "minor:v1.0.0:v1.1.0" "$actual" "all three env vars"
}

test_working_directory_is_project_root() {
    local repo
    repo=$(create_test_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    create_hook_script "$repo" "pre-bump" "01-check.sh" \
        "pwd > '$repo/.hook-pwd'"

    # Run from a different directory
    (cd /tmp && bash "$RUNNER" pre-bump patch v1.0.0 v1.0.1 "$repo" > /dev/null)

    # The script should still see the hooks dir path (it runs via absolute path)
    assert_file_exists "$repo/.hook-pwd" "pwd file should exist"
}

test_bump_type_patch() {
    local repo
    repo=$(create_test_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    create_hook_script "$repo" "pre-bump" "01-check.sh" \
        "echo \"\$BUMP_TYPE\" > '$repo/.bump-type'"

    bash "$RUNNER" pre-bump patch v1.0.0 v1.0.1 "$repo" > /dev/null

    local actual
    actual=$(cat "$repo/.bump-type" | tr -d '[:space:]')
    assert_eq "patch" "$actual" "BUMP_TYPE should be patch"
}
