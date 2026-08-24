#!/usr/bin/env bash
# Regression test: Semver's Codex SessionStart hook must emit Codex's
# hookSpecificOutput envelope, not Claude's top-level additionalContext shape.

test_session_start_emits_host_specific_json() {
    local plugin_root="$PLUGIN_ROOT"
    local hooks_json="$plugin_root/hooks/hooks.json"
    local expected_command='bash "${PLUGIN_ROOT:-$CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh"'
    local manifest_command

    manifest_command=$(jq -er '.hooks.SessionStart[0].hooks[0].command' "$hooks_json") || {
        echo "    FAIL: could not read the SessionStart command from $hooks_json"
        return 2
    }

    if ! assert_eq "$expected_command" "$manifest_command" \
        "test must exercise the installed-manifest SessionStart command"; then
        return 2
    fi

    local fixture
    fixture=$(mktemp -d "/tmp/semver-test-codex-sessionstart-XXXXXX") || return 2
    trap "cleanup_test_repo '$fixture'" RETURN

    mkdir -p "$fixture/.semver"
    cat > "$fixture/.semver/config.yaml" <<'YAML'
tracking: true
git_tagging: false
YAML
    printf 'v9.8.7\n' > "$fixture/VERSION"

    local expected_message
    expected_message="$(basename "$fixture") version: v9.8.7"

    local stdin_json codex_stderr codex_output codex_ec
    stdin_json=$(jq -cn --arg cwd "$fixture" '{
        session_id: "semver-codex-sessionstart-repro",
        cwd: $cwd,
        hook_event_name: "SessionStart",
        source: "clear"
    }')
    codex_stderr="$fixture/codex.stderr"

    set +e
    codex_output=$(printf '%s\n' "$stdin_json" | env -i PATH="$PATH" \
        PLUGIN_ROOT="$plugin_root" CLAUDE_PLUGIN_ROOT="$plugin_root" \
        bash -c "$manifest_command" 2>"$codex_stderr")
    codex_ec=$?
    set -e

    if ! assert_exit_code "0" "$codex_ec" \
        "Codex SessionStart command should launch successfully"; then
        if [[ -s "$codex_stderr" ]]; then
            sed 's/^/      stderr: /' "$codex_stderr"
        fi
        return 2
    fi

    if [[ -s "$codex_stderr" ]]; then
        echo "    FAIL: Codex SessionStart command must not emit stderr"
        sed 's/^/      stderr: /' "$codex_stderr"
        return 1
    fi

    if ! printf '%s' "$codex_output" | jq -e . >/dev/null 2>&1; then
        echo "    FAIL: Codex SessionStart command must emit valid JSON"
        echo "      actual: $codex_output"
        return 2
    fi

    if ! printf '%s' "$codex_output" | jq -e --arg message "$expected_message" '
        keys == ["hookSpecificOutput"] and
        (.hookSpecificOutput | keys) == ["additionalContext", "hookEventName"] and
        .hookSpecificOutput == {
            hookEventName: "SessionStart",
            additionalContext: $message
        }
    ' >/dev/null; then
        echo "    FAIL: Codex SessionStart output must match the exact hookSpecificOutput contract"
        echo "      expected message: $expected_message"
        echo "      actual:           $(printf '%s' "$codex_output" | jq -c .)"
        return 1
    fi

    local claude_stderr claude_output claude_ec
    claude_stderr="$fixture/claude.stderr"

    set +e
    claude_output=$(printf '%s\n' "$stdin_json" | env -i PATH="$PATH" \
        CLAUDE_PLUGIN_ROOT="$plugin_root" CLAUDE_PROJECT_DIR="$fixture" \
        bash -c "$manifest_command" 2>"$claude_stderr")
    claude_ec=$?
    set -e

    if ! assert_exit_code "0" "$claude_ec" \
        "Claude SessionStart command should launch successfully"; then
        if [[ -s "$claude_stderr" ]]; then
            sed 's/^/      stderr: /' "$claude_stderr"
        fi
        return 2
    fi

    if [[ -s "$claude_stderr" ]]; then
        echo "    FAIL: Claude SessionStart command must not emit stderr"
        sed 's/^/      stderr: /' "$claude_stderr"
        return 1
    fi

    if ! printf '%s' "$claude_output" | jq -e . >/dev/null 2>&1; then
        echo "    FAIL: Claude SessionStart command must emit valid JSON"
        echo "      actual: $claude_output"
        return 2
    fi

    if ! printf '%s' "$claude_output" | jq -e --arg message "$expected_message" '
        keys == ["additionalContext"] and
        .additionalContext == $message
    ' >/dev/null; then
        echo "    FAIL: Claude SessionStart output must preserve the exact additionalContext contract"
        echo "      expected message: $expected_message"
        echo "      actual:           $(printf '%s' "$claude_output" | jq -c .)"
        return 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    TESTS_DIR=$(cd "$(dirname "$0")" && pwd)
    source "$TESTS_DIR/helpers/setup.sh"

    echo "semver Codex SessionStart JSON regression"
    if test_session_start_emits_host_specific_json; then
        echo "  PASS  test_session_start_emits_host_specific_json"
        exit 0
    else
        ec=$?
        echo "  FAIL  test_session_start_emits_host_specific_json"
        exit "$ec"
    fi
fi
