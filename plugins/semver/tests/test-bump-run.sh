#!/usr/bin/env bash
# Tests for the agent-token-reduction features:
#   - `semver-cli recommend`  — deterministic bump-level recommendation
#   - `semver-cli bump run`   — single-call gather-then-execute happy path,
#                               with safe hand-back / non-interactive abort
#   - `bump gather` no longer ships the (unused) full commits array
#
# Uses $CLI from helpers/setup.sh. Self-contained repo fixture so this file
# does not depend on glob ordering relative to other test files.

# Self-contained tracked-repo fixture (mirrors test-cli.sh's create_semver_repo).
_make_tracked_repo() {
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

_commit() {
    local repo="$1" file="$2" msg="$3"
    echo "$file" > "$repo/$file"
    git -C "$repo" add -A
    git -C "$repo" commit -q -m "$msg"
}


# ═══════════════════════════════════════════════════════════════════════════
# recommend — deterministic level from conventional commits
# ═══════════════════════════════════════════════════════════════════════════

test_recommend_minor_for_feat() {
    local repo; repo=$(_make_tracked_repo)
    trap "cleanup_test_repo '$repo'" RETURN
    _commit "$repo" a.txt "feat: add a shiny feature"

    local out; out=$(cd "$repo" && "$CLI" recommend)
    assert_json_field "$out" ".ok" "true" "ok" &&
    assert_json_field "$out" ".recommended" "minor" "feat -> minor" &&
    assert_json_field "$out" ".counts.feat" "1" "one feat counted"
}

test_recommend_major_for_breaking_subject() {
    local repo; repo=$(_make_tracked_repo)
    trap "cleanup_test_repo '$repo'" RETURN
    _commit "$repo" a.txt "feat!: breaking redesign"

    local out; out=$(cd "$repo" && "$CLI" recommend)
    assert_json_field "$out" ".recommended" "major" "feat! -> major" &&
    assert_json_field "$out" ".counts.breaking" "1" "one breaking counted"
}

test_recommend_patch_for_fix_only() {
    local repo; repo=$(_make_tracked_repo)
    trap "cleanup_test_repo '$repo'" RETURN
    _commit "$repo" a.txt "fix: correct an off-by-one"

    local out; out=$(cd "$repo" && "$CLI" recommend)
    assert_json_field "$out" ".recommended" "patch" "fix -> patch" &&
    assert_json_field "$out" ".counts.fix" "1" "one fix counted"
}

test_recommend_patch_for_docs_only() {
    local repo; repo=$(_make_tracked_repo)
    trap "cleanup_test_repo '$repo'" RETURN
    _commit "$repo" a.txt "docs: tidy the readme"

    local out; out=$(cd "$repo" && "$CLI" recommend)
    assert_json_field "$out" ".recommended" "patch" "docs-only -> patch"
}

test_recommend_precedence_breaking_beats_feat_beats_fix() {
    local repo; repo=$(_make_tracked_repo)
    trap "cleanup_test_repo '$repo'" RETURN
    _commit "$repo" a.txt "fix: a fix"
    _commit "$repo" b.txt "feat: a feature"
    _commit "$repo" c.txt "feat!: a breaking change"

    local out; out=$(cd "$repo" && "$CLI" recommend)
    assert_json_field "$out" ".recommended" "major" "breaking wins over feat/fix" &&
    assert_json_field "$out" ".counts.total" "3" "all three counted"
}

test_recommend_null_when_no_commits() {
    local repo; repo=$(_make_tracked_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    local out; out=$(cd "$repo" && "$CLI" recommend)
    assert_json_field "$out" ".ok" "true" "ok" &&
    assert_json_field "$out" ".recommended" "null" "no commits -> null" &&
    assert_json_field "$out" ".commits_analyzed" "0" "zero analyzed"
}

test_recommend_ignores_release_commits() {
    # A stray release commit since the last version must not be counted.
    local repo; repo=$(_make_tracked_repo)
    trap "cleanup_test_repo '$repo'" RETURN
    _commit "$repo" x.txt "chore(release): v9.9.9"

    local out; out=$(cd "$repo" && "$CLI" recommend)
    assert_json_field "$out" ".recommended" "null" "release commit ignored -> null" &&
    assert_json_field "$out" ".commits_analyzed" "0" "release commit not analyzed"
}

test_recommend_tracking_inactive() {
    local repo; repo=$(_make_tracked_repo)
    trap "cleanup_test_repo '$repo'" RETURN
    cat > "$repo/.semver/config.yaml" << 'YAML'
tracking: false
auto_bump: false
auto_bump_confirm: true
version_prefix: "v"
git_tagging: true
changelog_format: "grouped"
target_branch: "main"
YAML

    local out; out=$(cd "$repo" && "$CLI" recommend)
    assert_json_field "$out" ".ok" "true" "informational, not an error" &&
    assert_json_field "$out" ".tracking" "false" "tracking false" &&
    assert_json_field "$out" ".recommended" "null" "no recommendation when inactive"
}


# ═══════════════════════════════════════════════════════════════════════════
# bump run — single-call happy path
# ═══════════════════════════════════════════════════════════════════════════

test_bump_run_happy_path_executes_in_one_call() {
    local repo; repo=$(_make_tracked_repo)
    trap "cleanup_test_repo '$repo'" RETURN
    _commit "$repo" a.txt "feat: a new feature"

    local out; out=$(cd "$repo" && "$CLI" bump run minor)
    assert_json_field "$out" ".ok" "true" "ok" &&
    assert_json_field "$out" ".executed" "true" "happy path auto-executes" &&
    assert_json_field "$out" ".old_version" "v1.0.0" "old_version" &&
    assert_json_field "$out" ".new_version" "v1.1.0" "new_version" &&
    assert_json_field "$out" ".tag_created" "true" "tag created" &&
    local v; v=$(cat "$repo/VERSION" | tr -d '[:space:]')
    assert_eq "v1.1.0" "$v" "VERSION written" &&
    local tag; tag=$(git -C "$repo" tag -l v1.1.0)
    assert_eq "v1.1.0" "$tag" "git tag exists" &&
    assert_file_contains "$repo/CHANGELOG.md" "## \\[v1.1.0\\]" "changelog entry written"
}

test_bump_run_dirty_tree_hands_back_without_executing() {
    local repo; repo=$(_make_tracked_repo)
    trap "cleanup_test_repo '$repo'" RETURN
    _commit "$repo" a.txt "feat: a new feature"
    echo "uncommitted" > "$repo/dirty.txt"

    local out; out=$(cd "$repo" && "$CLI" bump run minor)
    assert_json_field "$out" ".ok" "true" "ok" &&
    assert_json_field "$out" ".executed" "false" "must NOT auto-execute with a dirty tree" &&
    local has_dirty_q; has_dirty_q=$(echo "$out" | jq '.questions_needed | index("dirty_tree") != null')
    assert_eq "true" "$has_dirty_q" "returns the dirty_tree question for the agent" &&
    local v; v=$(cat "$repo/VERSION" | tr -d '[:space:]')
    assert_eq "v1.0.0" "$v" "VERSION untouched when handed back"
}

test_bump_run_no_commits_hands_back() {
    local repo; repo=$(_make_tracked_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    local out; out=$(cd "$repo" && "$CLI" bump run minor)
    assert_json_field "$out" ".executed" "false" "no execute without commits" &&
    assert_json_field "$out" ".no_commits" "true" "no_commits flagged"
}

test_bump_run_force_executes_with_no_commits() {
    local repo; repo=$(_make_tracked_repo)
    trap "cleanup_test_repo '$repo'" RETURN

    local out; out=$(cd "$repo" && "$CLI" bump run patch --force --source force)
    assert_json_field "$out" ".executed" "true" "force executes despite no commits" &&
    assert_json_field "$out" ".new_version" "v1.0.1" "patch bump"
}

test_bump_run_wrong_branch_hands_back() {
    local repo; repo=$(_make_tracked_repo)
    trap "cleanup_test_repo '$repo'" RETURN
    git -C "$repo" checkout -q -b feature-branch
    _commit "$repo" a.txt "feat: work on a branch"

    local out; out=$(cd "$repo" && "$CLI" bump run minor)
    assert_json_field "$out" ".executed" "false" "must not execute off the target branch" &&
    local has_branch_q; has_branch_q=$(echo "$out" | jq '.questions_needed | index("wrong_branch") != null')
    assert_eq "true" "$has_branch_q" "returns the wrong_branch question"
}


# ═══════════════════════════════════════════════════════════════════════════
# bump run — non-interactive (unattended auto-bump)
# ═══════════════════════════════════════════════════════════════════════════

test_bump_run_non_interactive_aborts_on_dirty() {
    local repo; repo=$(_make_tracked_repo)
    trap "cleanup_test_repo '$repo'" RETURN
    _commit "$repo" a.txt "feat: a new feature"
    echo "uncommitted" > "$repo/dirty.txt"

    local out; out=$(cd "$repo" && "$CLI" bump run minor --non-interactive)
    assert_json_field "$out" ".ok" "false" "aborts rather than asking" &&
    assert_json_field "$out" ".error" "non_interactive_blocked" "clear error code" &&
    local v; v=$(cat "$repo/VERSION" | tr -d '[:space:]')
    assert_eq "v1.0.0" "$v" "VERSION untouched on abort"
}

test_bump_run_non_interactive_executes_when_clean() {
    local repo; repo=$(_make_tracked_repo)
    trap "cleanup_test_repo '$repo'" RETURN
    _commit "$repo" a.txt "feat: a new feature"

    local out; out=$(cd "$repo" && "$CLI" bump run minor --non-interactive --source auto)
    assert_json_field "$out" ".executed" "true" "clean unattended bump executes" &&
    assert_json_field "$out" ".new_version" "v1.1.0" "new_version"
}

test_bump_run_reentrancy_guard() {
    local repo; repo=$(_make_tracked_repo)
    trap "cleanup_test_repo '$repo'" RETURN
    _commit "$repo" a.txt "feat: a new feature"

    # bump run's hard-error branch now exits 1 (matching bump execute's
    # output_error for the same condition), so the invocation must be guarded
    # from set -e like every other nonzero-exit CLI call in this suite.
    local out ec
    set +e
    out=$(cd "$repo" && SEMVER_BUMP_IN_PROGRESS=1 "$CLI" bump run minor 2>&1); ec=$?
    set -e
    assert_json_field "$out" ".ok" "false" "reentrancy blocked" &&
    assert_json_field "$out" ".error" "reentrancy" "reentrancy error code" &&
    assert_exit_code "1" "$ec" "reentrancy is a hard error — exit 1"
}


# ═══════════════════════════════════════════════════════════════════════════
# bump gather — payload trimmed (Phase 2A) + executed marker
# ═══════════════════════════════════════════════════════════════════════════

test_bump_gather_omits_full_commits_array() {
    local repo; repo=$(_make_tracked_repo)
    trap "cleanup_test_repo '$repo'" RETURN
    _commit "$repo" a.txt "feat: a new feature"

    local out; out=$(cd "$repo" && "$CLI" bump gather minor)
    local has_commits; has_commits=$(echo "$out" | jq 'has("commits")')
    assert_eq "false" "$has_commits" "gather must not ship the unused commits array" &&
    assert_json_field "$out" ".commits_since_last_bump" "1" "scalar count is retained"
}

test_bump_gather_marks_not_executed() {
    local repo; repo=$(_make_tracked_repo)
    trap "cleanup_test_repo '$repo'" RETURN
    _commit "$repo" a.txt "feat: a new feature"

    local out; out=$(cd "$repo" && "$CLI" bump gather minor)
    assert_json_field "$out" ".executed" "false" "gather is never an executed result"
}
