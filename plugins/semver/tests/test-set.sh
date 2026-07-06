#!/usr/bin/env bash
# Tests for `semver-cli set` (assign an explicit version).
# Covers: forward/non-sequential/backward sets, same-version re-cut, tag
#         conflicts, invalid versions, prefix handling, tracking guard, dirty
#         tree, re-entrancy, first-version-via-set, and post-bump hook firing.

# --- Fixtures ---

_set_repo() {
    # Tracking-active repo at v1.0.0 with git_tagging on, tag on the release commit.
    local dir
    dir=$(mktemp -d "/tmp/semver-test-XXXXXX")
    cd "$dir"
    git init -q
    git branch -M main
    git config user.name "Test"
    git config user.email "test@test.com"
    echo "init" > README.md
    git add README.md
    git commit -q -m "chore: initial commit"
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

# --- Tests ---

test_set_forward_creates_commit_and_tag() {
    local repo; repo=$(_set_repo)
    trap "cleanup_test_repo '$repo'" RETURN
    ( cd "$repo" && echo x > f.txt && git add f.txt && git commit -q -m "feat: a feature" )

    local out; out=$(cd "$repo" && "$CLI" set run 2.0.0 --plugin-root /x)

    assert_json_field "$out" ".executed" "true" "should execute on happy path" &&
    assert_json_field "$out" ".new_version" "v2.0.0" "new version" &&
    assert_json_field "$out" ".tag_created" "true" "tag created" &&
    assert_eq "v2.0.0" "$(cat "$repo/VERSION" | tr -d '[:space:]')" "VERSION content" &&
    assert_file_contains "$repo/CHANGELOG.md" "## \\[v2.0.0\\]" "changelog entry" &&
    assert_eq "v2.0.0" "$(git -C "$repo" tag -l v2.0.0)" "tag exists" &&
    assert_eq "chore(release): v2.0.0" "$(git -C "$repo" log -1 --format=%s)" "commit subject"
}

test_set_forward_validate_all_pass() {
    local repo; repo=$(_set_repo)
    trap "cleanup_test_repo '$repo'" RETURN
    ( cd "$repo" && "$CLI" set run 2.0.0 --plugin-root /x >/dev/null )
    local out; out=$(cd "$repo" && "$CLI" validate)
    assert_json_field "$out" ".all_pass" "true" "validate all_pass after set"
}

test_set_nonsequential_forward_executes() {
    local repo; repo=$(_set_repo)
    trap "cleanup_test_repo '$repo'" RETURN
    local out; out=$(cd "$repo" && "$CLI" set run 5.3.2 --plugin-root /x)
    assert_json_field "$out" ".executed" "true" "big forward jump executes" &&
    assert_json_field "$out" ".new_version" "v5.3.2" "new version"
}

test_set_backward_hands_back() {
    local repo; repo=$(_set_repo)
    trap "cleanup_test_repo '$repo'" RETURN
    local out; out=$(cd "$repo" && "$CLI" set run 0.9.0 --plugin-root /x)
    assert_json_field "$out" ".executed" "false" "backward set hands back" &&
    local has_q; has_q=$(echo "$out" | jq '.questions_needed | index("backward_version") != null')
    assert_eq "true" "$has_q" "asks backward_version"
}

test_set_backward_allow_executes() {
    local repo; repo=$(_set_repo)
    trap "cleanup_test_repo '$repo'" RETURN
    local out; out=$(cd "$repo" && "$CLI" set execute 0.9.0 --allow-backward --plugin-root /x)
    assert_json_field "$out" ".executed" "true" "executes with --allow-backward" &&
    assert_eq "v0.9.0" "$(cat "$repo/VERSION" | tr -d '[:space:]')" "VERSION lowered"
}

test_set_recut_same_version_is_noop() {
    local repo; repo=$(_set_repo)
    trap "cleanup_test_repo '$repo'" RETURN
    local head_before; head_before=$(git -C "$repo" rev-parse HEAD)
    local out; out=$(cd "$repo" && "$CLI" set run v1.0.0 --plugin-root /x)

    assert_json_field "$out" ".recut" "true" "recut flagged" &&
    assert_json_field "$out" ".tag_action" "noop" "no-op when tag already correct" &&
    assert_eq "$head_before" "$(git -C "$repo" rev-parse HEAD)" "no new commit" &&
    assert_eq "1" "$(grep -c '## \[v1.0.0\]' "$repo/CHANGELOG.md")" "no duplicate changelog heading"
}

test_set_recut_recreates_missing_tag() {
    local repo; repo=$(_set_repo)
    trap "cleanup_test_repo '$repo'" RETURN
    ( cd "$repo" && git tag -d v1.0.0 >/dev/null )
    local out; out=$(cd "$repo" && "$CLI" set run v1.0.0 --plugin-root /x)
    assert_json_field "$out" ".tag_action" "created" "recreates missing tag" &&
    assert_eq "v1.0.0" "$(git -C "$repo" tag -l v1.0.0)" "tag restored"
}

test_set_recut_validate_all_pass() {
    local repo; repo=$(_set_repo)
    trap "cleanup_test_repo '$repo'" RETURN
    ( cd "$repo" && "$CLI" set run v1.0.0 --plugin-root /x >/dev/null )
    local out; out=$(cd "$repo" && "$CLI" validate)
    assert_json_field "$out" ".all_pass" "true" "validate stays green after re-cut"
}

test_set_tag_conflict_hands_back() {
    local repo; repo=$(_set_repo)
    trap "cleanup_test_repo '$repo'" RETURN
    ( cd "$repo" && git tag v2.0.0 HEAD )  # pre-existing conflicting tag
    local out; out=$(cd "$repo" && "$CLI" set run 2.0.0 --plugin-root /x)
    assert_json_field "$out" ".executed" "false" "tag conflict hands back" &&
    local has_q; has_q=$(echo "$out" | jq '.questions_needed | index("tag_conflict") != null')
    assert_eq "true" "$has_q" "asks tag_conflict"
}

test_set_tag_conflict_overwrite() {
    local repo; repo=$(_set_repo)
    trap "cleanup_test_repo '$repo'" RETURN
    ( cd "$repo" && git tag v2.0.0 HEAD )
    local out; out=$(cd "$repo" && "$CLI" set execute 2.0.0 --overwrite-tag --plugin-root /x)
    assert_json_field "$out" ".executed" "true" "executes with --overwrite-tag" &&
    assert_json_field "$out" ".tag_overwritten" "true" "tag overwritten"
}

test_set_invalid_version_errors() {
    local repo; repo=$(_set_repo)
    trap "cleanup_test_repo '$repo'" RETURN
    local out ec
    set +e
    out=$(cd "$repo" && "$CLI" set run 1.2 --plugin-root /x 2>&1); ec=$?
    set -e
    assert_json_field "$out" ".ok" "false" "invalid version → ok false" &&
    assert_json_field "$out" ".error" "invalid_version" "error code" &&
    assert_exit_code "1" "$ec" "exit 1 on invalid version"
}

test_set_prefix_not_doubled() {
    local repo; repo=$(_set_repo)
    trap "cleanup_test_repo '$repo'" RETURN
    local out; out=$(cd "$repo" && "$CLI" set run v3.0.0 --plugin-root /x)
    assert_json_field "$out" ".new_version" "v3.0.0" "explicit v prefix not doubled"
}

test_set_tracking_inactive_errors() {
    local dir; dir=$(mktemp -d "/tmp/semver-test-XXXXXX")
    trap "cleanup_test_repo '$dir'" RETURN
    ( cd "$dir" && git init -q && git config user.name T && git config user.email t@t.co \
        && echo x > r && git add r && git commit -q -m init )
    local out ec
    set +e
    out=$(cd "$dir" && "$CLI" set run 2.0.0 --plugin-root /x 2>&1); ec=$?
    set -e
    assert_json_field "$out" ".error" "tracking_inactive" "tracking inactive error" &&
    assert_exit_code "1" "$ec" "exit 1"
}

test_set_dirty_tree_hands_back() {
    local repo; repo=$(_set_repo)
    trap "cleanup_test_repo '$repo'" RETURN
    ( cd "$repo" && echo dirty > uncommitted.txt )
    local out; out=$(cd "$repo" && "$CLI" set run 2.0.0 --plugin-root /x)
    assert_json_field "$out" ".executed" "false" "dirty tree hands back" &&
    local has_q; has_q=$(echo "$out" | jq '.questions_needed | index("dirty_tree") != null')
    assert_eq "true" "$has_q" "asks dirty_tree"
}

test_set_reentrancy_blocked() {
    local repo; repo=$(_set_repo)
    trap "cleanup_test_repo '$repo'" RETURN
    local out ec
    set +e
    out=$(cd "$repo" && SEMVER_BUMP_IN_PROGRESS=1 "$CLI" set run 2.0.0 --plugin-root /x 2>&1); ec=$?
    set -e
    assert_json_field "$out" ".error" "reentrancy" "reentrancy blocked" &&
    assert_exit_code "1" "$ec" "exit 1"
}

test_set_first_version_when_none() {
    # Tracking on but no VERSION yet — set should create it (first-version style).
    local dir; dir=$(mktemp -d "/tmp/semver-test-XXXXXX")
    trap "cleanup_test_repo '$dir'" RETURN
    ( cd "$dir" && git init -q && git branch -M main && git config user.name T && git config user.email t@t.co \
        && echo x > r && git add r && git commit -q -m init && mkdir -p .semver )
    cat > "$dir/.semver/config.yaml" << 'YAML'
tracking: true
auto_bump: false
auto_bump_confirm: true
version_prefix: "v"
git_tagging: true
changelog_format: "grouped"
target_branch: "main"
YAML
    ( cd "$dir" && git add -A && git commit -q -m cfg )
    local out; out=$(cd "$dir" && "$CLI" set run 1.0.0 --plugin-root /x)
    assert_json_field "$out" ".executed" "true" "first-version set executes" &&
    assert_eq "v1.0.0" "$(cat "$dir/VERSION" | tr -d '[:space:]')" "VERSION created" &&
    assert_file_contains "$dir/CHANGELOG.md" "## \\[v1.0.0\\]" "changelog created"
}

test_set_post_bump_hook_fires() {
    local repo; repo=$(_set_repo)
    trap "cleanup_test_repo '$repo'" RETURN
    mkdir -p "$repo/.semver/hooks/post-bump"
    cat > "$repo/.semver/hooks/post-bump/01-marker.sh" << 'HOOK'
#!/usr/bin/env bash
echo "$NEW_VERSION" > "$(git rev-parse --show-toplevel)/.hook-ran"
HOOK
    chmod +x "$repo/.semver/hooks/post-bump/01-marker.sh"
    ( cd "$repo" && git add -A && git commit -q -m "add hook" )
    ( cd "$repo" && "$CLI" set run 2.0.0 --plugin-root "$PLUGIN_ROOT" >/dev/null )
    assert_file_exists "$repo/.hook-ran" "post-bump hook ran" &&
    assert_file_contains "$repo/.hook-ran" "v2.0.0" "hook saw NEW_VERSION"
}
