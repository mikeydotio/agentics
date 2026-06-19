#!/usr/bin/env bash
# Tests for `atlas-cli migrate-v1` (Wave 8) — the one-time v1→v2 upgrade that
# re-keys existing v1 doc prose into the Judgment Cache — plus hardening of the
# v2 pipeline on degenerate repos.

_v1_mapped_fixture() {
    local repo
    repo=$(create_fixture_repo)
    mkdir -p "$repo/src"
    cat > "$repo/src/svc.py" <<'PY'
class Service:
    def start(self):
        return 1
PY
    local i
    for i in 1 2 3 4 5; do seed_file "$repo" "src/pad$i.txt"; done
    commit_all "$repo"
    # A v1-style doc citing the real symbol (partition id for src/ is "src").
    ATLAS_TEST_SUMMARY="Legacy v1 summary" \
        write_full_module_doc "$repo" "src" "src" "Service" "src/svc.py"
    echo "$repo"
}

test_migrate_rekeys_v1_prose() {
    local repo; repo=$(_v1_mapped_fixture)
    run_atlas "$repo" migrate-v1
    assert_exit_code 0 "$EXIT_CODE" "migrate exits 0" || return 1
    assert_json_field "$OUTPUT" '.ok' "true" "ok" || return 1
    local migrated; migrated=$(echo "$OUTPUT" | jq -r '.migrated')
    [ "$migrated" -ge 2 ] || { echo "    FAIL: expected >=2 cells migrated, got $migrated"; return 1; }
    assert_file_exists "$repo/docs/atlas/judgments.json" "cache written" || return 1
    # Cells carry the migrated provenance.
    local prov
    prov=$(jq -r '[.judgments[] | select(.provenance.generator=="migrated/v1")] | length' \
        "$repo/docs/atlas/judgments.json")
    [ "$prov" -ge 2 ] || { echo "    FAIL: migrated provenance missing"; return 1; }
    cleanup_fixture_repo "$repo"
}

test_migrate_contract_round_trips_to_projection() {
    local repo; repo=$(_v1_mapped_fixture)
    run_atlas "$repo" migrate-v1 >/dev/null
    # The v1 contract prose ("Does fixture things") should now render for Service.
    run_atlas "$repo" project >/dev/null
    grep -q 'Does fixture things' "$repo/docs/atlas/modules/src.md" || {
        echo "    FAIL: migrated contract not rendered"; return 1; }
    # And the v1 Purpose prose migrated too.
    grep -q 'Handles src concerns' "$repo/docs/atlas/modules/src.md" || {
        echo "    FAIL: migrated purpose not rendered"; return 1; }
    cleanup_fixture_repo "$repo"
}

test_migrate_reduces_missing_cells() {
    local repo; repo=$(_v1_mapped_fixture)
    local before
    run_atlas "$repo" judge-plan
    before=$(echo "$OUTPUT" | jq -r '.missing_count')
    run_atlas "$repo" migrate-v1
    local still; still=$(echo "$OUTPUT" | jq -r '.still_missing')
    [ "$still" -lt "$before" ] || {
        echo "    FAIL: migration should reduce missing cells ($before -> $still)"; return 1; }
    cleanup_fixture_repo "$repo"
}

test_migrate_reports_unmappable_symbols() {
    local repo; repo=$(_v1_mapped_fixture)
    # Add a v1 doc row citing a symbol that does NOT exist in the source.
    local doc="$repo/docs/atlas/modules/src.md"
    python3 - "$doc" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
row = "| `GhostSymbol` | class | `src/svc.py:1` | Phantom contract |\n"
t = t.replace("| `Service` | class | `src/svc.py:1` | Does fixture things |\n",
              "| `Service` | class | `src/svc.py:1` | Does fixture things |\n" + row)
open(p, "w").write(t)
PY
    run_atlas "$repo" migrate-v1
    local unmapped
    unmapped=$(echo "$OUTPUT" | jq -r '[.unmapped[]? | select(.symbol=="GhostSymbol")] | length')
    [ "$unmapped" -ge 1 ] || { echo "    FAIL: GhostSymbol should be unmapped"; return 1; }
    cleanup_fixture_repo "$repo"
}

test_migrate_does_not_clobber_existing_cells() {
    local repo; repo=$(_v1_mapped_fixture)
    # Pre-seed a real judgment for Service's contract.
    run_atlas "$repo" judge-plan
    local key
    key=$(echo "$OUTPUT" | jq -r '.missing_keys[] | select(.kind=="symbol.contract") | .key' | head -1)
    printf '[{"key":"%s","kind":"symbol.contract","value":"FRESH JUDGMENT"}]' "$key" \
        | (cd "$repo" && python3 "$CLI" judgment ingest >/dev/null)
    run_atlas "$repo" migrate-v1 >/dev/null
    local v; v=$(jq -r --arg k "$key" '.judgments[$k].value' "$repo/docs/atlas/judgments.json")
    assert_eq "FRESH JUDGMENT" "$v" "migrate must not overwrite a real judgment" || return 1
    cleanup_fixture_repo "$repo"
}

test_migrate_without_v1_map_fails_cleanly() {
    local repo; repo=$(create_fixture_repo)
    mkdir -p "$repo/src"; seed_file "$repo" "src/a.py"; commit_all "$repo"
    run_atlas "$repo" migrate-v1
    assert_exit_code 1 "$EXIT_CODE" "no v1 map → fails" || return 1
    assert_json_field "$OUTPUT" '.error' "no_v1_map" "error code" || return 1
    cleanup_fixture_repo "$repo"
}

# ── Hardening: the v2 pipeline survives degenerate repos ────────────────────
test_extract_empty_repo() {
    local repo; repo=$(create_fixture_repo)
    git -C "$repo" commit -q --allow-empty -m empty
    run_atlas "$repo" extract
    assert_json_field "$OUTPUT" '.ok' "true" "extract ok on empty repo" || return 1
    assert_json_field "$OUTPUT" '.symbol_count' "0" "no symbols" || return 1
    run_atlas "$repo" judge-plan
    assert_json_field "$OUTPUT" '.total_expected' "0" "no cells expected" || return 1
    cleanup_fixture_repo "$repo"
}

test_project_empty_repo_is_noop() {
    local repo; repo=$(create_fixture_repo)
    git -C "$repo" commit -q --allow-empty -m empty
    run_atlas "$repo" project
    assert_json_field "$OUTPUT" '.doc_count' "0" "no docs to project" || return 1
    cleanup_fixture_repo "$repo"
}

test_ambiguous_heavy_untyped_repo() {
    local repo; repo=$(create_fixture_repo)
    mkdir -p "$repo/src"
    # The same method name defined in many files — every call is ambiguous.
    local i
    for i in 1 2 3 4 5 6; do
        cat > "$repo/src/mod$i.py" <<PY
def run(x):
    return x

def caller$i():
    return run($i)
PY
    done
    commit_all "$repo"
    run_atlas "$repo" extract
    assert_json_field "$OUTPUT" '.ok' "true" "extract ok on ambiguous repo" || return 1
    # Calls to `run` are ambiguous (6 defs) → recorded, but no resolved noise.
    local amb; amb=$(echo "$OUTPUT" | jq -r '.ambiguous_edge_count')
    [ "$amb" -ge 1 ] || { echo "    FAIL: expected ambiguous edges"; return 1; }
    # judge-plan + project must still complete cleanly.
    run_atlas "$repo" project
    assert_json_field "$OUTPUT" '.ok' "true" "project ok on ambiguous repo" || return 1
    cleanup_fixture_repo "$repo"
}
