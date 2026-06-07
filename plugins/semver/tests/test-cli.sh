#!/usr/bin/env bash
# Tests for semver-cli Python script
# Covers: current, validate, bump gather/execute/first-version, changelog,
#         tracking start/stop-gather, auto-bump start/stop, repair diagnose,
#         and error cases.

# --- Helper: create a semver-tracked repo ---

create_semver_repo() {
    local dir
    dir=$(mktemp -d "/tmp/semver-test-XXXXXX")
    cd "$dir"
    git init -q
    git branch -M main
    git config user.name "Test"
    git config user.email "test@test.com"

    # Initial commit
    echo "init" > README.md
    git add README.md
    git commit -q -m "chore: initial commit"

    # Initialize semver config
    mkdir -p .semver
    cat > .semver/config.yaml << 'YAML'
tracking: true
auto_bump: false
auto_bump_confirm: true
version_prefix: "v"
git_tagging: true
changelog_format: "grouped"
target_branch: "main"
YAML

    echo "v1.0.0" > VERSION
    cat > CHANGELOG.md << 'CL'
# Changelog

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [v1.0.0] - 2026-01-01

- Initial version tracking

_[manual]_
CL
    git add -A
    git commit -q -m "chore: initialize semver tracking"
    git tag v1.0.0

    echo "$dir"
}


# ═══════════════════════════════════════════════════════════════════════════
# 1. current command
# ═══════════════════════════════════════════════════════════════════════════

test_current_tracking_active() {
    local repo
    repo=$(create_semver_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    local out
    out=$(cd "$repo" && "$CLI" current)

    assert_json_field "$out" ".ok" "true" "ok should be true" &&
    assert_json_field "$out" ".tracking" "true" "tracking should be true" &&
    assert_json_field "$out" ".version" "v1.0.0" "version should be v1.0.0" &&
    assert_json_field "$out" ".version_set" "true" "version_set should be true" &&
    assert_json_field "$out" ".auto_bump" "false" "auto_bump should be false" &&
    assert_json_field "$out" ".git_tagging" "true" "git_tagging should be true" &&
    assert_json_field "$out" ".changelog_format" "grouped" "changelog_format should be grouped" &&
    assert_json_field "$out" ".target_branch" "main" "target_branch should be main"
}

test_current_tracking_inactive() {
    local repo
    repo=$(create_semver_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    # Disable tracking
    sed_inplace 's/tracking: true/tracking: false/' "$repo/.semver/config.yaml"

    local out
    out=$(cd "$repo" && "$CLI" current)

    assert_json_field "$out" ".ok" "true" "ok should be true" &&
    assert_json_field "$out" ".tracking" "false" "tracking should be false" &&
    assert_json_field "$out" ".config_exists" "true" "config_exists should be true"
}

test_current_no_config() {
    local repo
    repo=$(mktemp -d "/tmp/semver-test-XXXXXX")
    trap "cleanup_test_repo '$repo'" RETURN

    cd "$repo"
    git init -q
    git branch -M main
    git config user.name "Test"
    git config user.email "test@test.com"
    echo "init" > README.md
    git add -A
    git commit -q -m "init"

    local out
    out=$(cd "$repo" && "$CLI" current)

    assert_json_field "$out" ".ok" "true" "ok should be true" &&
    assert_json_field "$out" ".tracking" "false" "tracking should be false" &&
    assert_json_field "$out" ".config_exists" "false" "config_exists should be false"
}


# ═══════════════════════════════════════════════════════════════════════════
# 2. validate command
# ═══════════════════════════════════════════════════════════════════════════

test_validate_all_passing() {
    local repo
    repo=$(create_semver_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    local out
    out=$(cd "$repo" && "$CLI" validate)

    assert_json_field "$out" ".ok" "true" "ok should be true" &&
    assert_json_field "$out" ".tracking" "true" "tracking should be true" &&
    assert_json_field "$out" ".all_pass" "true" "all_pass should be true" &&
    assert_json_field "$out" ".summary.fail" "0" "no failures"
}

test_validate_version_missing() {
    local repo
    repo=$(create_semver_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    rm "$repo/VERSION"
    git -C "$repo" add -A
    git -C "$repo" commit -q -m "chore: remove VERSION"

    local out
    out=$(cd "$repo" && "$CLI" validate)

    assert_json_field "$out" ".all_pass" "false" "should have failures" &&
    # Check that version_wellformed failed
    local version_status
    version_status=$(echo "$out" | jq -r '.checks[] | select(.name=="version_wellformed") | .status')
    assert_eq "FAIL" "$version_status" "version_wellformed should FAIL"
}

test_validate_tag_missing() {
    local repo
    repo=$(create_semver_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    # Delete the tag
    git -C "$repo" tag -d v1.0.0

    local out
    out=$(cd "$repo" && "$CLI" validate)

    local tag_status
    tag_status=$(echo "$out" | jq -r '.checks[] | select(.name=="tag_exists") | .status')
    assert_eq "FAIL" "$tag_status" "tag_exists should FAIL"
}

test_validate_changelog_missing() {
    local repo
    repo=$(create_semver_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    rm "$repo/CHANGELOG.md"
    git -C "$repo" add -A
    git -C "$repo" commit -q -m "chore: remove changelog"

    local out
    out=$(cd "$repo" && "$CLI" validate)

    local cl_status
    cl_status=$(echo "$out" | jq -r '.checks[] | select(.name=="changelog_entry") | .status')
    assert_eq "FAIL" "$cl_status" "changelog_entry should FAIL"
}

test_validate_tagging_disabled_skips() {
    local repo
    repo=$(create_semver_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    # Disable tagging
    sed_inplace 's/git_tagging: true/git_tagging: false/' "$repo/.semver/config.yaml"

    local out
    out=$(cd "$repo" && "$CLI" validate)

    local tag_status
    tag_status=$(echo "$out" | jq -r '.checks[] | select(.name=="tag_exists") | .status')
    assert_eq "SKIP" "$tag_status" "tag_exists should SKIP when tagging disabled" &&

    local tag_commit_status
    tag_commit_status=$(echo "$out" | jq -r '.checks[] | select(.name=="tag_correct_commit") | .status')
    assert_eq "SKIP" "$tag_commit_status" "tag_correct_commit should SKIP" &&

    local orphan_status
    orphan_status=$(echo "$out" | jq -r '.checks[] | select(.name=="orphaned_tags") | .status')
    assert_eq "SKIP" "$orphan_status" "orphaned_tags should SKIP"
}


# ═══════════════════════════════════════════════════════════════════════════
# 3. bump gather
# ═══════════════════════════════════════════════════════════════════════════

test_bump_gather_clean() {
    local repo
    repo=$(create_semver_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    # Add a feature commit
    echo "feature" > "$repo/feature.txt"
    git -C "$repo" add -A
    git -C "$repo" commit -q -m "feat: add new feature"

    local out
    out=$(cd "$repo" && "$CLI" bump gather minor)

    assert_json_field "$out" ".ok" "true" "ok should be true" &&
    assert_json_field "$out" ".bump_type" "minor" "bump_type should be minor" &&
    assert_json_field "$out" ".old_version" "v1.0.0" "old_version" &&
    assert_json_field "$out" ".new_version" "v1.1.0" "new_version" &&
    assert_json_field "$out" ".on_target_branch" "true" "on_target_branch" &&
    assert_json_field "$out" ".dirty_tree" "false" "dirty_tree should be false" &&
    assert_json_field "$out" ".version_exists" "true" "version_exists"
}

test_bump_gather_dirty_tree() {
    local repo
    repo=$(create_semver_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    # Add a committed feature + dirty file
    echo "feature" > "$repo/feature.txt"
    git -C "$repo" add -A
    git -C "$repo" commit -q -m "feat: add feature"

    echo "uncommitted" > "$repo/dirty.txt"

    local out
    out=$(cd "$repo" && "$CLI" bump gather minor)

    assert_json_field "$out" ".ok" "true" "ok should be true" &&
    assert_json_field "$out" ".dirty_tree" "true" "dirty_tree should be true" &&

    local has_dirty_q
    has_dirty_q=$(echo "$out" | jq '.questions_needed | index("dirty_tree") != null')
    assert_eq "true" "$has_dirty_q" "should ask about dirty_tree"
}

test_bump_gather_wrong_branch() {
    local repo
    repo=$(create_semver_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    git -C "$repo" checkout -q -b feature-branch
    echo "feature" > "$repo/feature.txt"
    git -C "$repo" add -A
    git -C "$repo" commit -q -m "feat: add feature"

    local out
    out=$(cd "$repo" && "$CLI" bump gather minor)

    assert_json_field "$out" ".ok" "true" "ok should be true" &&
    assert_json_field "$out" ".on_target_branch" "false" "should not be on target branch" &&
    assert_json_field "$out" ".current_branch" "feature-branch" "current_branch" &&

    local has_branch_q
    has_branch_q=$(echo "$out" | jq '.questions_needed | index("wrong_branch") != null')
    assert_eq "true" "$has_branch_q" "should ask about wrong_branch"
}

test_bump_gather_no_commits() {
    local repo
    repo=$(create_semver_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    # No commits since last version change
    local out
    out=$(cd "$repo" && "$CLI" bump gather minor)

    assert_json_field "$out" ".ok" "true" "ok should be true" &&
    assert_json_field "$out" ".no_commits" "true" "no_commits should be true" &&
    assert_json_field "$out" ".commits_since_last_bump" "0" "zero commits"
}

test_bump_gather_force_overrides_no_commits() {
    local repo
    repo=$(create_semver_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    local out
    out=$(cd "$repo" && "$CLI" bump gather minor --force)

    assert_json_field "$out" ".ok" "true" "ok should be true" &&
    assert_json_field "$out" ".force" "true" "force should be true" &&

    # With --force, no_commits should NOT appear (it shouldn't short-circuit)
    local has_no_commits
    has_no_commits=$(echo "$out" | jq 'has("no_commits")')
    assert_eq "false" "$has_no_commits" "no_commits should not appear with --force"
}


# ═══════════════════════════════════════════════════════════════════════════
# 4. bump execute
# ═══════════════════════════════════════════════════════════════════════════

test_bump_execute_minor() {
    local repo
    repo=$(create_semver_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    # Add a feature commit
    echo "feature" > "$repo/feature.txt"
    git -C "$repo" add -A
    git -C "$repo" commit -q -m "feat: add awesome feature"

    local out
    out=$(cd "$repo" && "$CLI" bump execute minor)

    assert_json_field "$out" ".ok" "true" "ok should be true" &&
    assert_json_field "$out" ".old_version" "v1.0.0" "old_version" &&
    assert_json_field "$out" ".new_version" "v1.1.0" "new_version" &&
    assert_json_field "$out" ".tag_created" "true" "tag should be created" &&

    # Verify VERSION file
    local version
    version=$(cat "$repo/VERSION" | tr -d '[:space:]')
    assert_eq "v1.1.0" "$version" "VERSION file content" &&

    # Verify git tag
    local tag_check
    tag_check=$(git -C "$repo" tag -l "v1.1.0")
    assert_eq "v1.1.0" "$tag_check" "git tag should exist" &&

    # Verify CHANGELOG has entry
    assert_file_contains "$repo/CHANGELOG.md" "## \\[v1.1.0\\]" "CHANGELOG should have v1.1.0 entry" &&

    # Verify CHANGELOG has the feature
    assert_file_contains "$repo/CHANGELOG.md" "add awesome feature" "CHANGELOG should have feature" &&

    # Verify commit message
    local commit_msg
    commit_msg=$(git -C "$repo" log -1 --format=%s)
    assert_eq "chore(release): v1.1.0" "$commit_msg" "commit message" &&

    # Verify verification block
    assert_json_field "$out" ".verification.version_matches" "true" "version verification" &&
    assert_json_field "$out" ".verification.tag_exists" "true" "tag verification" &&
    assert_json_field "$out" ".verification.changelog_has_entry" "true" "changelog verification"
}

test_bump_execute_force_no_commits() {
    local repo
    repo=$(create_semver_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    local out
    out=$(cd "$repo" && "$CLI" bump execute patch --force)

    assert_json_field "$out" ".ok" "true" "ok should be true" &&
    assert_json_field "$out" ".new_version" "v1.0.1" "new_version" &&

    local version
    version=$(cat "$repo/VERSION" | tr -d '[:space:]')
    assert_eq "v1.0.1" "$version" "VERSION should be v1.0.1" &&

    # CHANGELOG should note version-only adjustment
    assert_file_contains "$repo/CHANGELOG.md" "Version-only adjustment" "CHANGELOG should have force note"
}

test_bump_execute_stash_dirty() {
    local repo
    repo=$(create_semver_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    # Add a tracked commit
    echo "feature" > "$repo/feature.txt"
    git -C "$repo" add -A
    git -C "$repo" commit -q -m "feat: add feature"

    # Create dirty file
    echo "uncommitted work" > "$repo/dirty.txt"

    local out
    out=$(cd "$repo" && "$CLI" bump execute minor --dirty-action stash)

    assert_json_field "$out" ".ok" "true" "ok should be true" &&
    assert_json_field "$out" ".stash_applied" "true" "stash should be applied back" &&

    # Dirty file should still be present
    assert_file_exists "$repo/dirty.txt" "dirty file should exist after stash pop"
}


# ═══════════════════════════════════════════════════════════════════════════
# 5. bump first-version
# ═══════════════════════════════════════════════════════════════════════════

test_bump_first_version() {
    local repo
    repo=$(mktemp -d "/tmp/semver-test-XXXXXX")
    trap "cleanup_test_repo '$repo'" RETURN

    cd "$repo"
    git init -q
    git branch -M main
    git config user.name "Test"
    git config user.email "test@test.com"
    echo "init" > README.md
    git add -A
    git commit -q -m "init"

    # Set up config but no VERSION/CHANGELOG
    mkdir -p .semver
    cat > .semver/config.yaml << 'YAML'
tracking: true
auto_bump: false
auto_bump_confirm: true
version_prefix: "v"
git_tagging: true
changelog_format: "grouped"
target_branch: "main"
YAML
    git add -A
    git commit -q -m "chore: add config"

    local out
    out=$(cd "$repo" && "$CLI" bump first-version "0.1.0")

    assert_json_field "$out" ".ok" "true" "ok should be true" &&
    assert_json_field "$out" ".version" "v0.1.0" "version should be v0.1.0" &&
    assert_json_field "$out" ".changelog_created" "true" "changelog should be created" &&
    assert_json_field "$out" ".tag_created" "true" "tag should be created" &&

    # Verify files
    local version
    version=$(cat "$repo/VERSION" | tr -d '[:space:]')
    assert_eq "v0.1.0" "$version" "VERSION content" &&

    assert_file_exists "$repo/CHANGELOG.md" "CHANGELOG should exist" &&
    assert_file_contains "$repo/CHANGELOG.md" "## \\[v0.1.0\\]" "CHANGELOG should have entry" &&
    assert_file_contains "$repo/CHANGELOG.md" "Initial version tracking" "CHANGELOG should have initial note" &&

    local tag_check
    tag_check=$(git -C "$repo" tag -l "v0.1.0")
    assert_eq "v0.1.0" "$tag_check" "tag should exist"
}


# ═══════════════════════════════════════════════════════════════════════════
# 6. Changelog generation
# ═══════════════════════════════════════════════════════════════════════════

test_changelog_grouped_format() {
    local repo
    repo=$(create_semver_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    # Add various types of commits
    echo "a" > "$repo/a.txt"
    git -C "$repo" add -A
    git -C "$repo" commit -q -m "feat: add new endpoint"

    echo "b" > "$repo/b.txt"
    git -C "$repo" add -A
    git -C "$repo" commit -q -m "fix: resolve null pointer"

    echo "c" > "$repo/c.txt"
    git -C "$repo" add -A
    git -C "$repo" commit -q -m "refactor: simplify parser"

    local out
    out=$(cd "$repo" && "$CLI" bump execute minor)

    assert_json_field "$out" ".ok" "true" "ok should be true" &&

    # Check grouped headers
    assert_file_contains "$repo/CHANGELOG.md" "### Added" "should have Added group" &&
    assert_file_contains "$repo/CHANGELOG.md" "### Fixed" "should have Fixed group" &&
    assert_file_contains "$repo/CHANGELOG.md" "### Changed" "should have Changed group" &&

    # Check commit subjects are cleaned (prefix stripped)
    assert_file_contains "$repo/CHANGELOG.md" "add new endpoint" "feat commit in changelog" &&
    assert_file_contains "$repo/CHANGELOG.md" "resolve null pointer" "fix commit in changelog" &&
    assert_file_contains "$repo/CHANGELOG.md" "simplify parser" "refactor commit in changelog"
}

test_changelog_flat_format() {
    local repo
    repo=$(create_semver_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    # Switch to flat format
    sed_inplace 's/changelog_format: "grouped"/changelog_format: "flat"/' "$repo/.semver/config.yaml"

    echo "a" > "$repo/a.txt"
    git -C "$repo" add -A
    git -C "$repo" commit -q -m "feat: add button"

    echo "b" > "$repo/b.txt"
    git -C "$repo" add -A
    git -C "$repo" commit -q -m "fix: alignment issue"

    local out
    out=$(cd "$repo" && "$CLI" bump execute minor)

    assert_json_field "$out" ".ok" "true" "ok should be true" &&

    # Flat format should NOT have ### group headers
    assert_file_not_contains "$repo/CHANGELOG.md" "### Added" "flat format should not have group headers" &&

    # Should still contain commit info in flat style (hash + subject on each line)
    assert_file_contains "$repo/CHANGELOG.md" "feat: add button" "flat should have full subject" &&
    assert_file_contains "$repo/CHANGELOG.md" "fix: alignment issue" "flat should have fix subject"
}

test_changelog_filters_release_commits() {
    local repo
    repo=$(create_semver_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    # Add a feature commit, then do a bump
    echo "a" > "$repo/a.txt"
    git -C "$repo" add -A
    git -C "$repo" commit -q -m "feat: first feature"

    cd "$repo" && "$CLI" bump execute minor > /dev/null

    # Now add another feature and bump again
    echo "b" > "$repo/b.txt"
    git -C "$repo" add -A
    git -C "$repo" commit -q -m "feat: second feature"

    local out
    out=$(cd "$repo" && "$CLI" bump execute minor)

    assert_json_field "$out" ".ok" "true" "ok should be true" &&

    # The v1.2.0 entry should NOT contain "chore(release): v1.1.0"
    # Extract just the v1.2.0 section from the changelog
    local v120_section
    v120_section=$(sed -n '/## \[v1.2.0\]/,/## \[v1.1.0\]/p' "$repo/CHANGELOG.md" | sed '$d')
    local has_release
    has_release=$(echo "$v120_section" | grep -c "chore(release)" || true)
    assert_eq "0" "$has_release" "release commits should be filtered out"
}


# ═══════════════════════════════════════════════════════════════════════════
# 7. tracking start
# ═══════════════════════════════════════════════════════════════════════════

test_tracking_start_fresh_defaults() {
    local repo
    repo=$(mktemp -d "/tmp/semver-test-XXXXXX")
    trap "cleanup_test_repo '$repo'" RETURN

    cd "$repo"
    git init -q
    git branch -M main
    git config user.name "Test"
    git config user.email "test@test.com"
    echo "init" > README.md
    git add -A
    git commit -q -m "init"

    local out
    out=$(cd "$repo" && "$CLI" tracking start)

    assert_json_field "$out" ".ok" "true" "ok should be true" &&
    assert_json_field "$out" ".action" "fresh_start" "action should be fresh_start" &&
    assert_json_field "$out" ".git_tagging" "true" "tagging should default to true" &&
    assert_json_field "$out" ".changelog_format" "grouped" "format should default to grouped" &&
    assert_json_field "$out" ".version_prefix" "v" "prefix should default to v" &&
    assert_json_field "$out" ".version_set" "false" "no version should be set without --version" &&

    # Config file should exist
    assert_file_exists "$repo/.semver/config.yaml" "config should exist" &&
    assert_file_contains "$repo/.semver/config.yaml" "tracking: true" "tracking should be true" &&

    # CLAUDE.md should be injected
    assert_file_exists "$repo/CLAUDE.md" "CLAUDE.md should exist" &&
    assert_file_contains "$repo/CLAUDE.md" "semver:start" "CLAUDE.md should have semver section"
}

test_tracking_start_with_version_and_no_tags() {
    local repo
    repo=$(mktemp -d "/tmp/semver-test-XXXXXX")
    trap "cleanup_test_repo '$repo'" RETURN

    cd "$repo"
    git init -q
    git branch -M main
    git config user.name "Test"
    git config user.email "test@test.com"
    echo "init" > README.md
    git add -A
    git commit -q -m "init"

    local out
    out=$(cd "$repo" && "$CLI" tracking start --version "2.0.0" --no-tags)

    assert_json_field "$out" ".ok" "true" "ok should be true" &&
    assert_json_field "$out" ".version_set" "true" "version should be set" &&
    assert_json_field "$out" ".version" "v2.0.0" "version should be v2.0.0" &&
    assert_json_field "$out" ".tag_created" "false" "no tag with --no-tags" &&
    assert_json_field "$out" ".git_tagging" "false" "git_tagging should be false" &&

    assert_file_exists "$repo/VERSION" "VERSION should exist" &&
    assert_file_exists "$repo/CHANGELOG.md" "CHANGELOG should exist" &&

    # No tag should exist
    local tag_check
    tag_check=$(git -C "$repo" tag -l "v2.0.0")
    assert_eq "" "$tag_check" "no tag should exist"
}


# ═══════════════════════════════════════════════════════════════════════════
# 8. tracking stop-gather
# ═══════════════════════════════════════════════════════════════════════════

test_tracking_stop_gather() {
    local repo
    repo=$(create_semver_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    local out
    out=$(cd "$repo" && "$CLI" tracking stop-gather)

    assert_json_field "$out" ".ok" "true" "ok should be true" &&
    assert_json_field "$out" ".tracking" "true" "tracking should be true" &&
    assert_json_field "$out" ".version" "v1.0.0" "version should be v1.0.0" &&
    assert_json_field "$out" ".has_version" "true" "has_version should be true" &&
    assert_json_field "$out" ".has_changelog" "true" "has_changelog should be true" &&
    assert_json_field "$out" ".git_tagging" "true" "git_tagging should be true" &&

    # Should have tags listed
    local tag_count
    tag_count=$(echo "$out" | jq '.tag_count')
    assert_eq "1" "$tag_count" "should have 1 tag" &&

    # Questions should include archive_items and tag_deletion
    local has_archive_q
    has_archive_q=$(echo "$out" | jq '.questions_needed | index("archive_items") != null')
    assert_eq "true" "$has_archive_q" "should ask about archive_items" &&

    local has_tag_q
    has_tag_q=$(echo "$out" | jq '.questions_needed | index("tag_deletion") != null')
    assert_eq "true" "$has_tag_q" "should ask about tag_deletion"
}

test_tracking_stop_gather_inactive() {
    local repo
    repo=$(create_semver_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    sed_inplace 's/tracking: true/tracking: false/' "$repo/.semver/config.yaml"

    local out
    out=$(cd "$repo" && "$CLI" tracking stop-gather)

    assert_json_field "$out" ".ok" "false" "ok should be false for inactive tracking" &&
    assert_json_field "$out" ".error" "tracking_inactive" "error should be tracking_inactive"
}


# ═══════════════════════════════════════════════════════════════════════════
# 9. auto-bump start/stop
# ═══════════════════════════════════════════════════════════════════════════

test_auto_bump_start() {
    local repo
    repo=$(create_semver_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    local out
    out=$(cd "$repo" && "$CLI" auto-bump start --confirm true)

    assert_json_field "$out" ".ok" "true" "ok should be true" &&
    assert_json_field "$out" ".auto_bump" "true" "auto_bump should be true" &&

    # Verify config updated
    assert_file_contains "$repo/.semver/config.yaml" "auto_bump: true" "config should have auto_bump true"
}

test_auto_bump_start_no_confirm() {
    local repo
    repo=$(create_semver_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    local out
    out=$(cd "$repo" && "$CLI" auto-bump start --confirm false)

    assert_json_field "$out" ".ok" "true" "ok should be true" &&
    assert_json_field "$out" ".auto_bump" "true" "auto_bump should be true" &&
    assert_json_field "$out" ".auto_bump_confirm" "false" "auto_bump_confirm should be false" &&

    assert_file_contains "$repo/.semver/config.yaml" "auto_bump_confirm: false" "config should have confirm false"
}

test_auto_bump_stop() {
    local repo
    repo=$(create_semver_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    # First enable
    cd "$repo" && "$CLI" auto-bump start > /dev/null

    local out
    out=$(cd "$repo" && "$CLI" auto-bump stop)

    assert_json_field "$out" ".ok" "true" "ok should be true" &&
    assert_json_field "$out" ".auto_bump" "false" "auto_bump should be false" &&

    assert_file_contains "$repo/.semver/config.yaml" "auto_bump: false" "config should have auto_bump false"
}


# ═══════════════════════════════════════════════════════════════════════════
# 10. repair diagnose
# ═══════════════════════════════════════════════════════════════════════════

test_repair_diagnose_missing_tag() {
    local repo
    repo=$(create_semver_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    # Delete tag to create a repairable state
    git -C "$repo" tag -d v1.0.0

    local out
    out=$(cd "$repo" && "$CLI" repair diagnose)

    assert_json_field "$out" ".ok" "true" "ok should be true" &&
    assert_json_field "$out" ".all_pass" "false" "should have failures" &&

    # Should have a tag_missing repair
    local repair_issue
    repair_issue=$(echo "$out" | jq -r '.repairs_needed[0].issue')
    assert_eq "tag_missing" "$repair_issue" "should suggest tag_missing repair"
}

test_repair_diagnose_missing_changelog_entry() {
    local repo
    repo=$(create_semver_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    # Bump VERSION manually without updating changelog
    echo "v2.0.0" > "$repo/VERSION"
    git -C "$repo" add VERSION
    git -C "$repo" commit -q -m "chore: manual version bump"
    git -C "$repo" tag v2.0.0

    local out
    out=$(cd "$repo" && "$CLI" repair diagnose)

    assert_json_field "$out" ".ok" "true" "ok should be true" &&
    assert_json_field "$out" ".all_pass" "false" "should have failures" &&

    # Should have a changelog_missing repair
    local has_changelog_repair
    has_changelog_repair=$(echo "$out" | jq '[.repairs_needed[] | select(.issue=="changelog_missing")] | length')
    assert_ne "0" "$has_changelog_repair" "should suggest changelog_missing repair"
}

test_repair_diagnose_all_pass() {
    local repo
    repo=$(create_semver_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    local out
    out=$(cd "$repo" && "$CLI" repair diagnose)

    assert_json_field "$out" ".ok" "true" "ok should be true" &&
    assert_json_field "$out" ".all_pass" "true" "all_pass should be true" &&

    local repair_count
    repair_count=$(echo "$out" | jq '.repairs_needed | length')
    assert_eq "0" "$repair_count" "no repairs needed"
}


# ═══════════════════════════════════════════════════════════════════════════
# 11. Error cases
# ═══════════════════════════════════════════════════════════════════════════

test_reentrancy_guard() {
    local repo
    repo=$(create_semver_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    echo "feature" > "$repo/feature.txt"
    git -C "$repo" add -A
    git -C "$repo" commit -q -m "feat: test reentrancy"

    local out
    local ec
    set +e
    out=$(cd "$repo" && SEMVER_BUMP_IN_PROGRESS=1 "$CLI" bump gather minor 2>&1)
    ec=$?
    set -e

    # Should exit 0 (it outputs JSON with ok=false, not exit code 1, per the code)
    # Actually the code calls output() which exits 0 for the reentrancy case in gather
    assert_json_field "$out" ".ok" "false" "ok should be false" &&
    assert_json_field "$out" ".error" "reentrancy" "error should be reentrancy"
}

test_bump_gather_tracking_inactive() {
    local repo
    repo=$(create_semver_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    sed_inplace 's/tracking: true/tracking: false/' "$repo/.semver/config.yaml"

    local out
    out=$(cd "$repo" && "$CLI" bump gather minor)

    assert_json_field "$out" ".ok" "false" "ok should be false" &&
    assert_json_field "$out" ".error" "tracking_inactive" "error should be tracking_inactive"
}

test_bump_execute_no_version_file() {
    local repo
    repo=$(create_semver_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    rm "$repo/VERSION"
    git -C "$repo" add -A
    git -C "$repo" commit -q -m "chore: remove VERSION"

    local out
    local ec
    set +e
    out=$(cd "$repo" && "$CLI" bump execute minor 2>&1)
    ec=$?
    set -e

    assert_json_field "$out" ".ok" "false" "ok should be false" &&
    assert_json_field "$out" ".error" "no_version" "error should be no_version" &&
    assert_exit_code "1" "$ec" "exit code should be 1"
}

test_bump_execute_major_version() {
    local repo
    repo=$(create_semver_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    echo "breaking" > "$repo/break.txt"
    git -C "$repo" add -A
    git -C "$repo" commit -q -m "feat!: breaking API change"

    local out
    out=$(cd "$repo" && "$CLI" bump execute major)

    assert_json_field "$out" ".ok" "true" "ok should be true" &&
    assert_json_field "$out" ".new_version" "v2.0.0" "major bump to v2.0.0" &&

    local version
    version=$(cat "$repo/VERSION" | tr -d '[:space:]')
    assert_eq "v2.0.0" "$version" "VERSION should be v2.0.0" &&

    local tag_check
    tag_check=$(git -C "$repo" tag -l "v2.0.0")
    assert_eq "v2.0.0" "$tag_check" "v2.0.0 tag should exist"
}

test_bump_execute_patch_version() {
    local repo
    repo=$(create_semver_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    echo "fix" > "$repo/fix.txt"
    git -C "$repo" add -A
    git -C "$repo" commit -q -m "fix: correct off-by-one error"

    local out
    out=$(cd "$repo" && "$CLI" bump execute patch)

    assert_json_field "$out" ".ok" "true" "ok should be true" &&
    assert_json_field "$out" ".new_version" "v1.0.1" "patch bump to v1.0.1" &&

    local version
    version=$(cat "$repo/VERSION" | tr -d '[:space:]')
    assert_eq "v1.0.1" "$version" "VERSION should be v1.0.1"
}

test_auto_bump_tracking_inactive() {
    local repo
    repo=$(mktemp -d "/tmp/semver-test-XXXXXX")
    trap "cleanup_test_repo '$repo'" RETURN

    cd "$repo"
    git init -q
    git branch -M main
    git config user.name "Test"
    git config user.email "test@test.com"
    echo "init" > README.md
    git add -A
    git commit -q -m "init"

    local out
    local ec
    set +e
    out=$(cd "$repo" && "$CLI" auto-bump start 2>&1)
    ec=$?
    set -e

    assert_json_field "$out" ".ok" "false" "ok should be false" &&
    assert_json_field "$out" ".error" "tracking_inactive" "error should be tracking_inactive" &&
    assert_exit_code "1" "$ec" "exit code should be 1"
}

test_validate_tracking_inactive_returns_ok() {
    local repo
    repo=$(create_semver_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    sed_inplace 's/tracking: true/tracking: false/' "$repo/.semver/config.yaml"

    local out
    out=$(cd "$repo" && "$CLI" validate)

    # validate with inactive tracking is ok=true (informational, not error)
    assert_json_field "$out" ".ok" "true" "ok should be true" &&
    assert_json_field "$out" ".tracking" "false" "tracking should be false"
}

test_bump_first_version_invalid_format() {
    local repo
    repo=$(mktemp -d "/tmp/semver-test-XXXXXX")
    trap "cleanup_test_repo '$repo'" RETURN

    cd "$repo"
    git init -q
    git branch -M main
    git config user.name "Test"
    git config user.email "test@test.com"
    echo "init" > README.md
    git add -A
    git commit -q -m "init"

    mkdir -p .semver
    cat > .semver/config.yaml << 'YAML'
tracking: true
auto_bump: false
auto_bump_confirm: true
version_prefix: "v"
git_tagging: true
changelog_format: "grouped"
target_branch: "main"
YAML
    git add -A
    git commit -q -m "chore: add config"

    local out
    local ec
    set +e
    out=$(cd "$repo" && "$CLI" bump first-version "not-a-version" 2>&1)
    ec=$?
    set -e

    assert_json_field "$out" ".ok" "false" "ok should be false" &&
    assert_json_field "$out" ".error" "invalid_version" "should report invalid_version" &&
    assert_exit_code "1" "$ec" "exit code should be 1"
}
