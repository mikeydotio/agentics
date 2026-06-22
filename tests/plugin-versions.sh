#!/usr/bin/env bash
# tests/plugin-versions.sh — marketplace-wide manifest version sync.
#
# Self-contained plain-bash harness (NO bats dependency) so it runs under
# `make test` on every machine — bats is not installed here and this project does
# not run tests in CI, so a .bats file would never actually execute. Mirrors the
# per-plugin harness convention: define test_* functions, run each in an isolated
# subshell, print "=== name ===" / "  PASS|FAIL  fn", exit with the failure count.
#
# Covers two concerns:
#   1. Drift invariant on the REAL repo — the top-level marketplace.json and every
#      plugins/*/.claude-plugin/plugin.json carry a `version` equal to the bare
#      VERSION. This is the enforceable half of the "a bump can never miss a
#      manifest" promise; it fails the pre-push gate the moment a manifest drifts.
#   2. Behaviour of .semver/hooks/post-bump/01-sync-plugin-versions.sh in both its
#      standalone (files-only) and post-bump (amend + retag) modes, exercised in a
#      throwaway fixture so the trickiest path — folding into the release commit —
#      is actually proven, not assumed.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SYNC_SCRIPT="$REPO_ROOT/.semver/hooks/post-bump/01-sync-plugin-versions.sh"

fail() { echo "$1" >&2; return 1; }

bare_version() { tr -d '[:space:]' < "$REPO_ROOT/VERSION" | sed 's/^v//'; }

# Every version-bearing manifest in the real repo: marketplace.json + each plugin.json.
all_manifests() {
    [ -f "$REPO_ROOT/.claude-plugin/marketplace.json" ] && echo "$REPO_ROOT/.claude-plugin/marketplace.json"
    local f
    for f in "$REPO_ROOT"/plugins/*/.claude-plugin/plugin.json; do
        [ -f "$f" ] && echo "$f"
    done
}

# Create a throwaway fixture repo (a marketplace.json + two plugins, VERSION v9.9.9,
# the hook copied in at its canonical path) and echo its directory. The hook resolves
# the repo root relative to itself, so copying it to <fix>/.semver/hooks/post-bump/
# makes <fix> its target.
make_fixture() {
    local fix
    fix="$(mktemp -d)"
    mkdir -p "$fix/.semver/hooks/post-bump" "$fix/.claude-plugin"
    cp "$SYNC_SCRIPT" "$fix/.semver/hooks/post-bump/01-sync-plugin-versions.sh"
    chmod +x "$fix/.semver/hooks/post-bump/01-sync-plugin-versions.sh"
    printf 'v9.9.9\n' > "$fix/VERSION"
    printf '{\n  "$schema": "https://example/marketplace.schema.json",\n  "name": "fixturemarket",\n  "description": "fixture marketplace",\n  "owner": { "name": "x" },\n  "plugins": [ { "name": "alpha", "source": "./plugins/alpha" } ]\n}\n' \
        > "$fix/.claude-plugin/marketplace.json"
    mkdir -p "$fix/plugins/alpha/.claude-plugin" "$fix/plugins/beta/.claude-plugin"
    printf '{\n  "name": "alpha",\n  "description": "A plugin",\n  "author": { "name": "x" }\n}\n' \
        > "$fix/plugins/alpha/.claude-plugin/plugin.json"
    printf '{\n  "name": "beta",\n  "description": "B plugin"\n}\n' \
        > "$fix/plugins/beta/.claude-plugin/plugin.json"
    echo "$fix"
}

fixture_script() { echo "$1/.semver/hooks/post-bump/01-sync-plugin-versions.sh"; }

# Turn a fixture into a repo with a single tagged release commit, mimicking the
# state semver leaves the tree in right before it invokes the post-bump hook.
init_release_repo() {
    git -C "$1" init -q
    git -C "$1" config user.email "t@t.t"
    git -C "$1" config user.name "T"
    git -C "$1" add -A
    git -C "$1" commit -qm "chore(release): v9.9.9"
    git -C "$1" tag v9.9.9
}

# --- Drift invariant (real repo) -------------------------------------------

test_sync_hook_is_executable() {
    [ -x "$SYNC_SCRIPT" ] || fail "hook not executable: $SYNC_SCRIPT"
}

test_every_manifest_declares_nonempty_version() {
    local f v
    while IFS= read -r f; do
        v="$(jq -r '.version // ""' "$f")"
        [ -n "$v" ] || fail "missing version in $f"
    done < <(all_manifests)
}

test_every_manifest_matches_bare_version() {
    local want f got
    want="$(bare_version)"
    while IFS= read -r f; do
        got="$(jq -r '.version // ""' "$f")"
        [ "$got" = "$want" ] || fail "$f has version '$got', expected '$want'"
    done < <(all_manifests)
}

test_marketplace_manifest_is_covered() {
    # Guard against the drift loop silently skipping the marketplace manifest.
    all_manifests | grep -q '/.claude-plugin/marketplace.json$' \
        || fail "marketplace.json not in the synced manifest set"
}

# --- Standalone mode (fixture) ---------------------------------------------

test_standalone_stamps_bare_version_into_all_manifests() {
    local fix; fix="$(make_fixture)"; trap "rm -rf '$fix'" EXIT
    bash "$(fixture_script "$fix")" >/dev/null
    [ "$(jq -r .version "$fix/.claude-plugin/marketplace.json")" = "9.9.9" ] || fail "marketplace not synced"
    [ "$(jq -r .version "$fix/plugins/alpha/.claude-plugin/plugin.json")" = "9.9.9" ] || fail "alpha not synced"
    [ "$(jq -r .version "$fix/plugins/beta/.claude-plugin/plugin.json")" = "9.9.9" ] || fail "beta not synced"
}

test_standalone_syncs_marketplace_and_preserves_structure() {
    local fix; fix="$(make_fixture)"; trap "rm -rf '$fix'" EXIT
    bash "$(fixture_script "$fix")" >/dev/null
    local mf="$fix/.claude-plugin/marketplace.json"
    [ "$(jq -r .version "$mf")" = "9.9.9" ] || fail "marketplace version not set"
    # version sits immediately after name; $schema, owner and the plugins array survive.
    [ "$(jq -r 'keys_unsorted | join(",")' "$mf")" = "\$schema,name,version,description,owner,plugins" ] \
        || fail "unexpected marketplace key order: $(jq -rc keys_unsorted "$mf")"
    [ "$(jq -r '.["$schema"]' "$mf")" != "null" ] || fail "\$schema dropped"
    [ "$(jq -r '.owner.name' "$mf")" = "x" ] || fail "owner dropped"
    [ "$(jq -r '.plugins | length' "$mf")" = "1" ] || fail "plugins array not preserved"
    [ "$(jq -r '.plugins[0].source' "$mf")" = "./plugins/alpha" ] || fail "plugins entry mangled"
}

test_standalone_preserves_other_fields_and_key_order() {
    local fix; fix="$(make_fixture)"; trap "rm -rf '$fix'" EXIT
    bash "$(fixture_script "$fix")" >/dev/null
    [ "$(jq -r .name "$fix/plugins/alpha/.claude-plugin/plugin.json")" = "alpha" ] || fail "name lost"
    [ "$(jq -r '.author.name' "$fix/plugins/alpha/.claude-plugin/plugin.json")" = "x" ] || fail "author lost"
    [ "$(jq -r 'keys_unsorted | join(",")' "$fix/plugins/alpha/.claude-plugin/plugin.json")" \
        = "name,version,description,author" ] || fail "unexpected key order"
}

test_standalone_is_idempotent() {
    local fix; fix="$(make_fixture)"; trap "rm -rf '$fix'" EXIT
    bash "$(fixture_script "$fix")" >/dev/null
    local out; out="$(bash "$(fixture_script "$fix")")"
    [[ "$out" == *"(0 updated)"* ]] || fail "second run not a no-op: $out"
}

test_standalone_creates_no_git_state() {
    local fix; fix="$(make_fixture)"; trap "rm -rf '$fix'" EXIT
    bash "$(fixture_script "$fix")" >/dev/null
    [ ! -d "$fix/.git" ] || fail "standalone run created git state"
}

test_new_version_env_overrides_file_and_strips_prefix() {
    local fix; fix="$(make_fixture)"; trap "rm -rf '$fix'" EXIT
    NEW_VERSION=v1.2.3 bash "$(fixture_script "$fix")" >/dev/null
    [ "$(jq -r .version "$fix/plugins/alpha/.claude-plugin/plugin.json")" = "1.2.3" ] \
        || fail "NEW_VERSION env not honored / prefix not stripped"
}

# --- Post-bump mode (fixture) ----------------------------------------------

test_postbump_folds_manifests_into_release_commit_and_moves_tag() {
    local fix; fix="$(make_fixture)"; trap "rm -rf '$fix'" EXIT
    init_release_repo "$fix"
    local before after
    before="$(git -C "$fix" rev-parse HEAD)"
    SEMVER_BUMP_IN_PROGRESS=1 NEW_VERSION=v9.9.9 bash "$(fixture_script "$fix")" >/dev/null
    after="$(git -C "$fix" rev-parse HEAD)"
    [ "$(jq -r .version "$fix/plugins/alpha/.claude-plugin/plugin.json")" = "9.9.9" ] || fail "manifest not synced"
    [ -z "$(git -C "$fix" status --porcelain)" ] || fail "working tree left dirty (change not folded in)"
    [ "$before" != "$after" ] || fail "release commit was not amended"
    [ "$(git -C "$fix" rev-parse v9.9.9)" = "$after" ] || fail "tag not moved onto amended commit"
    # Verify the synced manifests are the versions actually committed at HEAD (robust:
    # reads committed content rather than parsing diff --stat, which wraps paths).
    [ "$(git -C "$fix" show "HEAD:plugins/alpha/.claude-plugin/plugin.json" | jq -r .version)" = "9.9.9" ] \
        || fail "synced plugin manifest is not committed into the release commit"
    [ "$(git -C "$fix" show "HEAD:.claude-plugin/marketplace.json" | jq -r .version)" = "9.9.9" ] \
        || fail "synced marketplace manifest is not committed into the release commit"
}

test_postbump_does_not_stage_unrelated_working_tree_changes() {
    local fix; fix="$(make_fixture)"; trap "rm -rf '$fix'" EXIT
    init_release_repo "$fix"
    printf 'scratch\n' > "$fix/UNRELATED.txt"   # as if restored from a pre-bump stash
    SEMVER_BUMP_IN_PROGRESS=1 NEW_VERSION=v9.9.9 bash "$(fixture_script "$fix")" >/dev/null
    [ "$(git -C "$fix" status --porcelain -- UNRELATED.txt)" = "?? UNRELATED.txt" ] \
        || fail "unrelated file was staged/committed"
    # Robust absence check: the path must not exist in HEAD's tree at all.
    if git -C "$fix" cat-file -e "HEAD:UNRELATED.txt" 2>/dev/null; then
        fail "unrelated file leaked into the release commit"
    fi
}

# --- Runner ----------------------------------------------------------------

command -v jq  >/dev/null 2>&1 || { echo "ERROR: jq is required"  >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "ERROR: git is required" >&2; exit 1; }

PASS=0
FAIL=0
FAILURES=()

echo "=== plugin-version-sync ==="
for fn in $(declare -F | awk '{print $3}' | grep '^test_' | sort); do
    set +e
    out="$( set -e; "$fn" 2>&1 )"
    ec=$?
    set -e
    if [ $ec -eq 0 ]; then
        echo "  PASS  $fn"
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
