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
        return _HashToken(1)

class _HashToken:
    pass
PY
    cat > "$repo/src/api/client.py" <<'PY'
from src.auth.service import _HashToken

def send(kind):
    return _HashToken(kind)
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
    # AuthService is public → Public API; _HashToken is private but referenced
    # cross-file → Load-bearing internals.
    local api lb
    api=$(awk '/## Public API/,/## Load-bearing/' "$doc")
    lb=$(awk '/## Load-bearing internals/,/## Relationships/' "$doc")
    echo "$api" | grep -q 'AuthService' || { echo "    FAIL: AuthService not in Public API"; return 1; }
    echo "$lb" | grep -q '_HashToken' || { echo "    FAIL: _HashToken not in Load-bearing"; return 1; }
    cleanup_fixture_repo "$repo"
}

test_cross_module_relationship_and_refs() {
    local repo; repo=$(_project_fixture)
    run_atlas "$repo" project
    local doc="$repo/docs/atlas/modules/src-api.md"
    # send (src-api) calls _HashToken (src-auth) → a cross-module edge, and
    # src-auth must appear in references_modules.
    grep -q 'src-api.send -> src-auth._HashToken (calls)' "$doc" || {
        echo "    FAIL: cross-module relationship not rendered"; cat "$doc"; return 1; }
    grep -q 'references_modules: \[src-auth\]' "$doc" || {
        echo "    FAIL: references_modules not set"; return 1; }
    cleanup_fixture_repo "$repo"
}

# ingest_edge_semantic <repo> <value-json>
# Finds the (single) edge.semantic key the fixture plans and ingests <value-json>
# as its value. The fixture has exactly one resolved cross-module edge:
# src-api.send -> src-auth._HashToken.
ingest_edge_semantic() {
    local repo="$1" value="$2"
    run_atlas "$repo" judge-plan
    local key
    key=$(echo "$OUTPUT" | jq -r '.missing_keys[] | select(.kind=="edge.semantic") | .key' | head -1)
    [ -n "$key" ] || { echo "    (no edge.semantic key planned)"; return 1; }
    printf '[{"key":"%s","kind":"edge.semantic","value":%s}]' "$key" "$value" \
        | (cd "$repo" && python3 "$CLI" judgment ingest >/dev/null)
}

test_edge_semantic_cell_is_planned() {
    local repo; repo=$(_project_fixture)
    run_atlas "$repo" judge-plan
    # One edge.semantic cell, anchored at the calling symbol, naming the target.
    local cell
    cell=$(echo "$OUTPUT" | jq -c '[.missing_keys[] | select(.kind=="edge.semantic")]')
    assert_eq "1" "$(echo "$cell" | jq 'length')" "exactly one edge.semantic planned" || return 1
    assert_json_field "$cell" '.[0].symbol' "src/api/client.py::send" "anchored at caller" || return 1
    assert_json_field "$cell" '.[0].to' "src/auth/service.py::_HashToken" "names the resolved target" || return 1
    cleanup_fixture_repo "$repo"
}

test_edge_semantic_verb_replaces_structural_in_relationships() {
    local repo; repo=$(_project_fixture)
    run_atlas "$repo" project   # no cell yet → structural fallback
    grep -q 'src-api.send -> src-auth._HashToken (calls)' "$repo/docs/atlas/modules/src-api.md" \
        || { echo "    FAIL: structural fallback not rendered"; return 1; }

    ingest_edge_semantic "$repo" '{"verb":"reads","to":"src/auth/service.py::_HashToken","why":"send reads the token hasher"}' || return 1
    run_atlas "$repo" project
    local doc="$repo/docs/atlas/modules/src-api.md"
    grep -q 'src-api.send -> src-auth._HashToken (reads)' "$doc" \
        || { echo "    FAIL: judged verb not rendered"; sed -n '/## Relationships/,/## Type/p' "$doc"; return 1; }
    grep -q 'src-api.send -> src-auth._HashToken (calls)' "$doc" \
        && { echo "    FAIL: structural verb should be replaced, not co-rendered"; return 1; }
    # The semantic target's module stays in references_modules.
    grep -q 'references_modules: \[src-auth\]' "$doc" \
        || { echo "    FAIL: references_modules lost the semantic target"; return 1; }
    cleanup_fixture_repo "$repo"
}

test_edge_semantic_null_verb_renders_structural() {
    local repo; repo=$(_project_fixture)
    ingest_edge_semantic "$repo" '{"verb":null}' || return 1
    run_atlas "$repo" project
    grep -q 'src-api.send -> src-auth._HashToken (calls)' "$repo/docs/atlas/modules/src-api.md" \
        || { echo "    FAIL: null verb should render the structural edge"; return 1; }
    cleanup_fixture_repo "$repo"
}

test_edge_semantic_out_of_grammar_verb_falls_back() {
    local repo; repo=$(_project_fixture)
    ingest_edge_semantic "$repo" '{"verb":"frobnicates","to":"src/auth/service.py::_HashToken"}' || return 1
    run_atlas "$repo" project
    local doc="$repo/docs/atlas/modules/src-api.md"
    grep -q 'src-api.send -> src-auth._HashToken (calls)' "$doc" \
        || { echo "    FAIL: an out-of-grammar verb must fall back to the structural verb"; return 1; }
    # …and the rendered doc still passes the L13 verb-grammar check.
    run_atlas "$repo" lint
    assert_eq "0" "$(echo "$OUTPUT" | jq -r '[.errors[]? | select(.check=="L13")] | length')" \
        "no L13 errors after fallback" || return 1
    cleanup_fixture_repo "$repo"
}

test_edge_semantic_reproject_is_byte_identical() {
    local repo; repo=$(_project_fixture)
    ingest_edge_semantic "$repo" '{"verb":"reads","to":"src/auth/service.py::_HashToken","why":"reads the hasher"}' || return 1
    run_atlas "$repo" project
    local h1; h1=$(shasum "$repo/docs/atlas/modules/src-api.md" | awk '{print $1}')
    run_atlas "$repo" project
    assert_json_field "$OUTPUT" '.changed' "0" "re-project with a judged edge rewrites nothing" || return 1
    local h2; h2=$(shasum "$repo/docs/atlas/modules/src-api.md" | awk '{print $1}')
    assert_eq "$h1" "$h2" "edge.semantic render is byte-stable (keying works)" || return 1
    cleanup_fixture_repo "$repo"
}

test_edge_semantic_doc_records_key_in_judgment_keys() {
    local repo; repo=$(_project_fixture)
    ingest_edge_semantic "$repo" '{"verb":"reads","to":"src/auth/service.py::_HashToken","why":"x"}' || return 1
    run_atlas "$repo" project >/dev/null
    run_atlas "$repo" ledger finalize --refresh-hashes --generator "cartographer/4"
    # The src-api doc's per-doc judgment_keys must include its edge.semantic key
    # (drives the v2 ripple: a changed semantic cell re-projects exactly this doc).
    local key
    key=$(jq -r '.judgment_keys["docs/atlas/modules/src-api.md"][]? | select(startswith("edge.semantic/"))' \
        "$repo/docs/atlas/atlas-ledger.json" | head -1)
    [ -n "$key" ] || { echo "    FAIL: edge.semantic key not recorded in ledger judgment_keys"; return 1; }
    cleanup_fixture_repo "$repo"
}

test_project_requires_git_repo() {
    local dir; dir=$(mktemp -d "/tmp/atlas-tests-XXXXXX")
    run_atlas "$dir" project
    assert_exit_code 1 "$EXIT_CODE" "project fails outside a git repo" || return 1
    assert_json_field "$OUTPUT" '.error' "not_a_git_repo" "error code" || return 1
    cleanup_fixture_repo "$dir"
}
