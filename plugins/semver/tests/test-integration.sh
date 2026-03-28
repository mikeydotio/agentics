#!/usr/bin/env bash
# Integration tests: simulate the full bump flow with hooks

test_full_bump_with_pre_and_post_hooks() {
    local repo
    repo=$(create_test_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    add_feature_commit "$repo" "feat: add search"

    local log="$repo/.hook-log"
    create_hook_script "$repo" "pre-bump" "01-log.sh" \
        "echo \"pre:\${OLD_VERSION}→\${NEW_VERSION}\" >> '$log'"
    create_hook_script "$repo" "post-bump" "01-log.sh" \
        "echo \"post:\${OLD_VERSION}→\${NEW_VERSION}\" >> '$log'"

    simulate_bump "$repo" minor

    assert_eq "0" "$SIM_EXIT_CODE" "bump should succeed" &&
    assert_file_contains "$log" "pre:v1.0.0→v1.1.0" "pre-bump log entry" &&
    assert_file_contains "$log" "post:v1.0.0→v1.1.0" "post-bump log entry" &&

    local version
    version=$(cat "$repo/VERSION" | tr -d '[:space:]')
    assert_eq "v1.1.0" "$version" "VERSION should be v1.1.0" &&

    local tag_exists
    tag_exists=$(git -C "$repo" tag -l "v1.1.0")
    assert_eq "v1.1.0" "$tag_exists" "tag v1.1.0 should exist"
}

test_pre_bump_failure_prevents_version_change() {
    local repo
    repo=$(create_test_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    add_feature_commit "$repo" "feat: new thing"

    create_hook_script "$repo" "pre-bump" "01-fail.sh" 'echo "blocked"; exit 1'

    simulate_bump "$repo" minor

    assert_ne "0" "$SIM_EXIT_CODE" "bump should have failed" &&

    local version
    version=$(cat "$repo/VERSION" | tr -d '[:space:]')
    assert_eq "v1.0.0" "$version" "VERSION should be unchanged" &&

    local tag_exists
    tag_exists=$(git -C "$repo" tag -l "v1.1.0")
    assert_eq "" "$tag_exists" "no new tag should exist" &&

    local log
    log=$(git -C "$repo" log --oneline | head -1)
    assert_file_not_contains <(echo "$log") "chore(release)" "no release commit"
}

test_post_bump_failure_preserves_version_change() {
    local repo
    repo=$(create_test_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    add_feature_commit "$repo" "feat: something"

    create_hook_script "$repo" "post-bump" "01-fail.sh" 'echo "oops"; exit 1'

    simulate_bump "$repo" patch

    assert_eq "0" "$SIM_EXIT_CODE" "bump should succeed despite post-hook failure" &&

    local version
    version=$(cat "$repo/VERSION" | tr -d '[:space:]')
    assert_eq "v1.0.1" "$version" "VERSION should be v1.0.1" &&

    local tag_exists
    tag_exists=$(git -C "$repo" tag -l "v1.0.1")
    assert_eq "v1.0.1" "$tag_exists" "tag should exist" &&

    # Check warnings in post result
    local warn_count
    warn_count=$(echo "$SIM_RESULT_POST" | jq '.warnings | length')
    assert_eq "1" "$warn_count" "should have 1 post-bump warning"
}

test_hook_execution_timing() {
    local repo
    repo=$(create_test_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    add_feature_commit "$repo" "feat: timing test"

    # Pre-bump hook snapshots VERSION content
    create_hook_script "$repo" "pre-bump" "01-snapshot.sh" \
        "cat '$repo/VERSION' > '$repo/.pre-version-snapshot'"

    # Post-bump hook snapshots VERSION content
    create_hook_script "$repo" "post-bump" "01-snapshot.sh" \
        "cat '$repo/VERSION' > '$repo/.post-version-snapshot'"

    simulate_bump "$repo" minor

    local pre_snap
    pre_snap=$(cat "$repo/.pre-version-snapshot" | tr -d '[:space:]')
    assert_eq "v1.0.0" "$pre_snap" "pre-bump should see old version" &&

    local post_snap
    post_snap=$(cat "$repo/.post-version-snapshot" | tr -d '[:space:]')
    assert_eq "v1.1.0" "$post_snap" "post-bump should see new version"
}

test_no_hooks_bump_unchanged() {
    local repo
    repo=$(create_test_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    add_feature_commit "$repo" "feat: no hooks"

    # No hooks at all
    simulate_bump "$repo" minor

    assert_eq "0" "$SIM_EXIT_CODE" "bump should succeed" &&

    local version
    version=$(cat "$repo/VERSION" | tr -d '[:space:]')
    assert_eq "v1.1.0" "$version" "VERSION should be bumped" &&

    local pre_hooks
    pre_hooks=$(echo "$SIM_RESULT_PRE" | jq '.hooks_run')
    assert_eq "0" "$pre_hooks" "pre-bump should report 0 hooks" &&

    local post_hooks
    post_hooks=$(echo "$SIM_RESULT_POST" | jq '.hooks_run')
    assert_eq "0" "$post_hooks" "post-bump should report 0 hooks"
}

test_reentrancy_during_bump_flow() {
    local repo
    repo=$(create_test_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    add_feature_commit "$repo" "feat: re-entrancy"

    # Hook that tries to invoke the runner with the guard already set
    # Must disable set -e to capture exit code of failing nested call
    mkdir -p "$repo/.semver/hooks/pre-bump"
    cat > "$repo/.semver/hooks/pre-bump/01-nested.sh" << SCRIPT
#!/usr/bin/env bash
set +e
SEMVER_BUMP_IN_PROGRESS=1 bash '$RUNNER' pre-bump patch v1.0.0 v1.0.1 '$repo' > '$repo/.nested-result' 2>&1
echo \$? > '$repo/.nested-exit'
exit 0
SCRIPT
    chmod +x "$repo/.semver/hooks/pre-bump/01-nested.sh"

    simulate_bump "$repo" minor

    assert_eq "0" "$SIM_EXIT_CODE" "outer bump should succeed" &&

    local nested_exit
    nested_exit=$(cat "$repo/.nested-exit" | tr -d '[:space:]')
    assert_eq "2" "$nested_exit" "nested invocation should be blocked"
}

test_multiple_hooks_ordering_in_full_flow() {
    local repo
    repo=$(create_test_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    add_feature_commit "$repo" "feat: ordering"

    local log="$repo/.order-log"
    create_hook_script "$repo" "pre-bump"  "01-first.sh"  "echo 'pre:first' >> '$log'"
    create_hook_script "$repo" "pre-bump"  "02-second.sh" "echo 'pre:second' >> '$log'"
    create_hook_script "$repo" "post-bump" "01-alpha.sh"  "echo 'post:alpha' >> '$log'"
    create_hook_script "$repo" "post-bump" "02-beta.sh"   "echo 'post:beta' >> '$log'"

    simulate_bump "$repo" minor

    local order
    order=$(cat "$log" | tr '\n' '|')
    assert_eq "pre:first|pre:second|post:alpha|post:beta|" "$order" "full flow ordering"
}

test_bump_types_passed_correctly() {
    local repo
    repo=$(create_test_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    add_feature_commit "$repo" "feat: major test"

    create_hook_script "$repo" "pre-bump" "01-log.sh" \
        "echo \"\$BUMP_TYPE\" >> '$repo/.bump-types'"

    # Major bump
    simulate_bump "$repo" major

    local type1
    type1=$(head -1 "$repo/.bump-types" | tr -d '[:space:]')
    assert_eq "major" "$type1" "first bump should be major" &&

    # Reset and do patch
    add_feature_commit "$repo" "fix: patch test"
    simulate_bump "$repo" patch

    local type2
    type2=$(tail -1 "$repo/.bump-types" | tr -d '[:space:]')
    assert_eq "patch" "$type2" "second bump should be patch"
}
