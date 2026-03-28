#!/usr/bin/env bash
# Tests: PROMPT_HOOK.md discovery, content extraction, not executed as script

test_prompt_hook_content_returned() {
    local repo
    repo=$(create_test_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    create_prompt_hook "$repo" "pre-bump" "Review breaking changes before major bump."

    local result
    result=$(bash "$RUNNER" pre-bump major v1.0.0 v2.0.0 "$repo")

    local content
    content=$(echo "$result" | jq -r '.prompt_hook')
    assert_eq "Review breaking changes before major bump." "$content" "should return PROMPT_HOOK.md content"
}

test_prompt_hook_not_counted_as_hook() {
    local repo
    repo=$(create_test_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    create_prompt_hook "$repo" "pre-bump" "Some instructions"

    local result
    result=$(bash "$RUNNER" pre-bump patch v1.0.0 v1.0.1 "$repo")

    assert_json_field "$result" '.hooks_run' "0" "PROMPT_HOOK.md should not be counted in hooks_run"
}

test_prompt_hook_not_executed_as_script() {
    local repo
    repo=$(create_test_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    # PROMPT_HOOK.md with content that would fail if executed as bash
    create_prompt_hook "$repo" "pre-bump" 'This is markdown, not bash.
If executed, the "quotes" and $VARIABLES would cause errors.
```code blocks``` too.'

    create_hook_script "$repo" "pre-bump" "01-real.sh" 'echo "ran"'

    local result
    set +e
    result=$(bash "$RUNNER" pre-bump patch v1.0.0 v1.0.1 "$repo")
    local ec=$?
    set -e

    assert_exit_code 0 "$ec" "should not fail from PROMPT_HOOK.md content" &&
    assert_json_field "$result" '.hooks_run' "1" "only .sh script should count"
}

test_missing_prompt_hook_returns_null() {
    local repo
    repo=$(create_test_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    create_hook_script "$repo" "pre-bump" "01-check.sh" 'echo "ok"'

    local result
    result=$(bash "$RUNNER" pre-bump patch v1.0.0 v1.0.1 "$repo")

    assert_json_field "$result" '.prompt_hook' "null" "should be null when no PROMPT_HOOK.md"
}

test_prompt_hook_multiline_content() {
    local repo
    repo=$(create_test_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    local content='# Pre-Bump Review

Check for breaking changes.
Look at the API surface.

> Important: verify backwards compatibility'

    create_prompt_hook "$repo" "pre-bump" "$content"

    local result
    result=$(bash "$RUNNER" pre-bump major v1.0.0 v2.0.0 "$repo")

    local returned
    returned=$(echo "$result" | jq -r '.prompt_hook')
    assert_eq "$content" "$returned" "multiline content should be returned verbatim"
}

test_prompt_hook_with_scripts() {
    local repo
    repo=$(create_test_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    create_prompt_hook "$repo" "post-bump" "Update README badges."
    create_hook_script "$repo" "post-bump" "01-sync.sh" 'echo "synced"'
    create_hook_script "$repo" "post-bump" "02-notify.sh" 'echo "notified"'

    local result
    result=$(bash "$RUNNER" post-bump patch v1.0.0 v1.0.1 "$repo")

    assert_json_field "$result" '.hooks_run' "2" "should run 2 scripts" &&
    local content
    content=$(echo "$result" | jq -r '.prompt_hook')
    assert_eq "Update README badges." "$content" "prompt_hook content should be present"
}
