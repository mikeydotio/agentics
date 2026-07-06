#!/usr/bin/env bash
# Tests for `semver-cli init` (one-shot adoption).
# Covers: clean init (default + arg + prefix), invalid version, read-only
#         assessment when artifacts exist, and the enable/adopt/reinit modes.

# --- Fixtures ---

_init_bare_repo() {
    # A git repo with one commit and NO semver artifacts.
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
    echo "$dir"
}

_init_tracked_repo() {
    # Fully tracked repo at v1.0.0 (like a project already using semver).
    local dir; dir=$(_init_bare_repo)
    mkdir -p "$dir/.semver"
    cat > "$dir/.semver/config.yaml" << 'YAML'
tracking: true
auto_bump: true
auto_bump_confirm: true
version_prefix: "v"
git_tagging: true
changelog_format: "grouped"
target_branch: "main"
YAML
    echo "v1.0.0" > "$dir/VERSION"
    printf '# Changelog\n\n## [v1.0.0] - 2026-01-01\n\n- Initial\n\n_[manual]_\n' > "$dir/CHANGELOG.md"
    ( cd "$dir" && git add -A && git commit -q -m "chore: initialize semver tracking" && git tag v1.0.0 )
    echo "$dir"
}

# --- Clean init ---

test_init_clean_default_version() {
    local repo; repo=$(_init_bare_repo)
    trap "cleanup_test_repo '$repo'" RETURN
    local out; out=$(cd "$repo" && "$CLI" init run --plugin-root /x)

    assert_json_field "$out" ".executed" "true" "clean init executes" &&
    assert_json_field "$out" ".action" "fresh_init" "action fresh_init" &&
    assert_json_field "$out" ".version" "v0.1.0" "default version v0.1.0" &&
    assert_file_exists "$repo/.semver/config.yaml" "config created" &&
    assert_file_contains "$repo/.semver/config.yaml" "tracking: true" "tracking on" &&
    assert_file_contains "$repo/.semver/config.yaml" "auto_bump: true" "auto-bump on" &&
    assert_eq "v0.1.0" "$(cat "$repo/VERSION" | tr -d '[:space:]')" "VERSION seeded" &&
    assert_file_exists "$repo/CHANGELOG.md" "changelog created" &&
    assert_file_contains "$repo/CLAUDE.md" "semver:start" "CLAUDE.md injected" &&
    assert_eq "v0.1.0" "$(git -C "$repo" tag -l v0.1.0)" "tag created"
}

test_init_clean_validate_all_pass() {
    local repo; repo=$(_init_bare_repo)
    trap "cleanup_test_repo '$repo'" RETURN
    ( cd "$repo" && "$CLI" init run --plugin-root /x >/dev/null )
    local out; out=$(cd "$repo" && "$CLI" validate)
    assert_json_field "$out" ".all_pass" "true" "validate all_pass after clean init"
}

test_init_clean_with_arg() {
    local repo; repo=$(_init_bare_repo)
    trap "cleanup_test_repo '$repo'" RETURN
    local out; out=$(cd "$repo" && "$CLI" init run v1.2.3 --plugin-root /x)
    assert_json_field "$out" ".version" "v1.2.3" "explicit version" &&
    assert_eq "v1.2.3" "$(git -C "$repo" tag -l v1.2.3)" "tag at requested version"
}

test_init_prefix_none() {
    local repo; repo=$(_init_bare_repo)
    trap "cleanup_test_repo '$repo'" RETURN
    local out; out=$(cd "$repo" && "$CLI" init run 1.0.0 --prefix none --plugin-root /x)
    assert_json_field "$out" ".version" "1.0.0" "no prefix applied" &&
    assert_eq "1.0.0" "$(git -C "$repo" tag -l 1.0.0)" "unprefixed tag"
}

test_init_invalid_version_errors() {
    local repo; repo=$(_init_bare_repo)
    trap "cleanup_test_repo '$repo'" RETURN
    local out ec
    set +e
    out=$(cd "$repo" && "$CLI" init run 9.9 --plugin-root /x 2>&1); ec=$?
    set -e
    assert_json_field "$out" ".error" "invalid_version" "invalid version error" &&
    assert_exit_code "1" "$ec" "exit 1"
}

test_init_reentrancy_blocked() {
    local repo; repo=$(_init_bare_repo)
    trap "cleanup_test_repo '$repo'" RETURN
    local out ec
    set +e
    out=$(cd "$repo" && SEMVER_BUMP_IN_PROGRESS=1 "$CLI" init run --plugin-root /x 2>&1); ec=$?
    set -e
    assert_json_field "$out" ".error" "reentrancy" "reentrancy blocked" &&
    assert_exit_code "1" "$ec" "exit 1"
}

# --- Artifacts present ---

test_init_artifacts_are_read_only() {
    local repo; repo=$(_init_tracked_repo)
    trap "cleanup_test_repo '$repo'" RETURN
    local head_before; head_before=$(git -C "$repo" rev-parse HEAD)
    local out; out=$(cd "$repo" && "$CLI" init run --plugin-root /x)

    assert_json_field "$out" ".executed" "false" "does not blindly re-init" &&
    assert_json_field "$out" ".artifacts.tracking_active" "true" "reports tracking active" &&
    local has_q; has_q=$(echo "$out" | jq '.questions_needed | index("init_existing") != null')
    assert_eq "true" "$has_q" "returns assessment question" &&
    assert_eq "$head_before" "$(git -C "$repo" rev-parse HEAD)" "no commit made (read-only)"
}

test_init_incoherent_offers_repair() {
    # VERSION present but no tag and no config → not coherent → repair offered.
    local repo; repo=$(_init_bare_repo)
    trap "cleanup_test_repo '$repo'" RETURN
    ( cd "$repo" && echo "v1.0.0" > VERSION && git add VERSION && git commit -q -m "add VERSION" )
    local out; out=$(cd "$repo" && "$CLI" init run --plugin-root /x)
    local has_repair; has_repair=$(echo "$out" | jq '[.questions[0].command_mapping[]] | index("repair") != null')
    assert_eq "true" "$has_repair" "repair offered for incoherent state"
}

test_init_enable_mode() {
    local repo; repo=$(_init_bare_repo)
    trap "cleanup_test_repo '$repo'" RETURN
    mkdir -p "$repo/.semver"
    cat > "$repo/.semver/config.yaml" << 'YAML'
tracking: false
auto_bump: false
auto_bump_confirm: true
version_prefix: "v"
git_tagging: true
changelog_format: "grouped"
target_branch: "main"
YAML
    ( cd "$repo" && git add -A && git commit -q -m cfg )
    local out; out=$(cd "$repo" && "$CLI" init execute --mode enable --plugin-root /x)

    assert_json_field "$out" ".action" "enable" "enable action" &&
    assert_json_field "$out" ".tracking" "true" "tracking reported on" &&
    assert_file_contains "$repo/.semver/config.yaml" "tracking: true" "tracking flipped" &&
    assert_file_contains "$repo/.semver/config.yaml" "auto_bump: true" "auto-bump flipped" &&
    assert_file_not_exists "$repo/VERSION" "VERSION untouched (still absent)"
}

test_init_adopt_mode() {
    # Existing VERSION + tag, no config → adopt writes config, keeps version/tag.
    local repo; repo=$(_init_bare_repo)
    trap "cleanup_test_repo '$repo'" RETURN
    ( cd "$repo" && echo "v3.1.0" > VERSION && git add VERSION && git commit -q -m ver && git tag v3.1.0 )
    local out; out=$(cd "$repo" && "$CLI" init execute --mode adopt --plugin-root /x)

    assert_json_field "$out" ".action" "adopt" "adopt action" &&
    assert_json_field "$out" ".version" "v3.1.0" "reports existing version" &&
    assert_file_contains "$repo/.semver/config.yaml" "tracking: true" "config written" &&
    assert_eq "v3.1.0" "$(cat "$repo/VERSION" | tr -d '[:space:]')" "VERSION unchanged" &&
    assert_eq "v3.1.0" "$(git -C "$repo" tag -l v3.1.0)" "existing tag kept"
}

test_init_reinit_mode() {
    local repo; repo=$(_init_tracked_repo)
    trap "cleanup_test_repo '$repo'" RETURN
    local out; out=$(cd "$repo" && "$CLI" init execute --mode reinit --version 5.0.0 --plugin-root /x)

    assert_json_field "$out" ".action" "reinit" "reinit action" &&
    assert_json_field "$out" ".version" "v5.0.0" "reinit version" &&
    assert_eq "v5.0.0" "$(cat "$repo/VERSION" | tr -d '[:space:]')" "VERSION reset" &&
    assert_eq "v5.0.0" "$(git -C "$repo" tag -l v5.0.0)" "tag created"
}

test_init_reinit_validate_all_pass() {
    local repo; repo=$(_init_tracked_repo)
    trap "cleanup_test_repo '$repo'" RETURN
    ( cd "$repo" && "$CLI" init execute --mode reinit --version 5.0.0 --plugin-root /x >/dev/null )
    local out; out=$(cd "$repo" && "$CLI" validate)
    assert_json_field "$out" ".all_pass" "true" "validate all_pass after reinit"
}

test_init_reinit_requires_version() {
    local repo; repo=$(_init_tracked_repo)
    trap "cleanup_test_repo '$repo'" RETURN
    local out ec
    set +e
    out=$(cd "$repo" && "$CLI" init execute --mode reinit --plugin-root /x 2>&1); ec=$?
    set -e
    assert_json_field "$out" ".error" "missing_version" "reinit needs --version" &&
    assert_exit_code "1" "$ec" "exit 1"
}
