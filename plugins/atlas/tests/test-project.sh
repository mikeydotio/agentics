#!/usr/bin/env bash
# Tests for `atlas-cli project` (Wave 4) — the deterministic JOIN that renders
# committed docs from the Structure Index + Judgment Cache. The load-bearing
# properties: rendered module docs pass v1 lint L1 (skeleton) byte-for-byte,
# rendering is idempotent and deterministic, a missing cell renders a visible
# placeholder, and ingesting a cell fills it on the next project.

_project_fixture() {
    local repo
    repo=$(create_fixture_repo)
    mkdir -p "$repo/src/auth" "$repo/src/api"
    cat > "$repo/src/auth/service.py" <<'PY'
class AuthService:
    def login(self):
        return _hash_token(1)

def _hash_token(x):
    return x
PY
    cat > "$repo/src/api/client.py" <<'PY'
from src.auth.service import _hash_token

def send(kind):
    return _hash_token(kind)
PY
    local i
    for i in 1 2 3 4 5 6 7; do
        seed_file "$repo" "src/auth/pad$i.txt"
        seed_file "$repo" "src/api/pad$i.txt"
    done
    commit_all "$repo"
    echo "$repo"
}

# ingest_cell <repo> <kind> <symbol-or-module> <value>
ingest_cell() {
    local repo="$1" kind="$2" anchor="$3" value="$4"
    run_atlas "$repo" judge-plan
    local key
    key=$(echo "$OUTPUT" | jq -r --arg k "$kind" --arg a "$anchor" \
        '.missing_keys[] | select(.kind==$k and ((.symbol // .module)==$a)) | .key' | head -1)
    [ -n "$key" ] || { echo "    (no key for $kind/$anchor)"; return 1; }
    printf '[{"key":"%s","kind":"%s","value":%s}]' "$key" "$kind" "$value" \
        | (cd "$repo" && python3 "$CLI" judgment ingest >/dev/null)
}

test_project_writes_module_and_overview_docs() {
    local repo; repo=$(_project_fixture)
    run_atlas "$repo" project
    assert_exit_code 0 "$EXIT_CODE" "project exits 0" || return 1
    assert_file_exists "$repo/docs/atlas/modules/src-auth.md" "src-auth doc" || return 1
    assert_file_exists "$repo/docs/atlas/modules/src-api.md" "src-api doc" || return 1
    assert_file_exists "$repo/docs/atlas/overview/ARCHITECTURE.md" "overview doc" || return 1
    cleanup_fixture_repo "$repo"
}

test_projected_module_doc_passes_lint_l1() {
    local repo; repo=$(_project_fixture)
    run_atlas "$repo" project
    run_atlas "$repo" lint
    # The skeleton check (L1) must be clean on every projected module doc, even
    # with all judgment cells still placeholders.
    local l1_errors
    l1_errors=$(echo "$OUTPUT" | jq -r '[.errors[]? | select(.check=="L1")] | length')
    assert_eq "0" "$l1_errors" "no L1 skeleton errors on projected docs" || return 1
    cleanup_fixture_repo "$repo"
}

test_project_is_idempotent() {
    local repo; repo=$(_project_fixture)
    run_atlas "$repo" project
    run_atlas "$repo" project
    assert_json_field "$OUTPUT" '.changed' "0" "second project rewrites nothing" || return 1
    cleanup_fixture_repo "$repo"
}

test_project_is_byte_identical_across_runs() {
    local repo; repo=$(_project_fixture)
    run_atlas "$repo" project
    local h1; h1=$(shasum "$repo/docs/atlas/modules/src-auth.md" | awk '{print $1}')
    rm -f "$repo/docs/atlas/modules/src-auth.md"
    run_atlas "$repo" project
    local h2; h2=$(shasum "$repo/docs/atlas/modules/src-auth.md" | awk '{print $1}')
    assert_eq "$h1" "$h2" "re-rendered doc is byte-identical" || return 1
    cleanup_fixture_repo "$repo"
}

test_missing_cell_renders_placeholder() {
    local repo; repo=$(_project_fixture)
    run_atlas "$repo" project
    assert_json_field "$OUTPUT" '.placeholder_count > 0' "true" "placeholders counted" || return 1
    grep -q '_(pending judgment)_' "$repo/docs/atlas/modules/src-auth.md" || {
        echo "    FAIL: placeholder text not present in doc"; return 1; }
    cleanup_fixture_repo "$repo"
}

test_ingested_cell_fills_placeholder_on_reproject() {
    local repo; repo=$(_project_fixture)
    run_atlas "$repo" project
    local before; before=$(echo "$OUTPUT" | jq -r '.placeholder_count')

    ingest_cell "$repo" module.purpose "src-auth" '"Owns auth and session lifecycle."' || return 1
    run_atlas "$repo" project
    local after; after=$(echo "$OUTPUT" | jq -r '.placeholder_count')

    [ "$after" -lt "$before" ] || {
        echo "    FAIL: placeholder_count should drop after ingest ($before -> $after)"; return 1; }
    grep -q 'Owns auth and session lifecycle.' "$repo/docs/atlas/modules/src-auth.md" || {
        echo "    FAIL: ingested purpose not rendered"; return 1; }
    cleanup_fixture_repo "$repo"
}

test_public_symbol_in_api_private_referenced_in_loadbearing() {
    local repo; repo=$(_project_fixture)
    run_atlas "$repo" project
    local doc="$repo/docs/atlas/modules/src-auth.md"
    # AuthService is public → Public API; _hash_token is private but referenced
    # cross-file → Load-bearing internals.
    local api lb
    api=$(awk '/## Public API/,/## Load-bearing/' "$doc")
    lb=$(awk '/## Load-bearing internals/,/## Relationships/' "$doc")
    echo "$api" | grep -q 'AuthService' || { echo "    FAIL: AuthService not in Public API"; return 1; }
    echo "$lb" | grep -q '_hash_token' || { echo "    FAIL: _hash_token not in Load-bearing"; return 1; }
    cleanup_fixture_repo "$repo"
}

test_cross_module_relationship_and_refs() {
    local repo; repo=$(_project_fixture)
    run_atlas "$repo" project
    local doc="$repo/docs/atlas/modules/src-api.md"
    # send (src-api) calls _hash_token (src-auth) → a cross-module edge, and
    # src-auth must appear in references_modules.
    grep -q 'src-api.send -> src-auth._hash_token (calls)' "$doc" || {
        echo "    FAIL: cross-module relationship not rendered"; cat "$doc"; return 1; }
    grep -q 'references_modules: \[src-auth\]' "$doc" || {
        echo "    FAIL: references_modules not set"; return 1; }
    cleanup_fixture_repo "$repo"
}

test_project_requires_git_repo() {
    local dir; dir=$(mktemp -d "/tmp/atlas-tests-XXXXXX")
    run_atlas "$dir" project
    assert_exit_code 1 "$EXIT_CODE" "project fails outside a git repo" || return 1
    assert_json_field "$OUTPUT" '.error' "not_a_git_repo" "error code" || return 1
    cleanup_fixture_repo "$dir"
}
