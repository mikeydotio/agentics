#!/usr/bin/env bash
# Tests for semver-router.sh argument routing
# Covers: all routing patterns, argument passthrough, usage output, error passthrough

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROUTER="$PLUGIN_ROOT/bin/semver-router.sh"

# --- Helpers ---

create_semver_repo() {
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

# ═══════════════════════════════════════════════════════════════════════════
# 1. Empty / current routing
# ═══════════════════════════════════════════════════════════════════════════

test_route_empty_runs_current() {
    local dir
    dir=$(create_semver_repo)
    cd "$dir"

    local result
    result=$(bash "$ROUTER")
    assert_json_field "$result" ".ok" "true"
    assert_json_field "$result" ".tracking" "true"

    rm -rf "$dir"
}

test_route_current_runs_current() {
    local dir
    dir=$(create_semver_repo)
    cd "$dir"

    local result
    result=$(bash "$ROUTER" current)
    assert_json_field "$result" ".ok" "true"
    assert_json_field "$result" ".tracking" "true"

    rm -rf "$dir"
}

# ═══════════════════════════════════════════════════════════════════════════
# 2. Bump routing (bump run: executes in one call on the happy path)
# ═══════════════════════════════════════════════════════════════════════════

test_route_bump_major() {
    local dir
    dir=$(create_semver_repo)
    cd "$dir"

    echo "feature" >> feature.txt
    git add -A
    git commit -q -m "feat: new feature"

    local result
    result=$(bash "$ROUTER" bump major)
    assert_json_field "$result" ".ok" "true"
    assert_json_field "$result" ".executed" "true"
    assert_json_field "$result" ".new_version" "v2.0.0"

    rm -rf "$dir"
}

test_route_bump_minor() {
    local dir
    dir=$(create_semver_repo)
    cd "$dir"

    echo "feature" >> feature.txt
    git add -A
    git commit -q -m "feat: new feature"

    local result
    result=$(bash "$ROUTER" bump minor)
    assert_json_field "$result" ".ok" "true"
    assert_json_field "$result" ".executed" "true"
    assert_json_field "$result" ".new_version" "v1.1.0"

    rm -rf "$dir"
}

test_route_bump_patch() {
    local dir
    dir=$(create_semver_repo)
    cd "$dir"

    echo "feature" >> feature.txt
    git add -A
    git commit -q -m "fix: a bugfix"

    local result
    result=$(bash "$ROUTER" bump patch)
    assert_json_field "$result" ".ok" "true"
    assert_json_field "$result" ".executed" "true"
    assert_json_field "$result" ".new_version" "v1.0.1"

    rm -rf "$dir"
}

test_route_bump_with_force() {
    local dir
    dir=$(create_semver_repo)
    cd "$dir"

    # No new commits; without --force this would report no_commits
    local result
    result=$(bash "$ROUTER" bump patch --force)
    assert_json_field "$result" ".ok" "true"

    rm -rf "$dir"
}

# ═══════════════════════════════════════════════════════════════════════════
# 3. Validate / check routing
# ═══════════════════════════════════════════════════════════════════════════

test_route_validate() {
    local dir
    dir=$(create_semver_repo)
    cd "$dir"

    local result
    result=$(bash "$ROUTER" validate)
    assert_json_field "$result" ".ok" "true"

    rm -rf "$dir"
}

test_route_check_alias() {
    local dir
    dir=$(create_semver_repo)
    cd "$dir"

    local result
    result=$(bash "$ROUTER" check)
    assert_json_field "$result" ".ok" "true"

    rm -rf "$dir"
}

# ═══════════════════════════════════════════════════════════════════════════
# 4. Repair / fix routing
# ═══════════════════════════════════════════════════════════════════════════

test_route_repair() {
    local dir
    dir=$(create_semver_repo)
    cd "$dir"

    local result
    result=$(bash "$ROUTER" repair)
    assert_json_field "$result" ".ok" "true"
    assert_json_field "$result" ".all_pass" "true"

    rm -rf "$dir"
}

test_route_fix_alias() {
    local dir
    dir=$(create_semver_repo)
    cd "$dir"

    local result
    result=$(bash "$ROUTER" fix)
    assert_json_field "$result" ".ok" "true"
    assert_json_field "$result" ".all_pass" "true"

    rm -rf "$dir"
}

# ═══════════════════════════════════════════════════════════════════════════
# 5. Tracking routing
# ═══════════════════════════════════════════════════════════════════════════

test_route_tracking_start_already_active() {
    local dir
    dir=$(create_semver_repo)
    cd "$dir"

    local result
    result=$(bash "$ROUTER" tracking start)
    assert_json_field "$result" ".ok" "true"
    assert_json_field "$result" ".action" "already_active"

    rm -rf "$dir"
}

test_route_tracking_stop() {
    local dir
    dir=$(create_semver_repo)
    cd "$dir"

    local result
    result=$(bash "$ROUTER" tracking stop)
    assert_json_field "$result" ".ok" "true"

    rm -rf "$dir"
}

# ═══════════════════════════════════════════════════════════════════════════
# 6. Auto-bump routing
# ═══════════════════════════════════════════════════════════════════════════

test_route_auto_bump_start() {
    local dir
    dir=$(create_semver_repo)
    cd "$dir"

    local result
    result=$(bash "$ROUTER" auto-bump start --confirm true)
    assert_json_field "$result" ".ok" "true"

    rm -rf "$dir"
}

test_route_auto_bump_stop() {
    local dir
    dir=$(create_semver_repo)
    cd "$dir"

    local result
    result=$(bash "$ROUTER" auto-bump stop)
    assert_json_field "$result" ".ok" "true"

    rm -rf "$dir"
}

# ═══════════════════════════════════════════════════════════════════════════
# 7. Unknown command produces usage JSON
# ═══════════════════════════════════════════════════════════════════════════

test_unknown_command_returns_usage_json() {
    local result
    result=$(bash "$ROUTER" something-totally-unknown)
    assert_json_field "$result" ".ok" "false"
    assert_json_field "$result" ".error" "usage"

    # Verify the display field contains key usage lines
    local display
    display=$(echo "$result" | jq -r '.display')
    echo "$display" | grep -q "/semver current" || { echo "FAIL: missing /semver current in usage"; return 1; }
    echo "$display" | grep -q "/semver bump" || { echo "FAIL: missing /semver bump in usage"; return 1; }
    echo "$display" | grep -q "/semver validate" || { echo "FAIL: missing /semver validate in usage"; return 1; }
    echo "$display" | grep -q "/semver repair" || { echo "FAIL: missing /semver repair in usage"; return 1; }
    echo "$display" | grep -q "/semver tracking" || { echo "FAIL: missing /semver tracking in usage"; return 1; }
    echo "$display" | grep -q "/semver auto-bump" || { echo "FAIL: missing /semver auto-bump in usage"; return 1; }
}

test_unknown_command_exits_zero() {
    # Script should exit 0 even for unknown commands (it returns JSON error, not shell error)
    bash "$ROUTER" unknown-stuff
    local ec=$?
    assert_eq "0" "$ec" "unknown command should exit 0"
}

# ═══════════════════════════════════════════════════════════════════════════
# 8. Tracking start with passthrough options
# ═══════════════════════════════════════════════════════════════════════════

test_route_tracking_start_with_options() {
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

    local result
    result=$(bash "$ROUTER" tracking start --version v2.0.0 --no-tags)
    assert_json_field "$result" ".ok" "true"

    rm -rf "$dir"
}

# ═══════════════════════════════════════════════════════════════════════════
# 9. CLI failure passthrough
# ═══════════════════════════════════════════════════════════════════════════

test_cli_error_passthrough() {
    # Run bump in a directory with no tracking -- CLI returns ok:false JSON
    local dir
    dir=$(mktemp -d "/tmp/semver-test-XXXXXX")
    cd "$dir"
    git init -q
    git config user.name "Test"
    git config user.email "test@test.com"
    echo "init" > README.md
    git add README.md
    git commit -q -m "init"

    local result
    result=$(bash "$ROUTER" bump major 2>/dev/null)

    assert_json_field "$result" ".ok" "false"

    rm -rf "$dir"
}
