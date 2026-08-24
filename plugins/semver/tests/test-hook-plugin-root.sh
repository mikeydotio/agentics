#!/usr/bin/env bash
# Regression tests for AGE-3: post-bump hooks were silently skipped whenever a
# caller omitted --plugin-root, because run_user_hooks() only looked for the
# hook runner at a path joined from that flag and both call sites were gated
# behind `if plugin_root:`. The runner ships with the plugin at a fixed path
# relative to semver-cli itself, so it should never need the flag to be found.
#
# Covers: the primary repro (bump execute with no --plugin-root), parity
# between the flagged and flag-less paths, the "no hooks defined" no-op case,
# the new skipped/exit-3 escalation when hooks are pending but unreachable,
# the scope boundary that a hook which RAN and failed is unaffected, and the
# same coverage for `set execute`, `init run`/`init execute`, and the
# `tracking start` sibling defect (which never threaded --plugin-root at all).

# --- Provider hook manifest ---

test_provider_hooks_resolve_codex_plugin_root() {
    local hooks_json="$PLUGIN_ROOT/hooks/hooks.json"
    local post_command session_command post_ec session_ec

    post_command=$(jq -r '.hooks.PostToolUse[0].hooks[0].command' "$hooks_json")
    session_command=$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$hooks_json")

    set +e
    printf '{}\n' | env -u CLAUDE_PLUGIN_ROOT PLUGIN_ROOT="$PLUGIN_ROOT" \
        bash -c "$post_command" >/dev/null 2>&1
    post_ec=$?
    printf '{}\n' | env -u CLAUDE_PLUGIN_ROOT PLUGIN_ROOT="$PLUGIN_ROOT" \
        bash -c "$session_command" >/dev/null 2>&1
    session_ec=$?
    set -e

    assert_eq 'bash "${PLUGIN_ROOT:-$CLAUDE_PLUGIN_ROOT}/hooks/post-push-check.sh"' \
        "$post_command" "PostToolUse should support Codex PLUGIN_ROOT" &&
    assert_eq 'bash "${PLUGIN_ROOT:-$CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh"' \
        "$session_command" "SessionStart should support Codex PLUGIN_ROOT" &&
    assert_exit_code "0" "$post_ec" "PostToolUse should launch with PLUGIN_ROOT only" &&
    assert_exit_code "0" "$session_ec" "SessionStart should launch with PLUGIN_ROOT only"
}

# --- Fixtures ---

# A tracking-active repo at v1.0.0 with git_tagging on — mirrors _set_repo in
# test-set.sh, needed here (rather than the shared create_test_repo, whose
# config omits git_tagging) so tag-existence assertions are unambiguous.
_hook_repo() {
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

## [v1.0.0] - 2026-01-01

- Initial version tracking

_[manual]_
CL
    git add -A
    git commit -q -m "chore: initialize semver tracking"
    git tag v1.0.0
    echo "$dir"
}

# A post-bump hook that writes NEW_VERSION to a marker file — proof it ran.
_add_marker_hook() {
    local repo="$1"
    create_hook_script "$repo" "post-bump" "01-marker.sh" \
        "echo \"\$NEW_VERSION\" > '$repo/.hook-ran'"
    ( cd "$repo" && git add -A && git commit -q -m "add post-bump hook" )
}

# --- bump execute ---

test_bump_execute_without_plugin_root_runs_hooks() {
    # The exact repro from the story: `bump execute ... --source manual` with
    # no --plugin-root at all must still run post-bump hooks.
    local repo; repo=$(_hook_repo)
    trap "cleanup_test_repo '$repo'" RETURN
    _add_marker_hook "$repo"
    ( cd "$repo" && echo x > f.txt && git add -A && git commit -q -m "feat: x" )

    local out; out=$(cd "$repo" && "$CLI" bump execute minor --source manual)

    assert_json_field "$out" ".ok" "true" "ok should be true" &&
    assert_json_field "$out" ".post_hooks.hooks_run" "1" "post-bump hook should have run" &&
    assert_json_field "$out" ".post_hooks.skipped" "false" "not skipped" &&
    assert_file_exists "$repo/.hook-ran" "marker file should exist" &&
    assert_file_contains "$repo/.hook-ran" "v1.1.0" "hook should see NEW_VERSION"
}

test_bump_execute_with_and_without_plugin_root_are_equivalent() {
    local repo_a; repo_a=$(_hook_repo)
    local repo_b; repo_b=$(_hook_repo)
    trap "cleanup_test_repo '$repo_a'; cleanup_test_repo '$repo_b'" RETURN
    _add_marker_hook "$repo_a"
    _add_marker_hook "$repo_b"
    ( cd "$repo_a" && echo x > f.txt && git add -A && git commit -q -m "feat: x" )
    ( cd "$repo_b" && echo x > f.txt && git add -A && git commit -q -m "feat: x" )

    local out_flagged; out_flagged=$(cd "$repo_a" && "$CLI" bump execute minor --plugin-root "$PLUGIN_ROOT")
    local out_bare; out_bare=$(cd "$repo_b" && "$CLI" bump execute minor)

    local hooks_flagged hooks_bare
    hooks_flagged=$(echo "$out_flagged" | jq -r '.post_hooks.hooks_run')
    hooks_bare=$(echo "$out_bare" | jq -r '.post_hooks.hooks_run')
    assert_eq "$hooks_flagged" "$hooks_bare" "hooks_run should match with/without --plugin-root"
}

test_bump_execute_no_hooks_defined_stays_clean() {
    local repo; repo=$(_hook_repo)
    trap "cleanup_test_repo '$repo'" RETURN
    ( cd "$repo" && echo x > f.txt && git add -A && git commit -q -m "feat: x" )

    local out ec
    set +e
    out=$(cd "$repo" && "$CLI" bump execute minor 2>&1); ec=$?
    set -e

    assert_json_field "$out" ".ok" "true" "ok should be true" &&
    assert_json_field "$out" ".post_hooks.hooks_run" "0" "no hooks to run" &&
    assert_json_field "$out" ".post_hooks.skipped" "false" "nothing was skipped" &&
    assert_exit_code "0" "$ec" "exit 0 when no hooks are defined"
}

test_bump_execute_unreachable_runner_reports_skip_and_exits_3() {
    local repo; repo=$(_hook_repo)
    trap "cleanup_test_repo '$repo'" RETURN
    _add_marker_hook "$repo"
    ( cd "$repo" && echo x > f.txt && git add -A && git commit -q -m "feat: x" )

    local out ec
    set +e
    out=$(cd "$repo" && "$CLI" bump execute minor --plugin-root /nonexistent-plugin-root 2>&1); ec=$?
    set -e

    assert_json_field "$out" ".ok" "true" "the bump itself still landed" &&
    assert_json_field "$out" ".tag_created" "true" "tag was created despite the skip" &&
    assert_json_field "$out" ".post_hooks.skipped" "true" "post_hooks.skipped should be true" &&
    assert_exit_code "3" "$ec" "exit 3 signals hooks could not run" &&
    assert_file_not_exists "$repo/.hook-ran" "the hook itself never ran" &&
    local pending
    pending=$(echo "$out" | jq -r '.post_hooks.warnings[0].hooks_pending[0]')
    assert_eq "01-marker.sh" "$pending" "the pending hook should be named in warnings"
}

test_bump_execute_hook_that_runs_and_fails_stays_exit_0() {
    # Scope boundary: a hook that RAN and exited non-zero is a different,
    # already-documented case (warn but do not roll back) — must NOT be
    # conflated with the new "hooks could not run at all" escalation.
    local repo; repo=$(_hook_repo)
    trap "cleanup_test_repo '$repo'" RETURN
    create_hook_script "$repo" "post-bump" "01-fail.sh" 'echo "boom"; exit 1'
    ( cd "$repo" && git add -A && git commit -q -m "add failing hook" )
    ( cd "$repo" && echo x > f.txt && git add -A && git commit -q -m "feat: x" )

    local out ec
    set +e
    out=$(cd "$repo" && "$CLI" bump execute minor 2>&1); ec=$?
    set -e

    assert_json_field "$out" ".post_hooks.hooks_run" "1" "the hook did run" &&
    assert_json_field "$out" ".post_hooks.skipped" "false" "not the skipped case" &&
    assert_exit_code "0" "$ec" "a failed (but executed) hook stays exit 0"
}

# --- set execute ---

test_set_execute_without_plugin_root_runs_hooks() {
    local repo; repo=$(_hook_repo)
    trap "cleanup_test_repo '$repo'" RETURN
    _add_marker_hook "$repo"

    local out; out=$(cd "$repo" && "$CLI" set execute 2.0.0)

    assert_json_field "$out" ".post_hooks.hooks_run" "1" "post-bump hook should have run" &&
    assert_file_exists "$repo/.hook-ran" "marker file should exist" &&
    assert_file_contains "$repo/.hook-ran" "v2.0.0" "hook should see NEW_VERSION"
}

# --- init run / init execute ---

test_init_run_fresh_without_plugin_root_runs_hooks() {
    # A brand-new repo can't have hooks committed before init exists, so this
    # proves the flag-less path is *attempted* (hooks_run: 0, no crash, exit 0)
    # rather than proving a hook fires — that's covered by reinit below, where
    # the project can already carry hooks from a prior life.
    local dir
    dir=$(mktemp -d "/tmp/semver-test-XXXXXX")
    trap "cleanup_test_repo '$dir'" RETURN
    cd "$dir"
    git init -q
    git branch -M main
    git config user.name "Test"
    git config user.email "test@test.com"
    echo "init" > README.md
    git add README.md
    git commit -q -m "chore: initial commit"

    local out ec
    set +e
    out=$(cd "$dir" && "$CLI" init run 2>&1); ec=$?
    set -e

    assert_json_field "$out" ".executed" "true" "fresh init should execute" &&
    assert_json_field "$out" ".post_hooks.hooks_run" "0" "no hooks yet on a brand-new repo" &&
    assert_exit_code "0" "$ec" "exit 0 with no hooks defined"
}

test_init_reinit_without_plugin_root_runs_hooks() {
    local repo; repo=$(_hook_repo)
    trap "cleanup_test_repo '$repo'" RETURN
    _add_marker_hook "$repo"

    local out; out=$(cd "$repo" && "$CLI" init execute --mode reinit --version 5.0.0)

    assert_json_field "$out" ".post_hooks.hooks_run" "1" "post-bump hook should have run" &&
    assert_file_exists "$repo/.hook-ran" "marker file should exist" &&
    assert_file_contains "$repo/.hook-ran" "v5.0.0" "hook should see NEW_VERSION"
}

# --- tracking start (sibling defect: never threaded --plugin-root at all) ---

test_tracking_start_with_version_runs_hooks() {
    local dir
    dir=$(mktemp -d "/tmp/semver-test-XXXXXX")
    trap "cleanup_test_repo '$dir'" RETURN
    cd "$dir"
    git init -q
    git branch -M main
    git config user.name "Test"
    git config user.email "test@test.com"
    echo "init" > README.md
    git add README.md
    git commit -q -m "chore: initial commit"
    # A hook committed before tracking exists — legitimate for a repo adding
    # semver hooks ahead of turning tracking on.
    mkdir -p .semver/hooks/post-bump
    cat > .semver/hooks/post-bump/01-marker.sh << HOOK
#!/usr/bin/env bash
echo "\$NEW_VERSION" > "$dir/.hook-ran"
HOOK
    chmod +x .semver/hooks/post-bump/01-marker.sh
    git add -A && git commit -q -m "add post-bump hook"

    local out; out=$(cd "$dir" && "$CLI" tracking start --version 1.0.0)

    assert_json_field "$out" ".version_set" "true" "version should be set" &&
    assert_json_field "$out" ".post_hooks.hooks_run" "1" "post-bump hook should have run" &&
    assert_file_exists "$dir/.hook-ran" "marker file should exist" &&
    assert_file_contains "$dir/.hook-ran" "v1.0.0" "hook should see NEW_VERSION"
}

test_tracking_start_without_version_does_not_run_hooks() {
    # No --version means no VERSION/tag is ever written; there is nothing for
    # post-bump hooks to react to, so they must not be invoked at all.
    local dir
    dir=$(mktemp -d "/tmp/semver-test-XXXXXX")
    trap "cleanup_test_repo '$dir'" RETURN
    cd "$dir"
    git init -q
    git branch -M main
    git config user.name "Test"
    git config user.email "test@test.com"
    echo "init" > README.md
    git add README.md
    git commit -q -m "chore: initial commit"
    mkdir -p .semver/hooks/post-bump
    cat > .semver/hooks/post-bump/01-marker.sh << HOOK
#!/usr/bin/env bash
echo "ran" > "$dir/.hook-ran"
HOOK
    chmod +x .semver/hooks/post-bump/01-marker.sh
    git add -A && git commit -q -m "add post-bump hook"

    local out; out=$(cd "$dir" && "$CLI" tracking start)

    assert_json_field "$out" ".version_set" "false" "no version should be set" &&
    local has_post_hooks
    has_post_hooks=$(echo "$out" | jq 'has("post_hooks")')
    assert_eq "false" "$has_post_hooks" "post_hooks block should not appear without a version" &&
    assert_file_not_exists "$dir/.hook-ran" "hook must not run when no version was written"
}
