#!/usr/bin/env bash
# Shared test fixtures and assertion helpers

# Path to the hook runner under test
RUNNER="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/hooks/run-user-hooks.sh"

# Counters (managed by run-tests.sh)
PASS_COUNT=0
FAIL_COUNT=0
FAIL_NAMES=()

# --- Fixture Helpers ---

create_test_repo() {
    local repo
    repo=$(mktemp -d "/tmp/semver-test-XXXXXX")

    cd "$repo"
    git init -q
    git config user.name "Test"
    git config user.email "test@test.com"

    mkdir -p .semver
    cat > .semver/config.yaml << 'YAML'
tracking: true
auto_bump: false
auto_bump_confirm: true
version_prefix: "v"
changelog_format: "grouped"
target_branch: "main"
YAML

    echo "v1.0.0" > VERSION

    cat > CHANGELOG.md << 'MD'
# Changelog

## [v1.0.0] - 2026-01-01

### Added
- Initial release

_[manual]_
MD

    git add -A
    git commit -q -m "chore: initialize version at v1.0.0"
    git tag "v1.0.0"

    echo "$repo"
}

add_feature_commit() {
    local repo="$1"
    local msg="${2:-feat: add new feature}"
    echo "feature" >> "$repo/feature.txt"
    git -C "$repo" add -A
    git -C "$repo" commit -q -m "$msg"
}

create_hook_script() {
    local repo="$1"
    local phase="$2"     # pre-bump or post-bump
    local filename="$3"  # e.g., 01-test.sh
    local body="$4"

    local dir="$repo/.semver/hooks/$phase"
    mkdir -p "$dir"

    cat > "$dir/$filename" << SCRIPT
#!/usr/bin/env bash
set -euo pipefail
$body
SCRIPT
    chmod +x "$dir/$filename"
}

create_prompt_hook() {
    local repo="$1"
    local phase="$2"     # pre-bump or post-bump
    local content="$3"

    local dir="$repo/.semver/hooks/$phase"
    mkdir -p "$dir"
    printf '%s' "$content" > "$dir/PROMPT_HOOK.md"
}

cleanup_test_repo() {
    local repo="$1"
    if [ -n "$repo" ] && [ -d "$repo" ] && [[ "$repo" == /tmp/semver-test-* ]]; then
        rm -rf "$repo"
    fi
}

# Simulates the bump flow that SKILL.md instructs Claude to execute.
# Calls run-user-hooks.sh at the correct points in the flow.
#
# Usage: simulate_bump <repo> <bump_type>
# Returns: exit code (0=success, 1=pre-bump hook failed)
# Sets globals: SIM_RESULT_PRE, SIM_RESULT_POST, SIM_EXIT_CODE
simulate_bump() {
    local repo="$1"
    local bump_type="$2"
    local old_version new_version
    local major minor patch

    SIM_RESULT_PRE=""
    SIM_RESULT_POST=""
    SIM_EXIT_CODE=0

    # Read current version
    old_version=$(cat "$repo/VERSION" | tr -d '[:space:]')
    local bare="${old_version#v}"
    IFS='.' read -r major minor patch <<< "$bare"

    # Compute new version
    case "$bump_type" in
        major) new_version="v$((major + 1)).0.0" ;;
        minor) new_version="v${major}.$((minor + 1)).0" ;;
        patch) new_version="v${major}.${minor}.$((patch + 1))" ;;
    esac

    # Run pre-bump hooks
    set +e
    SIM_RESULT_PRE=$(SEMVER_BUMP_IN_PROGRESS="" bash "$RUNNER" pre-bump "$bump_type" "$old_version" "$new_version" "$repo")
    local pre_exit=$?
    set -e

    if [ $pre_exit -ne 0 ]; then
        SIM_EXIT_CODE=$pre_exit
        return 0  # always return 0; callers check SIM_EXIT_CODE
    fi

    # Execute bump (write VERSION, update CHANGELOG, commit, tag)
    echo "$new_version" > "$repo/VERSION"

    local today
    today=$(date +%Y-%m-%d)
    local entry="## [$new_version] - $today\n\n### Changed\n- Bump from $old_version\n\n_[manual]_\n"
    local changelog
    changelog=$(cat "$repo/CHANGELOG.md")
    printf "# Changelog\n\n%b\n%s" "$entry" "${changelog#\# Changelog}" > "$repo/CHANGELOG.md"

    git -C "$repo" add VERSION CHANGELOG.md
    git -C "$repo" commit -q -m "chore(release): $new_version"
    git -C "$repo" tag "$new_version"

    # Run post-bump hooks
    set +e
    SIM_RESULT_POST=$(SEMVER_BUMP_IN_PROGRESS="" bash "$RUNNER" post-bump "$bump_type" "$old_version" "$new_version" "$repo")
    local post_exit=$?
    set -e

    SIM_EXIT_CODE=0
    return 0
}

# --- Assertion Helpers ---

assert_eq() {
    local expected="$1"
    local actual="$2"
    local msg="${3:-assert_eq}"

    if [ "$expected" = "$actual" ]; then
        return 0
    else
        echo "    FAIL: $msg"
        echo "      expected: $expected"
        echo "      actual:   $actual"
        return 1
    fi
}

assert_ne() {
    local unexpected="$1"
    local actual="$2"
    local msg="${3:-assert_ne}"

    if [ "$unexpected" != "$actual" ]; then
        return 0
    else
        echo "    FAIL: $msg — expected different but got: $actual"
        return 1
    fi
}

assert_file_contains() {
    local file="$1"
    local pattern="$2"
    local msg="${3:-assert_file_contains}"

    if grep -q "$pattern" "$file" 2>/dev/null; then
        return 0
    else
        echo "    FAIL: $msg — pattern '$pattern' not found in $file"
        return 1
    fi
}

assert_file_not_contains() {
    local file="$1"
    local pattern="$2"
    local msg="${3:-assert_file_not_contains}"

    if ! grep -q "$pattern" "$file" 2>/dev/null; then
        return 0
    else
        echo "    FAIL: $msg — pattern '$pattern' unexpectedly found in $file"
        return 1
    fi
}

assert_file_exists() {
    local file="$1"
    local msg="${2:-assert_file_exists}"

    if [ -f "$file" ]; then
        return 0
    else
        echo "    FAIL: $msg — file not found: $file"
        return 1
    fi
}

assert_file_not_exists() {
    local file="$1"
    local msg="${2:-assert_file_not_exists}"

    if [ ! -f "$file" ]; then
        return 0
    else
        echo "    FAIL: $msg — file unexpectedly exists: $file"
        return 1
    fi
}

assert_exit_code() {
    local expected="$1"
    local actual="$2"
    local msg="${3:-assert_exit_code}"

    if [ "$expected" = "$actual" ]; then
        return 0
    else
        echo "    FAIL: $msg — expected exit code $expected, got $actual"
        return 1
    fi
}

assert_json_field() {
    local json="$1"
    local field="$2"
    local expected="$3"
    local msg="${4:-assert_json_field}"

    local actual
    actual=$(echo "$json" | jq -r "$field" 2>/dev/null)

    if [ "$actual" = "$expected" ]; then
        return 0
    else
        echo "    FAIL: $msg — field $field"
        echo "      expected: $expected"
        echo "      actual:   $actual"
        return 1
    fi
}
