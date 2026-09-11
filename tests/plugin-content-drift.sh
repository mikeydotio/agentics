#!/usr/bin/env bash
# tests/plugin-content-drift.sh — marketplace-wide content-drift guard.
#
# WHY: Claude Code's plugin cache is keyed by the version string. If shipped
# plugin content changes but the single repo VERSION does not advance, installs
# that already cached that version never re-extract — they keep running the old
# code while the manifest *reports* the (unchanged) version. That is exactly the
# failure in issue #71: a deployit fix landed under an already-released 2.25.1
# without a bump, so no install ever received it. `tests/plugin-versions.sh`
# proves every manifest == VERSION, but it cannot see this: the manifests stay
# internally consistent with the stale VERSION. This guard closes that gap.
#
# HOW: git blob OIDs *are* content hashes, so `git diff <tag> HEAD -- <paths>`
# is a content-hash-vs-version check for free. The invariant: the shipped
# runtime bytes under plugins/**
# must not differ from the release tag v<VERSION> unless VERSION has advanced.
# The moment you change shipped content you must `/semver bump` (which retags at
# the new HEAD) or this fails the pre-push gate.
#
# SCOPE: everything under plugins/ counts as shipped/runtime EXCEPT test
# harnesses (plugins/*/tests/**, **/*.bats — never executed from an install)
# and GitHub-facing plugin READMEs. Erring toward over-inclusion is deliberate:
# under-inclusion misses a real "runs old code" drift (the bug); over-inclusion
# only forces an unnecessary — harmless — bump. .claude-plugin/plugin.json IS
# included and is false-positive-safe: the sync hook folds the restamped
# manifests into the tagged release commit, so v<VERSION> and HEAD carry the
# same `version` between bumps.
#
# Self-contained plain-bash harness (NO bats) so it runs under `make test` on
# every machine — mirrors tests/plugin-versions.sh: define test_* functions, run
# each in an isolated subshell, print "  PASS|FAIL  fn", exit with the failure
# count. This remains part of the repository-owned test suite after retirement
# of the global push-test hook (AGE-102).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

fail() { echo "$1" >&2; return 1; }

bare_version() { tr -d '[:space:]' < "$REPO_ROOT/VERSION" | sed 's/^v//'; }

# Shipped runtime pathspec. `glob` magic makes `*` match one path segment and
# `**` cross directories — predictable and precise. Kept as an array so it is
# passed to git as distinct argv entries, not a re-split string.
SHIPPED_PATHSPEC=(
    'plugins/'
    ':(exclude,glob)plugins/*/tests/**'   # test harnesses never run from an install
    ':(exclude,glob)plugins/**/*.bats'    # bats also live in plugins/*/bin, plugins/*/lib
    ':(exclude,glob)plugins/*/README.md'  # GitHub-facing docs, not read at runtime
)

# --- Shared primitives (work on any repo root; used by the real check + fixtures) ---

tag_for()     { echo "v$(tr -d '[:space:]' < "$1/VERSION" | sed 's/^v//')"; }
tag_present() { git -C "$1" rev-parse -q --verify "refs/tags/$(tag_for "$1")" >/dev/null 2>&1; }

# Echo the shipped files that differ between v<VERSION> and HEAD (empty if none).
# Caller MUST gate on tag_present first — without the tag, git diff would error.
drifted_names() {
    git -C "$1" diff --name-only "$(tag_for "$1")" HEAD -- "${SHIPPED_PATHSPEC[@]}"
}

# --- Drift invariant (real repo) -------------------------------------------

test_shipped_content_matches_tagged_release() {
    local tag; tag="$(tag_for "$REPO_ROOT")"
    if ! tag_present "$REPO_ROOT"; then
        # Fail open: the only legitimate way the current tag is missing is a
        # fresh/shallow clone in the merge->tag-push gap, where HEAD == the
        # release commit anyway. A forgotten bump always has the last release
        # tag present, so the guard still fires when it matters.
        echo "        (skip) tag $tag not present locally — content-drift check skipped" >&2
        return 0
    fi
    local drifted; drifted="$(drifted_names "$REPO_ROOT")"
    if [ -n "$drifted" ]; then
        fail "shipped plugin content changed since $tag was tagged, but VERSION is still $(bare_version).
        Run \`/semver bump\` (patch/minor/major) before pushing so version-keyed installs re-extract.
        Drifted shipped files:
$(echo "$drifted" | sed 's/^/          /')"
    fi
}

# --- Behaviour of the invariant (throwaway fixtures) -----------------------

# A minimal marketplace-shaped repo: one plugin with a shipped bin file, a test
# harness, and a README, committed and tagged v1.0.0 (HEAD == tag => clean).
make_fixture_repo() {
    local fix; fix="$(mktemp -d)"
    printf 'v1.0.0\n' > "$fix/VERSION"
    mkdir -p "$fix/plugins/alpha/bin" "$fix/plugins/alpha/tests"
    printf '#!/bin/sh\necho hi\n' > "$fix/plugins/alpha/bin/tool"
    printf 'test harness\n'       > "$fix/plugins/alpha/tests/test-tool.sh"
    printf 'plugin readme\n'      > "$fix/plugins/alpha/README.md"
    git -C "$fix" init -q
    git -C "$fix" config user.email "t@t.t"
    git -C "$fix" config user.name  "T"
    git -C "$fix" add -A
    git -C "$fix" commit -qm "chore(release): v1.0.0"
    git -C "$fix" tag v1.0.0
    echo "$fix"
}

test_fixture_clean_at_tag_is_green() {
    local fix; fix="$(make_fixture_repo)"; trap "rm -rf '$fix'" EXIT
    [ -z "$(drifted_names "$fix")" ] || fail "clean fixture (HEAD == tag) reported drift"
}

test_fixture_shipped_bin_change_is_red() {
    local fix; fix="$(make_fixture_repo)"; trap "rm -rf '$fix'" EXIT
    printf 'echo changed\n' >> "$fix/plugins/alpha/bin/tool"
    git -C "$fix" commit -qam "change shipped bin"
    [ -n "$(drifted_names "$fix")" ] || fail "shipped bin change was not detected as drift"
}

test_fixture_tests_only_change_is_green() {
    local fix; fix="$(make_fixture_repo)"; trap "rm -rf '$fix'" EXIT
    printf 'more harness\n' >> "$fix/plugins/alpha/tests/test-tool.sh"
    git -C "$fix" commit -qam "change test harness only"
    [ -z "$(drifted_names "$fix")" ] || fail "test-only change wrongly forced a bump"
}

test_fixture_bats_change_is_green() {
    local fix; fix="$(make_fixture_repo)"; trap "rm -rf '$fix'" EXIT
    printf '@test x {}\n' > "$fix/plugins/alpha/bin/tool.bats"   # .bats outside tests/
    git -C "$fix" add -A
    git -C "$fix" commit -qm "add a bats file next to bin/"
    [ -z "$(drifted_names "$fix")" ] || fail "a *.bats change wrongly forced a bump"
}

test_fixture_readme_change_is_green() {
    local fix; fix="$(make_fixture_repo)"; trap "rm -rf '$fix'" EXIT
    printf 'more readme\n' >> "$fix/plugins/alpha/README.md"
    git -C "$fix" commit -qam "tweak plugin README"
    [ -z "$(drifted_names "$fix")" ] || fail "a plugin README change wrongly forced a bump"
}

test_fixture_new_plugin_dir_is_red() {
    local fix; fix="$(make_fixture_repo)"; trap "rm -rf '$fix'" EXIT
    mkdir -p "$fix/plugins/beta/bin"
    printf '#!/bin/sh\necho beta\n' > "$fix/plugins/beta/bin/tool"
    git -C "$fix" add -A
    git -C "$fix" commit -qm "add a brand-new plugin beta"
    [ -n "$(drifted_names "$fix")" ] || fail "a brand-new plugin dir was not detected as drift"
}

test_fixture_missing_tag_is_skip() {
    local fix; fix="$(make_fixture_repo)"; trap "rm -rf '$fix'" EXIT
    printf 'echo changed\n' >> "$fix/plugins/alpha/bin/tool"
    git -C "$fix" commit -qam "change shipped bin"
    git -C "$fix" tag -d v1.0.0 >/dev/null
    # With the tag gone the guard hits its fail-open branch (gates on tag_present
    # before ever calling drifted_names, which would otherwise error).
    ! tag_present "$fix" || fail "tag should be absent after deletion"
}

# --- Runner ----------------------------------------------------------------

command -v git >/dev/null 2>&1 || { echo "ERROR: git is required" >&2; exit 1; }

PASS=0
FAIL=0
FAILURES=()

echo "=== plugin-content-drift ==="
for fn in $(declare -F | awk '{print $3}' | grep '^test_' | sort); do
    set +e
    out="$( set -e; "$fn" 2>&1 )"
    ec=$?
    set -e
    if [ $ec -eq 0 ]; then
        echo "  PASS  $fn"
        [ -n "$out" ] && echo "$out" | sed 's/^/        /'
        PASS=$((PASS + 1))
    else
        echo "  FAIL  $fn"
        [ -n "$out" ] && echo "$out" | sed 's/^/        /'
        FAIL=$((FAIL + 1))
        FAILURES+=("$fn")
    fi
done

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    printf 'Failures:\n'
    printf '  - %s\n' "${FAILURES[@]}"
fi
exit "$FAIL"
