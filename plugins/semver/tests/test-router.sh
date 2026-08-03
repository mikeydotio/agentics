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
# 6b. set / init routing
# ═══════════════════════════════════════════════════════════════════════════

test_route_set_runs_set_run() {
    local dir
    dir=$(create_semver_repo)
    cd "$dir"

    local result
    result=$(bash "$ROUTER" set 2.0.0)
    assert_json_field "$result" ".ok" "true"
    assert_json_field "$result" ".executed" "true"
    assert_json_field "$result" ".new_version" "v2.0.0"

    rm -rf "$dir"
}

test_route_set_no_version_returns_usage() {
    local result
    result=$(bash "$ROUTER" set)
    assert_json_field "$result" ".ok" "false"
    assert_json_field "$result" ".error" "usage"
}

test_route_init_runs_init_run() {
    # On an already-tracked repo, init routes through and returns the read-only
    # assessment (proving --plugin-root threading + argument passthrough work).
    local dir
    dir=$(create_semver_repo)
    cd "$dir"

    local result
    result=$(bash "$ROUTER" init)
    assert_json_field "$result" ".ok" "true"
    assert_json_field "$result" ".executed" "false"
    local has_q
    has_q=$(echo "$result" | jq '.questions_needed | index("init_existing") != null')
    assert_eq "true" "$has_q" "init returns the assessment question"

    rm -rf "$dir"
}

test_route_init_with_optional_version() {
    local dir
    dir=$(create_semver_repo)
    cd "$dir"

    local result
    result=$(bash "$ROUTER" init v9.9.9)
    assert_json_field "$result" ".ok" "true"
    assert_json_field "$result" ".reinit_needs_version" "false"

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
    echo "$display" | grep -q "/semver set" || { echo "FAIL: missing /semver set in usage"; return 1; }
    echo "$display" | grep -q "/semver init" || { echo "FAIL: missing /semver init in usage"; return 1; }
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
    # Run bump in a directory with no tracking -- CLI returns ok:false JSON.
    # The router now also exits 1 for this (previously always 0), so the
    # invocation must be guarded from set -e like every other nonzero-exit
    # call in this suite.
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
    set +e
    result=$(bash "$ROUTER" bump major 2>/dev/null)
    set -e

    assert_json_field "$result" ".ok" "false"

    rm -rf "$dir"
}

# ═══════════════════════════════════════════════════════════════════════════
# 10. Exit-code propagation (AGE-3 follow-on: run_cli() previously ended with
# a bare `set -e`, which itself returns 0 — every CLI outcome, success or
# failure, was silently reported as exit 0. Now the router exits with the
# CLI's own exit status: 0 success, 1 failed, 2 usage error, 3 completed but
# post-bump hooks were skipped.)
# ═══════════════════════════════════════════════════════════════════════════

test_route_exit_code_clean_bump_is_zero() {
    local dir
    dir=$(create_semver_repo)
    cd "$dir"
    echo "feature" >> feature.txt
    git add -A
    git commit -q -m "feat: new feature"

    bash "$ROUTER" bump minor > /dev/null
    local ec=$?

    rm -rf "$dir"
    assert_exit_code "0" "$ec" "clean bump should exit 0"
}

test_route_exit_code_tracking_inactive_is_one() {
    local dir
    dir=$(mktemp -d "/tmp/semver-test-XXXXXX")
    cd "$dir"
    git init -q
    git config user.name "Test"
    git config user.email "test@test.com"
    echo "init" > README.md
    git add README.md
    git commit -q -m "init"

    local ec
    set +e
    bash "$ROUTER" bump major > /dev/null 2>&1
    ec=$?
    set -e

    rm -rf "$dir"
    assert_exit_code "1" "$ec" "an operation-failed CLI error should exit 1"
}

test_route_exit_code_hooks_skipped_is_three() {
    local dir
    dir=$(create_semver_repo)
    cd "$dir"
    mkdir -p .semver/hooks/post-bump
    cat > .semver/hooks/post-bump/01-marker.sh << 'HOOK'
#!/usr/bin/env bash
echo "$NEW_VERSION" > .hook-ran
HOOK
    chmod +x .semver/hooks/post-bump/01-marker.sh
    git add -A && git commit -q -m "add post-bump hook"
    echo "feature" >> feature.txt
    git add -A
    git commit -q -m "feat: new feature"

    # The router unconditionally threads --plugin-root "$PLUGIN_ROOT" ahead of
    # passthrough args; argparse keeps the last occurrence of a repeated flag,
    # so appending a bogus one here overrides it — forcing an unreachable
    # runner without touching the real plugin's files on disk.
    local result ec
    set +e
    result=$(bash "$ROUTER" bump minor --plugin-root /nonexistent-plugin-root 2>&1); ec=$?
    set -e

    rm -rf "$dir"
    assert_json_field "$result" ".post_hooks.skipped" "true" "post_hooks.skipped should be true" &&
    assert_exit_code "3" "$ec" "hooks-skipped-but-bump-landed should exit 3"
}
